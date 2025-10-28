locals {
  dns_service_ip = cidrhost(var.network_profile.service_cidr, 10)
}

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

  storage_profile {
    blob_driver_enabled = true
  }

  role_based_access_control_enabled = var.rbac_enabled
  azure_active_directory_role_based_access_control {
    azure_rbac_enabled = var.azure_active_directory_role_based_access_control.azure_rbac_enabled
    admin_group_object_ids = var.azure_active_directory_role_based_access_control.admin_group_object_ids
  }


  azure_policy_enabled = var.azure_policy_enabled
  cost_analysis_enabled = var.cost_analysis_enabled
  http_application_routing_enabled = var.http_application_routing_enabled
  web_app_routing {
    dns_zone_ids = []
  }

  #  dynamic block — only included if enable_monitor_metrics is true
  dynamic "monitor_metrics" {
    for_each = var.enable_monitor_metrics ? [1] : []
    content {}
  }

  network_profile {
    network_plugin    = var.network_profile.network_plugin
    network_mode    = var.network_profile.network_mode
    network_plugin_mode    = var.network_profile.network_plugin_mode
    load_balancer_sku = var.network_profile.load_balancer_sku
    network_policy    = var.network_profile.network_policy
    service_cidr      = var.network_profile.service_cidr
    pod_cidr = var.network_profile.pod_cidr
    dns_service_ip = local.dns_service_ip
  }

  workload_identity_enabled = var.workload_identity_enabled

  identity {
    type = var.identity_type
  }
  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.aks.id
  }
  tags = var.tags
}

resource "azurerm_log_analytics_workspace" "aks" {
  name                = "${var.cluster_name}-logs"
  location            = var.resource_group.location
  resource_group_name = var.resource_group.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags
}

resource "azurerm_monitor_diagnostic_setting" "aks" {
  count = var.enable_diagnostics ? 1 : 0

  name                       = "${var.cluster_name}-diagnostics"
  target_resource_id         = azurerm_kubernetes_cluster.aks.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.aks.id

  dynamic "enabled_log" {
    for_each = [
      "kube-apiserver",
      "kube-audit",
      "kube-controller-manager",
      "kube-scheduler",
      "cluster-autoscaler"
    ]
    content {
      category = enabled_log.value
    }
  }

  enabled_metric {
    category = "AllMetrics"
  }
}
