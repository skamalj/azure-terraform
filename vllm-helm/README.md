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
```

Worker pods are only created when `api.vllm.pipelineParallelSize` is greater than `1`; the chart automatically sets the worker replica count to `(pipelineParallelSize - 1) * api.dataParallelSize` so tensor/pipeline parallelism stays in sync across data-parallel replicas.

Key knobs:
- `api.model.*` and `api.vllm.*` feed directly into the generated `vllm serve` command (model path/name, host/ports, dtype, swap space, tensor/pipeline parallel sizes, etc.).
- `api.dataParallelSize` controls how many API replicas are launched; each replica connects to Ray for data-parallel inference.
- `api.vllm.pipelineParallelSize` drives both the worker replica math and the `--pipeline-parallel-size` flag.
- `api.vllm.tensorParallelSize` controls the GPU requests/limits for the API pod and each worker (counts match the tensor-parallel width).
- `api.ray.clientVersion/numCpus`, `worker.ray.*`, and `head.ray.*` feed the bootstrap scripts rendered by the chart (no need to edit inline shell).

Prometheus targets default to the API service that the chart creates; supply `prometheus.scrapeTargets` to collect from additional endpoints.
