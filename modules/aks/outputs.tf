output "aks_cluster" {
  value = {
    id       = azurerm_kubernetes_cluster.aks.id
    name     = azurerm_kubernetes_cluster.aks.name
    location = azurerm_kubernetes_cluster.aks.location
    fqdn     = azurerm_kubernetes_cluster.aks.fqdn
    identity = azurerm_kubernetes_cluster.aks.identity
    kube_config = {
      raw_config = azurerm_kubernetes_cluster.aks.kube_config_raw
    }
  }
}