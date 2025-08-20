provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
  subscription_id = "3cee1ba8-a6e9-41b5-b6a7-fd6862ae5e92"
}

resource "azurerm_resource_group" "rg" {
  name     = "myaks-rg"
  location = "Southeast Asia"
}

module "vnet" {
  source = "../../modules/network"

  vnet_name          = "mynet-vnet"
  vnet_address_space = ["10.0.0.0/16"]
  subnets = [
    {
      name             = "public-subnet"
      address_prefixes = ["10.0.1.0/24"]
      type             = "public"
    },
    {
      name             = "private-subnet"
      address_prefixes = ["10.0.2.0/24"]
      type             = "private"
    }]
  resource_group = azurerm_resource_group.rg
  private_nsg_rules = [local.network_security_rule]
}

// @! add aks module basis included code with bare minimum parameters, where defaults are not provided, include=modules/aks/variables.tf include=modules/aks/main.tf

module "aks" {
  source = "../../modules/aks"

  cluster_name = "myakscluster"
  dns_prefix = "mydns"
  resource_group = {
    name = azurerm_resource_group.rg.name
    location = azurerm_resource_group.rg.location
  }
  default_node_pool = {
    name = "default"
    vm_size = "Standard_D2s_v3"
    node_count = 2
    vnet_subnet_id = module.vnet.subnets["private-subnet"].id
  }
  network_profile = {
    pod_cidr = "10.244.0.0/16"
    service_cidr = "10.2.0.0/24"
  }

  azure_active_directory_role_based_access_control = {
    admin_group_object_ids    = ["92a6460b-bc90-4519-8fc4-c17429c81cdd"]
  }

   
  tags = {
    environment = "dev"
  }
}

// @! create local variable to add network security rule for accepting http traffic on port 80 

locals {
  network_security_rule = {
    name                        = "HTTP"
    priority                    = 1001
    direction                   = "Inbound"
    access                      = "Allow"
    protocol                    = "Tcp"
    source_port_range           = "*"
    destination_port_range      = "80"
    source_address_prefix       = "*"
    destination_address_prefix  = "*"
  }
}

data "azurerm_client_config" "current" {}

resource "azurerm_role_assignment" "allow_aks_access" {
  scope                = module.aks.aks_cluster.id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"  # Cluster Admin
  principal_id         = data.azurerm_client_config.current.object_id
}


module "nodepool_head" {
  source = "../../modules/akspool"
  pool_name              = "userpool01"
  kubernetes_cluster_id  = module.aks.aks_cluster.id
  #vm_size = "Standard_NC4as_T4_v3"
  vm_size = "standard_d2d_v4"
  node_count = 1
  mode                   = "User"
  node_labels            = {
    workload = "rayHead"
  }
  vnet_subnet_id         = module.vnet.subnets["private-subnet"].id
  priority = "Spot"
}

variable "enable_nodepool_api" {
  type    = bool
  default = true
  description = "Enable or disable the second worker node pool"
}

module "nodepool_worker" {
  source = "../../modules/akspool"
  pool_name              = "userpool02"
  kubernetes_cluster_id  = module.aks.aks_cluster.id
  count  = var.enable_nodepool_api ? 1 : 0
  #vm_size = "Standard_NC40ads_H100_v5"
  vm_size = "Standard_NC24ads_A100_v4"
  #vm_size = "Standard_NV36ads_A10_v5"
  #vm_size = "Standard_NC4as_T4_v3"
  #vm_size = "standard_d2d_v4"
  node_count = 1
  mode                   = "User"
  node_labels            = {
    workload = "rayWorkerAndAPI"
  }
  vnet_subnet_id         = module.vnet.subnets["private-subnet"].id
  priority = "Spot"
}

variable "enable_nodepool_worker2" {
  type    = bool
  default = false
  description = "Enable or disable the second worker node pool"
}

module "nodepool_worker2" {
  source = "../../modules/akspool"
  count  = var.enable_nodepool_worker2 ? 1 : 0
  pool_name              = "userpool03"
  kubernetes_cluster_id  = module.aks.aks_cluster.id
  vm_size = "Standard_NV36ads_A10_v5"
  #vm_size = "Standard_NC4as_T4_v3"
  #vm_size = "Standard_NV18ads_A10_v5"
  #vm_size = "standard_d2d_v4"
  node_count = 0
  mode                   = "User"
  node_labels            = {
    workload = "rayWorker"
  }
  vnet_subnet_id         = module.vnet.subnets["private-subnet"].id
  priority = "Spot"
}

module "nodepool_worker3" {
  source = "../../modules/akspool"
  pool_name              = "userpool04"
  kubernetes_cluster_id  = module.aks.aks_cluster.id
  #vm_size = "Standard_NV36ads_A10_v5"
  vm_size = "Standard_NC4as_T4_v3"
  #vm_size = "Standard_NV18ads_A10_v5"
  #vm_size = "standard_d2d_v4"
  node_count = 1
  mode                   = "User"
  node_labels            = {
    workload = "olmOCRApi"
  }
  vnet_subnet_id         = module.vnet.subnets["private-subnet"].id
  priority = "Spot"
}

data "azurerm_storage_account" "target" {
  name                = "skamaljhuggingfacesea"
  resource_group_name = "azadmin"
}

# Contributor Role Definition ID (built-in)
data "azurerm_role_definition" "contributor" {
  name = "Contributor"
  scope = data.azurerm_storage_account.target.id
}

resource "azurerm_role_assignment" "storage_contributor" {
  scope              = data.azurerm_storage_account.target.id
  role_definition_id = data.azurerm_role_definition.contributor.id
  principal_id       = module.aks.aks_cluster.identity[0].principal_id
}