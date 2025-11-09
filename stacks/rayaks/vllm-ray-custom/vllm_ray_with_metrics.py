"""
Ray Serve + vLLM OpenAI-Compatible App with Metrics
Updated for vLLM 0.6+ (2024-2025)
Exposes VLLM metrics via RayPrometheusStatLogger to Ray's internal metrics (port 8080)

Simplified configuration:
- bind() takes single dictionary argument
- request_logger and chat_template initialized internally
"""

from typing import Dict, Optional, List, Union
import logging
from fastapi import FastAPI, Request
from fastapi.responses import StreamingResponse, JSONResponse, Response
import os

from ray import serve
from ray.serve import Application
from vllm.engine.arg_utils import AsyncEngineArgs
from vllm.engine.async_llm_engine import AsyncLLMEngine
from vllm.engine.metrics import RayPrometheusStatLogger
from vllm.entrypoints.openai.protocol import (
    ChatCompletionRequest,
    ChatCompletionResponse,
    ErrorResponse,
)
from vllm.entrypoints.openai.serving_chat import OpenAIServingChat
from vllm.entrypoints.openai.serving_models import (
    OpenAIServingModels,
    BaseModelPath,
)

# ✅ Set HTTP host to 0.0.0.0
os.environ["SERVE_HTTP_HOST"] = "0.0.0.0"

logger = logging.getLogger("ray.serve")

app = FastAPI()


def get_served_model_names(engine_args: AsyncEngineArgs) -> List[str]:
    """Extract served model names from engine args."""
    if engine_args.served_model_name is not None:
        served_model_names: Union[str, List[str]] = engine_args.served_model_name
        if isinstance(served_model_names, str):
            served_model_names: List[str] = [served_model_names]
    else:
        served_model_names: List[str] = [engine_args.model]
    return served_model_names


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
    """
    Ray Serve LLM deployment using vLLM engine with metrics.
    
    Autoscales from 0 to 5 replicas based on load.
    Metrics exposed via Ray's internal endpoint (port 8080).
    """

    def __init__(
        self,
        model: str,
        engine_kwargs: Optional[Dict] = None,
        response_role: str = "assistant",
    ):
        """
        Initialize the LLM server with metrics.

        Args:
            model: Model ID from HuggingFace or local path
            engine_kwargs: vLLM engine configuration parameters
            response_role: Response role for OpenAI API (default: "assistant")
        """
        self.model = model
        self.engine_kwargs = engine_kwargs or {}
        self.response_role = response_role

        logger.info(f"Initializing vLLM engine with model: {model}")
        logger.info(f"Engine kwargs: {self.engine_kwargs}")

        # ✅ Ensure disable_log_stats is False to enable metrics
        self.engine_kwargs.setdefault("disable_log_stats", False)

        # Create AsyncEngineArgs
        engine_args = AsyncEngineArgs(
            model=model,
            distributed_executor_backend="ray",
            **self.engine_kwargs
        )

        # Initialize the vLLM async engine
        self.engine = AsyncLLMEngine.from_engine_args(engine_args)
        logger.info("✓ vLLM engine created")

        # ✅ Add RayPrometheusStatLogger for metrics
        served_model_names = get_served_model_names(engine_args)
        
        try:
            metrics_logger = RayPrometheusStatLogger(
                local_interval=0.5,
                labels=dict(model_name=served_model_names),
                max_model_len=engine_args.max_model_len
            )
            self.engine.add_logger("ray", metrics_logger)
            logger.info("✓ RayPrometheusStatLogger added")
            logger.info("  Metrics: curl http://localhost:8080/metrics | grep vllm")
        except Exception as e:
            logger.warning(f"Failed to add metrics logger: {str(e)}")

        # Will be initialized on first request (lazy init)
        self.openai_serving_chat = None

    async def _init_openai_serving(self):
        """Lazy initialization of OpenAI serving chat."""
        if self.openai_serving_chat is None:
            logger.info("Initializing OpenAI serving chat...")

            model_config = await self.engine.get_model_config()

            # ✅ Auto-fetch chat template from model config
            chat_template = None
            try:
                if hasattr(model_config, 'hf_config') and hasattr(model_config.hf_config, 'chat_template'):
                    chat_template = model_config.hf_config.chat_template
                    logger.info(f"✓ Chat template loaded from model config")
            except Exception as e:
                logger.info(f"No chat template in model config: {str(e)}")

            served_model_names = [self.model]
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
                request_logger=None,  # ✅ No external logger needed
                chat_template=chat_template,  # ✅ Auto-loaded from model
                chat_template_content_format="auto",
            )
            logger.info("✓ OpenAI serving chat initialized successfully")

    @app.get("/health")
    async def health(self):
        """Health check endpoint."""
        return {"status": "healthy", "model": self.model}

    @app.get("/v1/models")
    async def list_models(self):
        """List available models."""
        return {
            "object": "list",
            "data": [{
                "id": self.model,
                "object": "model",
                "owned_by": "vllm",
            }]
        }

    @app.post("/v1/chat/completions")
    async def create_chat_completion(
        self,
        request: ChatCompletionRequest,
        raw_request: Request,
    ):
        """
        OpenAI-compatible chat completions endpoint.
        Handles both streaming and non-streaming requests.
        """
        try:
            await self._init_openai_serving()

            logger.info(f"Chat completion request - Model: {request.model}")

            # Generate response using vLLM
            generator = await self.openai_serving_chat.create_chat_completion(
                request, raw_request
            )

            # Handle errors
            if isinstance(generator, ErrorResponse):
                logger.error(f"Error response: {generator}")
                return JSONResponse(
                    content=generator.model_dump(),
                    status_code=generator.code
                )

            # Return streaming or non-streaming response
            if request.stream:
                return StreamingResponse(
                    content=generator,
                    media_type="text/event-stream"
                )
            else:
                assert isinstance(generator, ChatCompletionResponse)
                return JSONResponse(content=generator.model_dump())

        except Exception as e:
            logger.error(f"Error in chat completion: {str(e)}", exc_info=True)
            return JSONResponse(
                content={"error": str(e)},
                status_code=500
            )


def build_app(args: Dict[str, str]) -> Application:
    """
    Build OpenAI-compatible LLM serving application with metrics.

    Args:
        args: Single dictionary with all configuration:
            - model: Model ID or path
            - engine_kwargs: Dict of vLLM engine parameters
            - response_role: Response role (default: "assistant")

    Returns:
        Ray Serve application

    Example serveConfigV2:
        deployments:
        - name: "LLMServer"
          user_config:
            model: "Qwen/Qwen2.5-0.5B-Instruct"
            engine_kwargs:
              tensor_parallel_size: 1
              dtype: "float16"
              max_model_len: 2048
              gpu_memory_utilization: 0.7
            response_role: "assistant"
    """
    # ✅ Single dictionary argument (extracted from args)
    config = {
        "model": args.get("model", "Qwen/Qwen2.5-0.5B-Instruct"),
        "engine_kwargs": args.get("engine_kwargs", {
            "tensor_parallel_size": 1,
            "dtype": "float16",
            "max_model_len": 2048,
            "gpu_memory_utilization": 0.7,
            "disable_log_stats": False,
        }),
        "response_role": args.get("response_role", "assistant"),
    }

    # ✅ bind() with single dictionary argument
    return LLMServer.bind(**config)
