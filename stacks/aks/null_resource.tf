resource "null_resource" "post_aks_setup" {
  triggers = {
    always_run = timestamp()
  }  
  provisioner "local-exec" {
    command = <<EOT
      az aks get-credentials -g ${azurerm_resource_group.rg.name} --name ${module.aks.aks_cluster.name} --overwrite-existing
      az aks update  -g ${azurerm_resource_group.rg.name} --name ${module.aks.aks_cluster.name} --node-provisioning-mode Auto
      kubectl apply -f ${path.module}/provisioner.yaml
      kubectl apply -f ${path.module}/storage-class-model-blob.yaml
      kubectl apply -f ${path.module}/pvc.yaml
      kubectl apply -f ${path.module}/nvidia-device-plugin-ds.yaml
    EOT
  }
  depends_on = [module.aks]
}