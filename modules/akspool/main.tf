resource "azurerm_kubernetes_cluster_node_pool" "akspool" {
    name                = var.pool_name
    kubernetes_cluster_id = var.kubernetes_cluster_id
    vm_size             = var.vm_size
    auto_scaling_enabled = var.auto_scaling_enabled
    node_public_ip_enabled = var.node_public_ip_enabled
    mode = var.mode
    node_labels = var.node_labels
    node_taints = var.node_taints
    pod_subnet_id = var.pod_subnet_id
    priority = var.priority
    vnet_subnet_id = var.vnet_subnet_id
    max_count = var.max_count
    min_count = var.min_count
    node_count = var.node_count
    lifecycle {
    ignore_changes = [
      eviction_policy
    ]
  }
}