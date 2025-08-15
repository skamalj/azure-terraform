# vLLM Helm Chart

This Helm chart deploys a distributed vLLM inference setup on Kubernetes, including:

* `head` node (Ray cluster head)
* `worker` nodes (Ray workers running vLLM workers)
* `vllm-api` (vLLM HTTP API server)
* Persistent Volume Claims and StorageClass for model storage

## Prerequisites

* Kubernetes cluster (with GPU nodes if using GPU scheduling)
* NVIDIA Device Plugin installed and running (installed manually)
* Helm v3.0+

## Installation

```bash
# Clone the chart repo or copy the files
helm install vllm ./vllm-helm \
  --set head.numCpus=4 \
  --set head.image.repository="myregistry/vllm-head" \
  --set worker.numReplicas=2 \
  --set worker.vllmArgs="['--model=/models/llms/mistral-7b']" \
  --set api.modelName="mistral-7b"
```

## Values

Here are the configurable parameters:

### `head` values

| Parameter               | Description         | Default     |
| ----------------------- | ------------------- | ----------- |
| `head.image.repository` | Head pod image repo | `vllm-head` |
| `head.image.tag`        | Image tag           | `latest`    |
| `head.numCpus`          | CPUs to allocate    | `4`         |

### `worker` values

| Parameter                 | Description                  | Default       |
| ------------------------- | ---------------------------- | ------------- |
| `worker.image.repository` | Worker image repo            | `vllm-worker` |
| `worker.numReplicas`      | Number of worker pods        | `1`           |
| `worker.numCpus`          | CPUs to allocate per worker  | `4`           |
| `worker.vllmArgs`         | Array of CLI args for `vllm` | `[]`          |

### `api` values

| Parameter              | Description              | Default      |
| ---------------------- | ------------------------ | ------------ |
| `api.image.repository` | API server image repo    | `vllm-api`   |
| `api.modelName`        | Model name passed to API | `mistral-7b` |
| `api.numCpus`          | CPUs for API container   | `2`          |

### Storage

| Parameter           | Description                   | Default      |
| ------------------- | ----------------------------- | ------------ |
| `storage.className` | StorageClass for model volume | `model-blob` |
| `storage.size`      | Size of the PVC               | `100Gi`      |

## Notes

* The NVIDIA device plugin must be applied manually before deploying the chart.
* `head` must be running before `worker` or `api` connect.
* `worker` pods have liveness probes checking Ray connectivity.

## License

MIT or Apache 2.0 (your choice)

---

If you'd like to generate this chart in a private registry or extend it with other models, open a PR or customize as needed.

DeepSeek-R1-Distill-Qwen-1.5B/snapshots/ad9f0ae0864d7fbcd1cd905e3c6c5b069cc8b562
mistral-7b/e0bc86c23ce5aae1db576c8cca6f06f1f73af2db
Qwen2.5-Omni-7B/snapshots/ae9e1690543ffd5c0221dc27f79834d0294cba00 <<  Not Supported by VLLM >>
Qwen2.5VL3B/snapshots/66285546d2b821cf421d4f5eb2576359d3770cd3