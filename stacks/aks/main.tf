provider "azurerm" {
  features {}
  subscription_id = "3cee1ba8-a6e9-41b5-b6a7-fd6862ae5e92"
}

resource "azurerm_resource_group" "rg" {
  name     = "myaks-rg"
  location = "Central India"
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
    node_count = 1
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


module "nodepool" {
  source = "../../modules/akspool"
  pool_name              = "systempool01"
  kubernetes_cluster_id  = module.aks.aks_cluster.id
  mode                   = "User"
  node_labels            = {
    workload = "LLM"
  }
  vnet_subnet_id         = module.vnet.subnets["private-subnet"].id
  priority = "Spot"
}
