variable "cluster_name" {
  description = "Name of the AKS cluster."
  type        = string
}

variable "dns_prefix" {
  description = "DNS prefix for AKS cluster."
  type        = string
  default = "myekscluster"
}

variable "automatic_upgrade_channel" {
  description = "Automatic Upgrade Channel: one of -- none,patch,stable,rapid."
  type        = string
  default = "stable"
}

variable "kubernetes_version" {
  description = "AKS Kubernetes version."
  type        = string
  default     = "1.33.0"
}

variable "sku_tier" {
  description = "AKS SKU Tier (Free or Paid)."
  type        = string
  default     = "Standard"
}

variable "private_cluster_enabled" {
  description = "Enable private cluster."
  type        = bool
  default     = false
}

variable "rbac_enabled" {
  description = "Enable RBAC."
  type        = bool
  default     = true
}

variable "azure_policy_enabled" {
  description = "Enable Azure Policy for AKS."
  type        = bool
  default     = true    
}

variable "cost_analysis_enabled" {
  description = "Enable cost analysis for AKS."
  type        = bool
  default     = true
} 

variable http_application_routing_enabled {
  description = "Enable HTTP application routing."
  type        = bool
  default     = false
}

variable "oidc_issuer_enabled" {
  description = "Enable OIDC issuer for workload identity."
  type        = bool
  default     = true
}

variable "workload_identity_enabled" {
  description = "Enable workload identity for AKS."
  type        = bool
  default     = true  
}

variable "identity_type" {
  description = "Identity type for AKS cluster."
  type        = string
  default     = "SystemAssigned"
}

variable "default_node_pool" {
  description = "Default node pool configuration."
  type = object({
    name                = string
    vm_size             = string
    node_count          = optional(number, 3)
    vnet_subnet_id      = string
  })
}

variable "autoscaler_profile" {
  description = "Cluster autoscaler profile settings."
  type = object({ 
    expander                       = optional(string, "least-waste")
  })
  default = {}
}

variable "azure_active_directory_role_based_access_control" {
  description = "Azure Active Directory RBAC settings."
  type = object({
    azure_rbac_enabled        = optional(bool, true)
    admin_group_object_ids    = optional(list(string), [])
  })
  default = {}
} 

variable "network_profile" {
  description = "Cluster network profile settings."
  type = object({
    network_plugin     = optional(string, "azure")
    network_mode     = optional(string, "transparent")
    network_plugin_mode     = optional(string, "overlay")
    pod_cidr       = string
    load_balancer_sku  = optional(string, "standard")
    network_policy     = optional(string, "azure")
    service_cidr       = string
  })
}

variable "resource_group" {
  description = "Object with resource group name and location"
  type = object({
    name     = string
    location = string
  })
}

variable "tags" {
  description = "Tags to apply to the AKS cluster."
  type        = map(string)
  default     = {}
}

variable "enable_diagnostics" {
  description = "Enable or disable AKS diagnostic settings"
  type        = bool
  default     = false
}

variable "enable_monitor_metrics" {
  type    = bool
  default = false
  description = "Set to true to enable Azure Managed Prometheus monitoring (installs CRDs)"
}
