# vLLM Ray Helm Chart

This chart packages the manifests in `stacks/vLLM` so you can deploy the Ray-based vLLM stack with a single `helm install`.

## Components
- Ray head, worker, and vLLM API Deployments plus their Services.
- Optional Azure Blob backed StorageClass and PVCs for model storage and HF cache.
- Prometheus scraper targeting the API pod.
- NVIDIA device plugin DaemonSet (deployed into a dedicated namespace).

## Usage
```bash
# from repo root
helm install vllm ./vllm-helm \
  --namespace default \
  --create-namespace
```

Override values as needed (images, node selectors, tolerations, PVC names, Prometheus targets, etc.). Example:
```bash
helm upgrade --install vllm ./vllm-helm \
  --set global.modelStorage.pvcName=my-models \
  --set api.nodeSelector.gpu=h100 \
  --set api.vllm.pipelineParallelSize=4 \
  --set api.dataParallelSize=2

# Or start from the sample override file and customize:
helm upgrade --install vllm ./vllm-helm \
  -f vllm-helm/values.override.example.yaml
```

Worker pods are only created when `api.vllm.pipelineParallelSize` is greater than `1`; the chart automatically sets the worker replica count to `(pipelineParallelSize - 1) * api.dataParallelSize` so tensor/pipeline parallelism stays in sync across data-parallel replicas.

Key knobs:
- `api.model.*` and `api.vllm.*` feed directly into the generated `vllm serve` command (model path/name, host/ports, dtype, swap space, tensor/pipeline parallel sizes, etc.).
- Any additional key you place under `api.vllm` is rendered automatically into a `--<key>` flag (bools become single switches, scalars get values, slices repeat), so you can pass new vLLM CLI options without modifying the chart.
- `worker.extraPipPackages` / `api.extraPipPackages` let you append additional `pip install ...` commands (for things like `deepgemm` or flash-attn) without editing the templates.
- `worker.extraShellCommands` / `api.extraShellCommands` run arbitrary shell snippets right after the pip installs (perfect for installing `uv`, cloning repos, `apt-get install git`, etc.); because the containers run as root by default, remember to pass `--system` (or create a venv) when using tools like `uv pip`.
- `nodePools.*` defines reusable node selectors (CPU/GPU pools, etc.) that components can reference via `head.nodePool`, `worker.nodePool`, and `api.nodePool`; set `*.nodeSelector` directly if you need per-component overrides.
- `api.dataParallelSize` controls how many API replicas are launched; each replica connects to Ray for data-parallel inference.
- `api.vllm.pipelineParallelSize` drives both the worker replica math and the `--pipeline-parallel-size` flag.
- `api.vllm.tensorParallelSize` controls the GPU requests/limits for the API pod and each worker (counts match the tensor-parallel width).
- `versions.*` pins the Ray wheels, `vllm/vllm-openai` image tag, and Transformers release so every pod stays on the same stack; override them once to update the entire chart.
- `api.ray.numCpus`, `worker.ray.*`, and `head.ray.*` feed the bootstrap scripts rendered by the chart (no need to edit inline shell).
- `sharedMemory.worker` / `sharedMemory.api` control the `/dev/shm` `emptyDir` sizes for worker and API pods; adjust once to resize all replicas.

Prometheus targets default to the API service that the chart creates; supply `prometheus.scrapeTargets` to collect from additional endpoints.
