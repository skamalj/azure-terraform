# vLLM Kubernetes Deployment with Prometheus Monitoring

This repository provides Kubernetes (Specific to Azure Kubernetes Service, due to storage CSI driver) manifests and scripts to deploy a **vLLM inference cluster** with GPU scheduling, persistent storage, and Prometheus-based monitoring.

---

## 📂 Files Overview

* **`head-deployment.yaml`**
  Defines the **head node** deployment for vLLM, which coordinates workers and handles scheduling.

* **`worker-deployment.yaml`**
  Deploys **worker nodes** that run vLLM inference tasks. These attach GPUs and execute model inference.

* **`vllm-api-deployment.yaml`**
  Exposes the **vLLM API service** for external access (e.g., REST or gRPC inference requests).
  ⚠️ **Important:** Update this file to configure health/readiness checks that validate the correct number of **Ray workers** are running. This must align with your parallelism strategy (pipeline, tensor, or data parallel).

  * If you only need **one worker**, the API pod alone is sufficient.
  * If you need **more than one worker**, deploy additional worker pods and ensure the API pod checks are updated accordingly.

* **`nvidia-device-plugin-ds.yaml`**
  Deploys the **NVIDIA Device Plugin DaemonSet**, allowing Kubernetes to schedule and expose GPU resources to pods.

* **`storage-class-model-blob.yaml`**
  Defines a **StorageClass** for model artifacts using blob storage (e.g., Azure Blob or equivalent CSI driver).

* **`pvc.yaml`**
  PersistentVolumeClaim (PVC) to mount the model storage into vLLM pods.

* **`prom-deployment.yaml`**
  Deploys **Prometheus** for monitoring cluster metrics and vLLM performance.

* **`prometheus.sh`**
  Helper script to create the Prometheus ConfigMap and apply it to the cluster.
  Example scrape config included for monitoring the `vllm-api` service.

---

## 🚀 Deployment Steps

### 1. Install NVIDIA GPU Support

Ensure your Kubernetes cluster has GPU-enabled nodes and install the NVIDIA drivers + container runtime.
Apply the device plugin:

```bash
kubectl apply -f nvidia-device-plugin-ds.yaml
```

### 2. Prepare Model Storage

Before deploying vLLM, download your models from **Hugging Face** and upload them to your **Azure Blob Storage** container.

For example:

```bash
# Download a model (example: LLaMA 7B)
git lfs install
git clone https://huggingface.co/meta-llama/Llama-2-7b-hf

# Upload to Azure Blob Storage
az storage blob upload-batch \
  --account-name <your-storage-account> \
  --destination <your-container-name> \
  --source Llama-2-7b-hf
```

Update `storage-class-model-blob.yaml` to point to your Azure Blob CSI configuration.
These models will be mounted into the vLLM pods through the **PVC (pvc.yaml)**.

```yaml
volumeMounts:
  - mountPath: /models
    name: model-storage
```

### 3. Deploy Storage

Set up the storage class and PVC for model weights:

```bash
kubectl apply -f storage-class-model-blob.yaml
kubectl apply -f pvc.yaml
```

### 4. Deploy vLLM Cluster

Deploy the head, workers, and API service:

```bash
kubectl apply -f head-deployment.yaml
kubectl apply -f worker-deployment.yaml
kubectl apply -f vllm-api-deployment.yaml
```

# vLLM Benchmarking Results

## Text Generation Models

This section covers benchmarks for general-purpose text generation models like Llama-3, Mistral, and Qwen.

### Benchmark Table: Text Models
> These tests were with `ShareGPT_V3` dataset available on huggingface

| Model Name | GPU | Pipeline Parallel | No. of seq | Max Model Len | dtype | Token Throughput (tokens/sec) | TTFT (sec) | Cache Util. % | Result | Remark |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| mistral-7b | T4 | 1 | | 4096 | Not Set | | | | Fail | `Bfloat16` not supported on T4 (compute capability 7.5); suggests using `half`. |
| mistral-7b | T4 | 1 | | 4096 | half | | | | Fail | Model Load failure. |
| mistral-7b | T4 | 2 | 32 | 4096 | half | 390 | 2 | | Success | |
| Qwen2.5-7B-Instruct | T4 | 2 | | 4096 | Not Set | | | | Fail | |
| Qwen2.5-7B-Instruct | T4 | 2 | 32 | 4096 | half | 325 | 2 | 12 | Success | |
| Qwen2.5-7B-Instruct | T4 | 2 | 128 | 4096 | half | 320 | 2 | 12 | Success | |
| Meta-Llama-3-8B-Instruct | T4 | 2 | 32 | 8192 | half | 320 | 2 | 25 | Success | |
| Meta-Llama-3-8B-Instruct | T4 | 2 | 32 | 4096 | half | 300 | 3 | 15 | Success | |
| Meta-Llama-3-8B-Instruct | A10 | 1 | 64 | 8192 | None | 700 | 1 | 60 | Success | |
| Meta-Llama-3-8B-Instruct | A10 | 1 | 128 | 16384 | None | | | | Failed | `max_model_len` (16384) exceeds the model's supported maximum (8192). |
| Meta-Llama-3-8B-Instruct | A10 | 1 | 128 | 8192 | None | 700 | 1 | 70 | Success | |
| mistral-7b | A10 | 1 | 64 | 8192 | None | 700 | 0.5 | 50 | Success | |
| Qwen2.5-7B-Instruct | A10 | 1 | 64 | 8192 | None | 600 | 1 | 30 | Success | |

### Summary: Text Generation Models

* **GPU Impact**: There is a significant performance difference between the GPUs. The **A10** offers more than double the throughput (**~700 tokens/sec**) of the **T4** (**~300-390 tokens/sec**) for similar models.
* **T4 Configuration**: To run these ~8B parameter models, the T4 GPU requires specific settings:
    * The data type must be set to `half` precision, as `bfloat16` is not supported.
    * Pipeline Parallelism of 2 (`PP=2`) was necessary to successfully load and run the models.
* **A10 Performance**: The A10 GPU is a robust choice, achieving up to **700 tokens/sec** for both `Meta-Llama-3-8B-Instruct` and `mistral-7b` on a single GPU (`PP=1`). It handles larger batches and an 8192 context length with high efficiency.
* **Top Performers**: `Meta-Llama-3-8B` and `mistral-7b` were the most performant models in this test set, reaching the 700 tokens/sec mark on the A10 GPU.

***

## OCR Model (`olmOCR-7B-0225-preview`)

This section covers benchmarks for the specialized `olmOCR` model designed for Optical Character Recognition tasks.
> These tests were simply using 400 page PDF book utilizing olmOCR toolkit. 

### Benchmark Table: OCR Model

| Model Name | GPU | Pipeline Parallel | No. of seq | Max Model Len | dtype | Token Throughput (tokens/sec) | TTFT (sec) | Cache Util. % | Result | Remark |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| olmOCR-7B-0225-preview | A10 | 1 | None | None | None | | | | Failed | Not enough cache. Model requires a large context length (>=32K). |
| olmOCR-7B-0225-preview | A10 | 2 | None | None | None | 376 | 10 | 50 | Success | 25 dense pages finished in 2m 20s. |
| olmOCR-7B-0225-preview | A100 | 1 | 64 | None | None | 1000 | 3 | | Success | |
| olmOCR-7B-0225-preview | A100 | 1 | 128 | None | None | 950 | 3 | 2 | Success | |
| olmOCR-7B-0225-preview | H100 | 1 | 2048 | None | None | 4000 | 4 | 80 | Success | Tested with a 400-page PDF. |

### Summary: OCR Model

* **Exceptional Hardware Scaling**: The `olmOCR` model's performance scales dramatically with more powerful GPUs, making it ideal for high-throughput environments.
    * **A10**: Requires 2 GPUs (`PP=2`) to run, achieving **376 tokens/sec**.
    * **A100**: Provides a ~2.7x performance boost over the A10, reaching **~1000 tokens/sec** on a single card.
    * **H100**: Delivers an outstanding **4000 tokens/sec**, a 4x increase over the A100, and is capable of handling extremely large documents and batch sizes.
* **High Memory Requirements**: This model is memory-intensive, failing to run on a single A10 due to insufficient cache and requiring a large context window (at least 32K).
* **Built for Heavy Workloads**: The tests confirm the model's suitability for demanding, real-world OCR tasks, as demonstrated by its ability to process a 400-page PDF on the H100.

---

## 📊 Benchmark Cost Comparison

### Text Inference (50 QnA requests/sec)

* Workload = 50 requests/sec × 512 tokens ≈ **25,600 tokens/sec**.

| GPU / VM Type              | Tokens/sec per GPU | GPUs Required | Spot \$/hr | Regular \$/hr |
| -------------------------- | ------------------ | ------------- | ---------- | ------------- |
| **T4 (NC4as\_T4\_v3)**     | 320                | 80            | \$17.07    | \$58.88       |
| **A10 (NV18ads\_A10\_v5)** | 700                | 37            | \$13.04    | \$76.96       |

**Summary:** A10 spot instances are more cost-efficient than T4 for text workloads, requiring fewer GPUs to hit 50 QPS.

---

### OCR Inference (1,000,000 pages)

* Assumption = 1 page = 1000 tokens → **1 billion tokens total**.

| GPU / VM Type                | Tokens/sec per GPU | Total Time (hrs) | Spot Cost | Regular Cost |
| ---------------------------- | ------------------ | ---------------- | --------- | ------------ |
| **A10 (NV18ads\_A10\_v5)**   | 350                | \~793 hrs        | \$279     | \$1,650      |
| **A100 (NC24ads\_A100\_v4)** | 1000               | \~278 hrs        | \$245     | \$1,325      |
| **H100 (NC40ads\_H100\_v5)** | 4000               | \~69 hrs         | \$499     | \$626        |

**Summary:** For OCR, **A100 spot instances give the best price-performance balance**. A10 is cheaper but very slow, while H100 is fastest and also cost-efficient compared to its runtime.

---
