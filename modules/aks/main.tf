resource "azurerm_kubernetes_cluster" "aks" {
  name                = var.cluster_name
  location            = var.resource_group.location
  resource_group_name = var.resource_group.name
  dns_prefix          = var.dns_prefix

  kubernetes_version  = var.kubernetes_version
  sku_tier            = var.sku_tier
  private_cluster_enabled = var.private_cluster_enabled
  oidc_issuer_enabled = var.oidc_issuer_enabled
  automatic_upgrade_channel = var.automatic_upgrade_channel

  default_node_pool {
    name                = var.default_node_pool.name
    vm_size             = var.default_node_pool.vm_size
    node_count          = var.default_node_pool.node_count
    vnet_subnet_id      = var.default_node_pool.vnet_subnet_id
  }

  auto_scaler_profile {
    expander                         = var.autoscaler_profile.expander
  }

  role_based_access_control_enabled = var.rbac_enabled
  azure_active_directory_role_based_access_control {
    azure_rbac_enabled = var.azure_active_directory_role_based_access_control.azure_rbac_enabled
    admin_group_object_ids = var.azure_active_directory_role_based_access_control.admin_group_object_ids
  }


  azure_policy_enabled = var.azure_policy_enabled
  cost_analysis_enabled = var.cost_analysis_enabled
  http_application_routing_enabled = var.http_application_routing_enabled

  monitor_metrics {
    
  }

  network_profile {
    network_plugin    = var.network_profile.network_plugin
    network_mode    = var.network_profile.network_mode
    load_balancer_sku = var.network_profile.load_balancer_sku
    network_policy    = var.network_profile.network_policy
    dns_service_ip    = var.network_profile.dns_service_ip
    service_cidr      = var.network_profile.service_cidr
    pod_cidr = var.network_profile.pod_cidr
  }

  workload_identity_enabled = var.workload_identity_enabled

  identity {
    type = var.identity_type
  }

  tags = var.tags
}