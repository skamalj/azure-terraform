import os
import io
import base64
import time
import asyncio
import torch
from PIL import Image, ImageOps
from fastapi import FastAPI
from pydantic import BaseModel
from fastapi.responses import JSONResponse

from vllm import AsyncLLMEngine, SamplingParams
from vllm.engine.arg_utils import AsyncEngineArgs
from vllm.model_executor.models.registry import ModelRegistry

# --- your custom imports ---
from deepseek_ocr import DeepseekOCRForCausalLM
from process.ngram_norepeat import NoRepeatNGramLogitsProcessor
from process.image_process import DeepseekOCRProcessor
from config import MODEL_PATH, CROP_MODE

# --- environment setup ---
if torch.version.cuda == "11.8":
    os.environ["TRITON_PTXAS_PATH"] = "/usr/local/cuda-11.8/bin/ptxas"
os.environ["VLLM_USE_V1"] = "0"
os.environ["CUDA_VISIBLE_DEVICES"] = "0"

# --- register custom model ---
ModelRegistry.register_model("DeepseekOCRForCausalLM", DeepseekOCRForCausalLM)

# --- FastAPI app ---
app = FastAPI(title="DeepSeek OCR API", version="1.0")

# --- global engine (loaded once) ---
engine_args = AsyncEngineArgs(
    model=MODEL_PATH,
    hf_overrides={"architectures": ["DeepseekOCRForCausalLM"]},
    block_size=256,
    max_model_len=8192,
    trust_remote_code=True,
    tensor_parallel_size=1,
    gpu_memory_utilization=0.75,
)
engine = AsyncLLMEngine.from_engine_args(engine_args)

# --- request model ---
class OCRRequest(BaseModel):
    prompt: str
    image_base64: str

# --- helper functions ---
def decode_base64_to_image(b64_string: str) -> Image.Image:
    image_bytes = base64.b64decode(b64_string)
    image = Image.open(io.BytesIO(image_bytes))
    image = ImageOps.exif_transpose(image).convert("RGB")
    return image


async def run_ocr(prompt: str, image: Image.Image) -> str:
    # Convert image to model input features
    image_features = (
        DeepseekOCRProcessor().tokenize_with_images(
            images=[image], bos=True, eos=True, cropping=CROP_MODE
        )
        if "<image>" in prompt
        else ""
    )

    logits_processors = [
        NoRepeatNGramLogitsProcessor(
            ngram_size=30, window_size=90, whitelist_token_ids={128821, 128822}
        )
    ]

    sampling_params = SamplingParams(
        temperature=0.0,
        max_tokens=8192,
        logits_processors=logits_processors,
        skip_special_tokens=False,
    )

    request_id = f"req-{int(time.time())}"

    request = (
        {"prompt": prompt, "multi_modal_data": {"image": image_features}}
        if "<image>" in prompt
        else {"prompt": prompt}
    )

    final_output = ""
    async for result in engine.generate(request, sampling_params, request_id):
        if result.outputs:
            final_output = result.outputs[0].text
    return final_output


# --- endpoint ---
@app.post("/ocr")
async def ocr_endpoint(data: OCRRequest):
    try:
        image = decode_base64_to_image(data.image_base64)
        output_text = await run_ocr(data.prompt, image)
        return {"text_output": output_text}
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)


@app.get("/health")
def health_check():
    return {"status": "ok"}
