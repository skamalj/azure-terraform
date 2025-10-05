resource "null_resource" "post_aks_setup" {
  triggers = {
    always_run = timestamp()
  }  
  provisioner "local-exec" {
    command = <<EOT
      az aks get-credentials -g ${azurerm_resource_group.rg.name} --name ${module.aks.aks_cluster.name} --overwrite-existing
      az aks update  -g ${azurerm_resource_group.rg.name} --name ${module.aks.aks_cluster.name} --node-provisioning-mode Auto
      kubectl apply -f ${path.module}/provisioner.yaml
      kubectl apply -f ${path.module}/vllm-ray-service/storage-class-model-blob.yaml
      kubectl apply -f ${path.module}/vllm-ray-service/pvc.yaml
      kubectl apply -f ${path.module}/vllm-ray-service/nvidia-device-plugin-ds.yaml
      ~/dev/kuberay/install/prometheus/install.sh --auto-load-dashboard true
      helm upgrade --install kuberay-operator kuberay/kuberay-operator --version 1.4.2  --set image.tag=v1.4.2 \
      --set metrics.serviceMonitor.enabled=true --set metrics.serviceMonitor.selector.release=prometheus
    EOT
  }

  depends_on = [module.aks]
}