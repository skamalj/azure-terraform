# vLLM Bare-Metal Playbook

This folder contains a “manual gearbox” deployment of vLLM for teams that want full control over every pod. Instead of relying on the managed `RayService` pattern packaged under `stacks/rayaks`, you stand up the head, worker, and API interface yourself. It’s more hands-on, but the payoff is predictable rollouts, explicit resource pinning, and easier debugging when you need to inspect each component in isolation.

## When to Choose This Layout

- **Tight Operational Control:** You decide when to restart the head, how many workers run, and which GPU pool the API gateway lives on.
- **Incremental Upgrades:** Roll different container versions for head/worker/API without waiting for RayService reconciler loops.
- **Troubleshooting & Profiling:** Restart a single deployment, attach profiling containers, or override environment variables without touching the bigger Ray autoscaler stack.

If you prefer “click once and go,” the `stacks/rayaks/vllm-ray-service` directory gives you a higher-level RayService with automatic worker management, Prometheus integration, and pod recyclers. This directory is for the long-time operators who want to see—and control—every bolt.

## Components at a Glance

| Manifest | Purpose | Highlights |
|----------|---------|------------|
| `storage-class-model-blob.yaml` | Storage plumbing | Thin storage class to back the shared PVC for model artifacts. |
| `pvc.yaml` | Shared volume | Binds the PVC that both head and worker use to read models (often preloaded by the downloader stack). |
| `nvidia-device-plugin-ds.yaml` | GPU enumeration | Ensures Kubernetes exposes GPU resources before you launch vLLM pods. Deploy once per cluster. |
| `head-deployment.yaml` | Ray head node | Launches the head pod; exposes the dashboard & head service ports you’ll connect workers to. |
| `worker-deployment.yaml` | Ray workers | Horizontal set of workers pointing back to the head; tweak replicas to control capacity. |
| `vllm-api-deployment.yaml` | HTTP/OpenAI shim | Thin FastAPI wrapper that points to the Ray cluster for inference requests. |
| `monitoring/` | Dashboards & rules | Optional extras for Prometheus/Grafana when you want eyes on GPU/latency metrics. |

## Deploying Step by Step

1. **Set up storage and GPUs**
   ```bash
   kubectl apply -f storage-class-model-blob.yaml
   kubectl apply -f pvc.yaml
   kubectl apply -f nvidia-device-plugin-ds.yaml
   ```
   Confirm the PVC binds and the device plugin reports GPUs before moving on.

2. **Bring up the Ray backbone**
   ```bash
   kubectl apply -f head-deployment.yaml
   kubectl apply -f worker-deployment.yaml
   ```
   The worker deployment references the head service by name (`RAY_HEAD_SERVICE_HOST`). Adjust node selectors and resource requests in each manifest to match your cluster topology.

3. **Expose the API facade**
   ```bash
   kubectl apply -f vllm-api-deployment.yaml
   ```
   This pod runs the vLLM HTTP server with the familiar OpenAI-compatible routes. Point clients at the service’s ClusterIP/Ingress once ready.

4. **(Optional) Layer on monitoring**
   The `monitoring/` directory contains Prometheus rules, dashboards, and pod monitors tailored to this manual setup. Apply them after your metrics stack is in place.

## How It Differs from `stacks/rayaks`

| Manual vLLM (this folder) | RayService (`stacks/rayaks`) |
|---------------------------|------------------------------|
| Separate deployments for head, worker, API | Declarative RayService object that manages the trio |
| You scale workers via Kubernetes replicas | Autoscaler handled by the Ray operator |
| Rollouts done pod-by-pod | Operator coordinates restarts and upgrades |
| Great for bespoke debugging and custom GPU scheduling | Ideal for production clusters that want managed lifecycle and self-healing |

In many teams the RayService path becomes the default once everything stabilises. Keep this manual layout handy for day-zero bring-up, controlled benchmarks, or clusters where you are not ready to run the Ray operator.

## Configuration Pointers

- **Model paths:** Each manifest mounts the shared PVC at `/models`. Pair this directory with the downloader workflow under `stacks/download-modells` so models are present before workers start.
- **Environment variables:** The head and worker deployments define `RAY_` flags to tune runtime behaviour. Adjust memory, CPUs, and GPU counts based on your hardware.
- **Networking:** The API deployment exposes port 8000 (OpenAI REST) and optionally gRPC. Wire it to an Ingress or LoadBalancer as needed.

## Operational Checklist

- Use `kubectl logs` on the head to watch worker registration.
- Scale the worker deployment up/down to match demand.
- Restart only the API pod if you change model serving parameters or need a quick config reload.
- Once comfortable, compare behaviour against the RayService setup to decide which path best fits your production environment.

Manual does not mean messy—it simply gives you the knobs. This folder documents every piece so you can spin up vLLM with confidence and graduate to the managed RayService when you’re ready.

Results and Key takeaways:
- **T4 GPUs** have limited support (no bfloat16, frequent load failures, lower throughput).  
- **A10 GPUs** achieve much higher throughput and cache utilization, with stable performance across larger sequence lengths.  
- Misconfigured parameters (like `dtype` or `max_model_len`) often cause failures.  


| Model name                | GPU | Pipeline Parallel | No. of seq | Max model Len | dtype   | Token Throughput (per sec) | TTFT (sec) | Cache Utilization % | Result  | Remark                                                                                                                                                  |
|----------------------------|-----|------------------|------------|---------------|---------|----------------------------|------------|----------------------|---------|---------------------------------------------------------------------------------------------------------------------------------------------------------|
| mistral-7b                 | T4  | 1                |            | 4096          | Not Set |                            |            |                      | Fail    | Bfloat16 is only supported on GPUs with compute capability of at least 8.0. Your Tesla T4 GPU has compute capability 7.5. Use `--dtype=half` instead.    |
| mistral-7b                 | T4  | 1                |            | 4096          | half    |                            |            |                      | Fail    | Model Load failure                                                                                                                                      |
| mistral-7b                 | T4  | 2                | 32         | 4096          | half    | 390                        | 2          |                      | Success |                                                                                                                                                         |
| Qwen2.5-7B-Instruct        | T4  | 2                |            | 4096          | Not set |                            |            |                      | Fail    |                                                                                                                                                         |
| Qwen2.5-7B-Instruct        | T4  | 2                | 32         | 4096          | half    | 325                        | 2          | 12                   | Success |                                                                                                                                                         |
| Qwen2.5-7B-Instruct        | T4  | 2                | 128        | 4096          | half    | 320                        | 2          | 12                   | Success |                                                                                                                                                         |
| Meta-Llama-3-8B-Instruct   | T4  | 2                | 32         | 8192          | half    | 320                        | 2          | 25                   | Success |                                                                                                                                                         |
| Meta-Llama-3-8B-Instruct   | T4  | 2                | 32         | 4096          | half    | 300                        | 3          | 15                   | Success |                                                                                                                                                         |
| Meta-Llama-3-8B-Instruct   | A10 | 1                | 64         | 8192          | None    | 700                        | 1          | 60                   | Success |                                                                                                                                                         |
| Meta-Llama-3-8B-Instruct   | A10 | 1                | 128        | 16384         | None    |                            |            |                      | Failed  | ValueError: User-specified max_model_len (16384) is greater than derived max_model_len (max_position_embeddings=8192 or model_max_length=None).          |
| Meta-Llama-3-8B-Instruct   | A10 | 1                | 128        | 8192          | None    | 700                        | 1          | 70                   | Success |                                                                                                                                                         |
| mistral-7b                 | A10 | 1                | 64         | 8192          | None    | 700                        | 0.5        | 50                   | Success |                                                                                                                                                         |
| Qwen2.5-7B-Instruct        | A10 | 1                | 64         | 8192          | None    | 600                        | 1          | 30                   | Success |                                                                                                                                                         |
