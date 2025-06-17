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
    node_count = 4
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

