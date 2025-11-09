"""
Ray Serve + vLLM OpenAI-Compatible App with Metrics
Updated for vLLM 0.6+ (2024-2025)
Exposes VLLM metrics via RayPrometheusStatLogger to Ray's internal metrics (port 8080)

Simplified configuration:
- bind() takes single dictionary argument
- request_logger and chat_template initialized internally
"""

from typing import Dict, Optional, List
import logging
from fastapi import FastAPI, Request
from fastapi.responses import StreamingResponse, JSONResponse
import os

from vllm.entrypoints.openai.serving_models import (
    OpenAIServingModels,
    BaseModelPath,
)


from ray import serve
from ray.serve import Application

# vLLM v1 imports
from vllm.engine.arg_utils import AsyncEngineArgs
from vllm.v1.engine.async_llm import AsyncLLM
from vllm.v1.executor.abstract import Executor
from vllm.v1.metrics.ray_wrappers import RayPrometheusStatLogger
from vllm.usage.usage_lib import UsageContext
from vllm.platforms import current_platform

# Use OpenAIServingChat directly - not init_app_state
from vllm.entrypoints.openai.protocol import (
    ChatCompletionRequest,
    ChatCompletionResponse,
    ErrorResponse as VLLMErrorResponse,
)
from vllm.entrypoints.openai.serving_chat import OpenAIServingChat

os.environ["SERVE_HTTP_HOST"] = "0.0.0.0"
logger = logging.getLogger("ray.serve")
app = FastAPI()

@serve.deployment(
    ray_actor_options={"num_cpus": 1},
    autoscaling_config={
        "min_replicas": 0,
        "initial_replicas": 0,
        "max_replicas": 5,
        "target_ongoing_requests": 2,
        "upscale_delay_s": 15,
        "downscale_delay_s": 120,
        "metrics_interval_s": 5,
        "look_back_period_s": 10,
    },
    max_ongoing_requests=15,
)
@serve.ingress(app)
class LLMServer:
    """Ray Serve deployment for vLLM v1 engine."""

    def __init__(
        self,
        model: str,
        engine_kwargs: Optional[Dict] = None,
        response_role: str = "assistant",
        chat_template: Optional[str] = None,  # ✅ Add this parameter
    ):
        self.model = model
        self.engine_kwargs = engine_kwargs or {}
        self.response_role = response_role
        self.chat_template = chat_template  # Store it

        logger.info(f"🚀 Initializing vLLM v1 engine with model: {model}")

        # Build engine args - DON'T add chat_template here
        engine_args = AsyncEngineArgs(
            model=model,
            distributed_executor_backend="ray",
            **self.engine_kwargs,
        )

        # Clear platform cache
        if hasattr(current_platform.get_device_capability, "cache_clear"):
            current_platform.get_device_capability.cache_clear()

        # Build engine config for v1
        engine_config = engine_args.create_engine_config(
            usage_context=UsageContext.OPENAI_API_SERVER
        )

        # Get executor
        executor_class = Executor.get_class(engine_config)

        # ✅ KEY FIX: Create stat logger factory as a callable
        def create_ray_metrics_logger(vllm_config, engine_index: int = 0):
            return RayPrometheusStatLogger(
                vllm_config=vllm_config
            )

        # ✅ Initialize AsyncLLM with metrics
        self.engine = AsyncLLM(
            vllm_config=engine_config,
            executor_class=executor_class,
            log_stats=not engine_args.disable_log_stats,
            stat_loggers=[create_ray_metrics_logger],
        )
        logger.info("✓ vLLM v1 AsyncLLM initialized")

        # Store for later use
        self.openai_serving_chat = None
        self.engine_config = engine_config

    async def _init_openai_serving(self):
        """Initialize OpenAIServingChat after engine is ready."""
        if self.openai_serving_chat is not None:
            return

        logger.info("Initializing OpenAI-compatible serving...")
        try:
            # Get model config from the engine
            model_config = await self.engine.get_model_config()


            # v1 requires OpenAIServingModels
            base_model_paths = [
                BaseModelPath(name=self.model, model_path=self.model)
            ]

            models = OpenAIServingModels(
                engine_client=self.engine,
                model_config=model_config,
                base_model_paths=base_model_paths,
            )

            self.openai_serving_chat = OpenAIServingChat(
                engine_client=self.engine,
                model_config=model_config,
                models=models,
                response_role=self.response_role,
                request_logger=None,
                chat_template=self.chat_template,
                chat_template_content_format="auto",
            )
            logger.info("✓ OpenAI serving chat initialized successfully")
        except Exception as e:
            logger.error(f"Failed to initialize OpenAI serving: {e}")
            raise

    @app.get("/health")
    async def health(self):
        """Health check endpoint."""
        try:
            await self.engine.check_health()
            return {"status": "healthy", "model": self.model}
        except Exception as e:
            return {"status": "unhealthy", "error": str(e)}

    @app.get("/v1/models")
    async def list_models(self):
        """List available models."""
        return {
            "object": "list",
            "data": [
                {
                    "id": self.model,
                    "object": "model",
                    "owned_by": "vllm",
                }
            ],
        }

    @app.post("/v1/chat/completions")
    async def create_chat_completion(
        self,
        request: ChatCompletionRequest,
        raw_request: Request,
    ):
        """OpenAI-compatible /v1/chat/completions endpoint."""
        try:
            await self._init_openai_serving()
            logger.info(f"🗨️ Chat completion request - model: {request.model}")

            generator = await self.openai_serving_chat.create_chat_completion(
                request, raw_request
            )

            if isinstance(generator, VLLMErrorResponse):
                logger.error(f"vLLM error: {generator.error.message}")
                return JSONResponse(
                    content=generator.model_dump(),
                    status_code=500,
                )

            if request.stream:
                return StreamingResponse(
                    content=generator, media_type="text/event-stream"
                )

            assert isinstance(generator, ChatCompletionResponse)
            return JSONResponse(content=generator.model_dump())

        except Exception as e:
            logger.exception(f"Chat completion failed: {e}")
            return JSONResponse(content={"error": str(e)}, status_code=500)


def build_app(args: Dict[str, str]) -> Application:
    """Build OpenAI-compatible Ray Serve application for vLLM v1."""

    config = {
        "model": args.get("model", "Qwen/Qwen2.5-0.5B-Instruct"),
        "engine_kwargs": args.get(
            "engine_kwargs",
            {
                "tensor_parallel_size": 1,
                "dtype": "float16",
                "max_model_len": 2048,
                "gpu_memory_utilization": 0.7,
                "disable_log_stats": False
            },
        ),
        "response_role": args.get("response_role", "assistant"),
        # ✅ Add chat_template here if needed (Qwen2.5 has built-in, but explicit is better)
        "chat_template": args.get("chat_template", None),
    }

    return LLMServer.bind(**config)
