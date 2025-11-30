# Azure Terraform LLM Platform

This repository is the top-level hub for provisioning Azure infrastructure and running large language models with Ray + vLLM on AKS. Everything is curated so you can go from zero to a managed, autoscaled inference platform with a set of reproducible Terraform modules and Kubernetes manifests.

## Project Layout

- `modules/` – Reusable Terraform modules (AKS, networking, etc.) pulled into the stack definitions.
- `stacks/rayaks/` – Full end-to-end RayService deployment on AKS. Terraform builds the Azure landing zone, while Kubernetes manifests and notebooks wire up Ray, Karpenter, monitoring, and validation playbooks. See the dedicated README for step-by-step guidance.
- `stacks/vLLM/` – Manual “bare-metal” deployment of vLLM with standalone head, worker, and API deployments. Ideal when you want to experiment outside of the Ray operator or need fine-grained control.
- `stacks/download-modells/` – Kubernetes job/deployment for preloading Hugging Face models onto shared storage so GPU pods start instantly.
- `stacks/DeepSeek-OCR/` – Ancillary OCR services that integrate with the same infrastructure backbone.

## Getting Started

1. Install Terraform, Azure CLI, and `kubelogin`.
2. Choose your stack:
   - **Managed path:** Follow `stacks/rayaks/README.md` to provision AKS and deploy the RayService-based LLM cluster with autoscaling out of the box.
   - **Manual path:** Use `stacks/vLLM/Readme.md` if you prefer to manage head/worker/API pods yourself.
3. Preload models using the downloader deployment (`stacks/download-modells/readme.md`) so inference services don’t waste GPU cycles fetching weights.
4. Optional: deploy the OCR or monitoring components to round out the platform.
5. Use the notebooks under `stacks/rayaks/test/` to validate chat endpoints, latency behaviour, and OCR pipelines.

## Highlights

- Terraform-driven Azure resource creation with sensible defaults and guardrails.
- RayService architecture that scales workers to zero, buffers requests during warm-up, and exposes tuning knobs for response time and cost control.
- Karpenter NodePools preconfigured for CPU and multiple GPU SKUs, mixing spot and on-demand capacity.
- Model downloader workflow to keep checkpoints off the critical path.
- Prometheus alert rules and Grafana-friendly metrics endpoints for observability.

## Recommended Workflow

1. **Provision** infrastructure with Terraform.
2. **Connect** to the cluster (`az aks get-credentials` + `kubelogin convert-kubeconfig -l azurecli`).
3. **Deploy** the downloader, storage classes, RayService manifests, and optional monitoring.
4. **Validate** with the provided notebooks and adjust autoscaling knobs or model configs as needed.
5. **Iterate** by tweaking Terraform variables, RayService parameters, or Karpenter limits to match your production requirements.

Whether you want an opinionated, autoscaling LLM serving stack or a manual environment for fine-grained experiments, this repo provides both paths with shared infrastructure primitives.
