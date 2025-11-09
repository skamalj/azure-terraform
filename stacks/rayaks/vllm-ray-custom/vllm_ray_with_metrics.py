"""
Ray Serve + vLLM OpenAI-Compatible App
IMPROVED VERSION with Eager Initialization + Resilient Config
For vLLM 0.6+ (2024-2025)
"""

import os
import asyncio
from typing import Dict, Optional
import logging
from fastapi import FastAPI, Request
from fastapi.responses import StreamingResponse, JSONResponse, Response

from ray import serve
from vllm.engine.arg_utils import AsyncEngineArgs
from vllm.engine.async_llm_engine import AsyncLLMEngine
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

from prometheus_client import generate_latest, REGISTRY

logger = logging.getLogger("ray.serve")

app = FastAPI()


# ========== HELPER: Run async in sync __init__ ==========
def run_async_in_thread(coro):
    """Run async code from sync context."""
    loop = asyncio.new_event_loop()
    try:
        return loop.run_until_complete(coro)
    finally:
        loop.close()


@serve.deployment(
    autoscaling_config={
        "min_replicas": 1,
        "max_replicas": 2,
        "target_ongoing_requests": 5,
    },
    max_ongoing_requests=10,
)
@serve.ingress(app)
class LLMServer:
    """Ray Serve LLM with eager initialization and resilient config."""
    
    def __init__(
        self,
        model: str = "Qwen/Qwen2.5-0.5B-Instruct",
        engine_kwargs: Optional[Dict] = None,
        response_role: str = "assistant",
    ):
        """Initialize with EAGER initialization (no lazy loading)."""
        self.model = model
        self.response_role = response_role
        
        print("\n" + "="*80)
        print("INITIALIZING VLLM SERVER (EAGER MODE)")
        print("="*80)
        
        # ========== RESILIENT DEFAULTS ==========
        resilient_defaults = {
            "dtype": "float16",                 # Explicit, safe
            "enforce_eager": True,              # No CUDA graphs - stable!
            "max_model_len": 2048,              # Conservative
            "gpu_memory_utilization": 0.7,      # Safe (not aggressive)
            "max_num_seqs": 128,                # Moderate concurrency
            "max_num_batched_tokens": 4096,
            "enable_prefix_caching": False,     # Disabled for stability
            "chunked_prefill_enabled": False,   # Disabled for stability
            "tensor_parallel_size": 1,
            "pipeline_parallel_size": 1,
            "disable_log_stats": False,
            "quantization": None,
            "load_format": "auto",
            "seed": 0,
        }
        
        if engine_kwargs:
            resilient_defaults.update(engine_kwargs)
        
        self.engine_kwargs = resilient_defaults
        
        print(f"1️⃣  Creating vLLM engine...")
        print(f"   Model: {model}")
        print(f"   Config: enforce_eager={self.engine_kwargs['enforce_eager']}")
        
        # Create engine
        engine_args = AsyncEngineArgs(
            model=model,
            distributed_executor_backend="ray",
            **self.engine_kwargs
        )
        
        self.engine = AsyncLLMEngine.from_engine_args(engine_args)
        print(f"   ✓ Engine created")
        
        # ========== EAGER INITIALIZATION ==========
        print(f"2️⃣  Eagerly initializing OpenAI serving...")
        
        try:
            self.openai_serving_chat = run_async_in_thread(
                self._async_init_openai_serving()
            )
            print(f"   ✓ OpenAI serving initialized")
            print(f"✅ SERVER READY!\n")
        except Exception as e:
            print(f"   ✗ ERROR: {str(e)}")
            print(f"   Using fallback lazy initialization\n")
            self.openai_serving_chat = None
    
    async def _async_init_openai_serving(self):
        """Async initialization of OpenAI serving."""
        model_config = await self.engine.get_model_config()
        
        base_model_paths = [
            BaseModelPath(name=self.model, model_path=self.model)
        ]
        
        models = OpenAIServingModels(
            engine_client=self.engine,
            model_config=model_config,
            base_model_paths=base_model_paths,
        )
        
        openai_serving_chat = OpenAIServingChat(
            engine_client=self.engine,
            model_config=model_config,
            models=models,
            response_role=self.response_role,
            request_logger=None,
            chat_template=None,
            chat_template_content_format="auto",
        )
        
        return openai_serving_chat
    
    async def _ensure_initialized(self):
        """Ensure engine is initialized (lazy fallback if eager failed)."""
        if self.openai_serving_chat is None:
            self.openai_serving_chat = await self._async_init_openai_serving()
    
    @app.get("/health")
    async def health(self):
        """Health check."""
        return {
            "status": "healthy",
            "model": self.model,
            "initialized": self.openai_serving_chat is not None,
        }
    
    @app.get("/metrics")
    async def metrics(self):
        """Prometheus metrics."""
        try:
            metrics_output = generate_latest(REGISTRY)
            return Response(content=metrics_output, media_type="text/plain")
        except Exception as e:
            logger.error(f"Error generating metrics: {str(e)}")
            return Response(content=f"Error: {str(e)}", status_code=500)
    
    @app.get("/v1/models")
    async def list_models(self):
        """List models."""
        return {
            "object": "list",
            "data": [{"id": self.model, "object": "model", "owned_by": "vllm"}]
        }
    
    @app.post("/v1/chat/completions")
    async def create_chat_completion(
        self,
        request: ChatCompletionRequest,
        raw_request: Request,
    ):
        """OpenAI-compatible chat completions."""
        try:
            await self._ensure_initialized()
            
            generator = await self.openai_serving_chat.create_chat_completion(
                request, raw_request
            )
            
            if isinstance(generator, ErrorResponse):
                return JSONResponse(
                    content=generator.model_dump(),
                    status_code=generator.code
                )
            
            if request.stream:
                return StreamingResponse(
                    content=generator,
                    media_type="text/event-stream"
                )
            else:
                return JSONResponse(content=generator.model_dump())
        
        except Exception as e:
            logger.error(f"Error: {str(e)}", exc_info=True)
            return JSONResponse(
                content={"error": str(e)},
                status_code=500
            )


def build_openai_app(
    model: str = "Qwen/Qwen2.5-0.5B-Instruct",
    engine_kwargs: Optional[Dict] = None,
) -> serve.Application:
    """Build OpenAI-compatible LLM serving application."""
    print("\n" + "="*80)
    print("BUILDING OPENAI-COMPATIBLE VLLM RAY SERVE APPLICATION")
    print("="*80)
    return LLMServer.bind(
        model=model,
        engine_kwargs=engine_kwargs,
    )


#if __name__ == "__main__":
#    os.environ.setdefault("PROMETHEUS_MULTIPROC_DIR", "/tmp/prometheus")
#    
#    app = build_openai_app(
#        model="Qwen/Qwen2.5-0.5B-Instruct",
#        engine_kwargs={
#            "dtype": "float16",
#            "enforce_eager": True,           # ✅ Stable
#            "max_model_len": 2048,
#            "gpu_memory_utilization": 0.7,   # ✅ Conservative
#            "max_num_seqs": 128,
#            "enable_prefix_caching": False,  # ✅ Stable
#        }
#    )
#    
#    serve.run(app, blocking=True, host="0.0.0.0", port=8000)
