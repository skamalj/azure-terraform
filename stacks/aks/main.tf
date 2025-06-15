provider "azurerm" {
  features {}
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
