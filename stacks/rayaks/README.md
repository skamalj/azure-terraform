# RayAKS Deployment Suite

RayAKS is an end-to-end toolkit for launching a production-ready Ray + vLLM stack on Azure Kubernetes Service (AKS). The Terraform code spins up the Azure resources, and the Kubernetes manifests layer on RayService, GPU-aware autoscaling, monitoring, and validation notebooks. Use this folder when you want a repeatable path from empty subscription to a fully managed, autoscaled LLM serving cluster.

---

## What This Stack Builds

- **Azure Resource Group + Virtual Network** – `main.tf` provisions a VNet with public/private subnets, security rules, and role assignments so AKS can reach storage and scale nodes.
- **AKS Cluster with Managed AAD Integration** – The `modules/aks` module configures the cluster, default node pool, network ranges, and Azure AD RBAC bindings.
- **Role Assignments** – Terraform grants the cluster identity Contributor access to your Hugging Face storage account and Network Contributor rights on the VNet.
- **Karpenter NodePools** – `provisioner.yaml` defines CPU and multiple GPU pools (T4, A10, A100, H100) so Ray workers can land on the appropriate hardware with spot / on-demand mix.
- **RayService-based vLLM Deployment** – Under `vllm-ray-service/` you’ll find the RayService manifest, associated PVC and storage class, the NVIDIA device plugin, and a pod cleaner job.
- **Monitoring Hooks** – `monitoring/` ships Prometheus alert rules. Combine with your Prometheus stack to track GPU utilisation, request latency, etc.
- **Operator Playbooks** – `test/` (read the README there) contains notebooks that smoke-test the chat endpoints and OCR flows built on top of this deployment.

---

## Terraform Workflow

1. **Authenticate**
   ```bash
   az login
   az account set --subscription "<your-subscription-id>"
   ```

2. **Bootstrap Terraform backend** (optional if already configured):
   ```bash
   terraform init
   ```

3. **Review & apply**
   ```bash
   terraform plan -out=tfplan
   terraform apply tfplan
   ```
   This provisions the resource group, VNet, AKS, and role assignments defined in `main.tf`.

4. **Fetch cluster credentials**
   ```bash
   az aks get-credentials --resource-group myaks-rg --name myakscluster --overwrite-existing
   kubelogin convert-kubeconfig -l azurecli
   ```

5. **Verify access**
   ```bash
   kubectl get nodes
   ```

---

## Kubernetes Layer

Once AKS is ready, deploy the add-ons in this order:

1. **GPU device plugin** (once per cluster)
   ```bash
   kubectl apply -f vllm-ray-service/nvidia-device-plugin-ds.yaml
   ```

2. **Storage plumbing**
   ```bash
   kubectl apply -f vllm-ray-service/storage-class-model-blob.yaml
   kubectl apply -f vllm-ray-service/pvc.yaml
   ```
   Pair this PVC with your model downloader workflow so weights are cached under `/models`.

3. **Karpenter node pools & classes**
   ```bash
   kubectl apply -f provisioner.yaml
   ```
   The CPU pool handles Ray head + utility pods; GPU pools (T4/A10/A100/H100) back the worker autoscaling groups defined in the RayService manifest.

4. **RayService deployment**
   ```bash
   kubectl apply -f vllm-ray-service/ray-service.yaml
   ```
   This single resource spins up the Ray head, manages worker groups, and publishes the OpenAI-compatible endpoint. Customize model IDs, autoscaling policies, and GPU requirements directly in the manifest.

5. **(Optional) Pod cleaner** – Keeps idle worker pods tidy when experimenting.
   ```bash
   kubectl apply -f vllm-ray-service/pod-cleaner.yaml
   ```

6. **(Optional) Monitoring**
   Hook Prometheus/Grafana into the cluster, then apply `monitoring/prom_vllm_rules.yaml` (and other resources you maintain) to track utilisation and alert on anomalies.

---

## How it Compares to the Manual vLLM Setup

| RayAKS (this folder) | Manual vLLM (`stacks/vLLM`) |
|----------------------|-----------------------------|
| Terraform-managed AKS cluster, networking, RBAC | Assumes cluster already exists |
| RayService controls head, workers, autoscaling | Separate deployments per component |
| Karpenter NodePools for multi-tier GPU scheduling | Static worker replica counts |
| Built-in monitoring hooks & pod cleaner | Bring your own observability |
| Best when you want managed orchestration | Best for hands-on debugging or bespoke setups |

Use RayAKS when you prefer a managed experience with autoscaling, spot/on-demand blending, and minimal manual patching. Drop to the manual folder when you need step-by-step control or a lightweight lab environment.

---

## Why This Architecture Works

- **Scale-to-zero economics:** RayService can hold an application at zero replicas until traffic arrives. Combined with Karpenter, the cluster spins up GPU nodes only when needed, then evicts them once requests drain. You stop paying the moment demand disappears.
- **Warm-up protection via proxy:** The Serve proxy buffers inbound requests while the head and workers initialise. Users see a pending response rather than a timeout, which matters for heavy checkpoints that take minutes to load.
- **Autoscaling knobs you actually control:** `max_replicas`, `target_ongoing_requests`, and `downscale_to_zero_delay_s` let you choreograph how fast the system reacts to spikes versus how aggressively it shrinks. Tune them per model to balance GPU cost against tail latency.
- **Karpenter placement logic:** NodePools split CPU utility nodes from multiple GPU SKUs (T4, A10, A100, H100). You choose which group each Ray worker maps to, mixing spot and on-demand capacity without touching Ray code.
- **Storage locality:** A shared PVC ties into the downloader workflow, so Ray workers mount pre-fetched models. No request wastes GPU time downloading weights.
- **Observability baked in:** Workers export Prometheus metrics and the head exposes Ray dashboards. You can watch autoscaler decisions, GPU utilisation, and request latencies in real time.
- **Security & RBAC alignment:** Terraform wires Azure AD groups into cluster admin roles and limits network access via NSG rules. Operators stay within enterprise guardrails even while running cutting-edge LLM infrastructure.

In short, this architecture gives you the cloud elasticity of a serverless platform with the transparency of managing every component yourself.

---

## Configurable Touchpoints

- **Model & autoscaling config** – Edit `vllm-ray-service/ray-service.yaml` to change the model path (`/models/...`), adjust `max_num_seqs`, or tweak autoscaler bounds.
- **Node pool SKUs** – Update `provisioner.yaml` if you need different GPU SKUs or capacity limits.
- **Networking / RBAC** – Modify `main.tf` to match your subscription, subnet ranges, or Azure AD group IDs.
- **Storage account** – The Terraform role assignment expects the Hugging Face models to live in `skamaljhuggingfacesea`. Point it to your account instead.

---

## Validation & Operations

- Run the notebooks in `test/` to confirm chat completion endpoints and OCR flows work end-to-end.
- `kubectl get rayservices` to watch RayService state transitions.
- `kubectl logs -l ray.io/node-type=head` to inspect Ray head activity.
- Scale GPU groups by editing autoscaling config or Karpenter limits.
- Use the Prometheus rules to trigger alerts on GPU saturation or high latency.

With RayAKS you get a turnkey Azure landing zone plus a managed Ray/vLLM control plane. Follow the Terraform + Kubernetes steps above and you’ll have a scalable LLM serving cluster ready for traffic.
