# RayAKS Test Playbooks

This folder hosts runnable notebooks that exercise the Ray/vLLM deployment defined under `stacks/rayaks`. They serve as living playbooks for validating the serving stack before and after you roll manifests such as `vllm-ray-service/ray-service.yaml` or the FastAPI OCR microservice in `DeepSeek-OCR`.

## Notebooks

- **test-serve.ipynb**  
  End-to-end smoke and stress tests for the OpenAI-compatible chat endpoints exposed by the Ray service. Use it after tweaking `ray-service.yaml` or custom model configs to confirm single-turn chats, ShareGPT prompt batches, and JSON-parsing utilities still behave. Optional cells are commented wherever they duplicate functionality or require manual setup.

- **test-pdf.ipynb**  
  Vision/OCR workflows that complement the FastAPI deployment in `DeepSeek-OCR`. The notebook contrasts synchronous and async PDF pipelines using the same models referenced in the manifests, and highlights optional MinerU tooling plus the HTTP wrapper. Commented sections mark historical or environment-specific steps you can enable on demand.

## How To Use

1. Apply the Ray/vLLM resources (e.g., `kubectl apply -f stacks/rayaks/vllm-ray-service/ray-service.yaml`) and FastAPI OCR deployment if relevant.
2. Mount or sync sample PDFs to the notebook environment.
3. Run the notebooks top-to-bottom, skipping or re-enabling the commented cells based on the features you want to verify.
4. Feed the generated outputs back into monitoring or regression suites (for example, the Prometheus rules under `monitoring/` expect predictable JSON payloads).

These notebooks intentionally mirror the production manifests so you can iterate quickly, capture evidence for changes, and hand off reproducible repro steps to teammates.
