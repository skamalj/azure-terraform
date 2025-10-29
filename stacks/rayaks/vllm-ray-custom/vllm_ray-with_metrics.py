from ray import serve
from fastapi import FastAPI, Response
from starlette.requests import Request
from starlette.responses import StreamingResponse, JSONResponse
from prometheus_client import REGISTRY, generate_latest, CONTENT_TYPE_LATEST
from typing import Dict, Any
import logging

from vllm.engine.arg_utils import AsyncEngineArgs
from vllm.engine.async_llm_engine import AsyncLLMEngine
from vllm.engine.metrics import RayPrometheusStatLogger
from vllm.entrypoints.openai.serving_chat import OpenAIServingChat
from vllm.entrypoints.openai.serving_models import BaseModelPath, OpenAIServingModels
from vllm.entrypoints.openai.protocol import ChatCompletionRequest, ErrorResponse, ChatCompletionResponse

logger = logging.getLogger("ray.serve")
app = FastAPI(title="Multi-vLLM RayServe", version="1.0.0")


@serve.deployment(
    autoscaling_config={
        "min_replicas": 1,
        "max_replicas": 4,
        "target_ongoing_requests": 10,
        "upscale_delay_s": 10,
        "downscale_delay_s": 600,
    },
    ray_actor_options={"num_gpus": 1, "object_store_memory": 1_000_000_000},
    max_ongoing_requests=100,
)
@serve.ingress(app)
class MultiVLLMDeployment:
    """Generic multi-model vLLM deployment with metrics."""

    def __init__(self, llm_configs: list[Dict[str, Any]]):
        self.models = {}
        self.deployment_ready = False

        logger.info(f"Initializing {len(llm_configs)} vLLM models...")

        for cfg in llm_configs:
            model_id = cfg["model_id"]
            model_source = cfg["model_source"]
            tp = int(cfg.get("tensor_parallel_size", 1))
            pp = int(cfg.get("pipeline_parallel_size", 1))
            max_len = int(cfg.get("max_model_len", 8192))
            gpu_util = float(cfg.get("gpu_memory_utilization", 0.9))
            dtype = cfg.get("dtype", "auto")
            prefix_cache = cfg.get("enable_prefix_caching", True)
            chunked_prefill = cfg.get("enable_chunked_prefill", True)

            logger.info(f"→ Loading {model_id} from {model_source}")

            engine_args = AsyncEngineArgs(
                model=model_source,
                tensor_parallel_size=tp,
                pipeline_parallel_size=pp,
                max_model_len=max_len,
                gpu_memory_utilization=gpu_util,
                dtype=dtype,
                enable_prefix_caching=prefix_cache,
                enable_chunked_prefill=chunked_prefill,
                worker_use_ray=True,
            )

            try:
                engine = AsyncLLMEngine.from_engine_args(engine_args)
                model_name = engine_args.served_model_name or model_source.split("/")[-1]
                metrics_logger = RayPrometheusStatLogger(
                    local_interval=0.5,
                    labels={"model_name": model_name, "model_id": model_id},
                    max_model_len=max_len,
                )
                engine.add_logger("ray", metrics_logger)

                # Prepare OpenAI-compatible serving interface
                model_config = engine_args.create_model_config()
                models = OpenAIServingModels(
                    engine,
                    model_config,
                    [BaseModelPath(name=model_id, model_path=model_source)],
                )
                openai_serving_chat = OpenAIServingChat(
                    engine,
                    model_config,
                    models,
                    response_role="assistant",
                )

                self.models[model_id] = {
                    "engine": engine,
                    "chat": openai_serving_chat,
                    "metrics": metrics_logger,
                }

                logger.info(f"✓ Model {model_id} initialized.")
            except Exception as e:
                logger.error(f"✗ Failed to initialize model {model_id}: {e}", exc_info=True)

        self.deployment_ready = len(self.models) > 0
        logger.info(f"Deployment ready with models: {list(self.models.keys())}")

    @app.get("/health")
    async def health(self):
        return {"status": "healthy" if self.deployment_ready else "unhealthy",
                "models": list(self.models.keys())}

    @app.get("/v1/models")
    async def list_models(self):
        return {"object": "list",
                "data": [{"id": mid, "object": "model"} for mid in self.models.keys()]}

    @app.get("/metrics")
    async def metrics(self):
        try:
            return Response(content=generate_latest(REGISTRY), media_type=CONTENT_TYPE_LATEST)
        except Exception as e:
            return Response(f"metrics error: {e}", media_type="text/plain", status_code=500)

    @app.post("/v1/chat/completions")
    async def create_chat_completion(self, request: ChatCompletionRequest, raw_request: Request):
        if not self.deployment_ready:
            return JSONResponse(content={"error": "No models loaded"}, status_code=503)

        model_id = getattr(request, "model", None)
        if model_id not in self.models:
            return JSONResponse(content={"error": f"Model '{model_id}' not found"}, status_code=404)

        model_entry = self.models[model_id]
        try:
            generator = await model_entry["chat"].create_chat_completion(request, raw_request)
            if isinstance(generator, ErrorResponse):
                return JSONResponse(content=generator.model_dump(), status_code=generator.code)
            if request.stream:
                return StreamingResponse(content=generator, media_type="text/event-stream")
            else:
                return JSONResponse(content=generator.model_dump())
        except Exception as e:
            logger.error(f"Inference error for {model_id}: {e}", exc_info=True)
            return JSONResponse(content={"error": str(e)}, status_code=500)
