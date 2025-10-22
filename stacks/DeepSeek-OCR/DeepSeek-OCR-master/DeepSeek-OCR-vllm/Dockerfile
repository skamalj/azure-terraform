# --------------------------------------------------------
# Base image: vLLM with CUDA (already includes PyTorch + vLLM)
# --------------------------------------------------------
FROM vllm/vllm-openai:v0.11.0

# --------------------------------------------------------
# Environment setup
# --------------------------------------------------------
ENV PYTHONUNBUFFERED=1
ENV VLLM_USE_V1=0
ENV CUDA_VISIBLE_DEVICES=0

# --------------------------------------------------------
# Remove preinstalled vLLM
# --------------------------------------------------------
RUN pip uninstall -y vllm || true

# --------------------------------------------------------
# Install dependencies required by DeepSeek-OCR
# As per https://github.com/deepseek-ai/DeepSeek-OCR
# --------------------------------------------------------
RUN pip install --no-cache-dir \
    torch==2.6.0 torchvision==0.21.0 torchaudio==2.6.0 --index-url https://download.pytorch.org/whl/cu118 \
    fastapi uvicorn pillow tqdm numpy


# --------------------------------------------------------
# Download and install vLLM 0.8.5 manually
# --------------------------------------------------------
WORKDIR /tmp
RUN curl -L -o vllm-0.8.5+cu118-cp38-abi3-manylinux1_x86_64.whl \
    https://github.com/vllm-project/vllm/releases/download/v0.8.5/vllm-0.8.5+cu118-cp38-abi3-manylinux1_x86_64.whl && \
    pip install ./vllm-0.8.5+cu118-cp38-abi3-manylinux1_x86_64.whl && \
    rm -f vllm-0.8.5+cu118-cp38-abi3-manylinux1_x86_64.whl

# --------------------------------------------------------
# Copy application code
# --------------------------------------------------------
WORKDIR /app

# FastAPI app
COPY fastapi_deepseek_ocr.py /app/fastapi_deepseek_ocr.py

# DeepSeek model + processors + config
COPY deepseek_ocr.py /app/deepseek_ocr.py
COPY process /app/process
COPY deepencoder /app/deepencoder
COPY config.py /app/config.py

# Optional: If DeepSeek repo has its own requirements.txt
COPY requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt || true

RUN pip install flash-attn==2.7.3 --no-build-isolation
# --------------------------------------------------------
# Expose the FastAPI port
# --------------------------------------------------------
EXPOSE 8080

# --------------------------------------------------------
# Launch FastAPI app
# --------------------------------------------------------
CMD ["uvicorn", "fastapi_deepseek_ocr:app", "--host", "0.0.0.0", "--port", "8080"]
