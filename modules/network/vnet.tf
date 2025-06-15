provider "azurerm" {
  features {

  }
}

locals {
  subnets_map = { for s in var.subnets : s.name => s }
}

resource "azurerm_virtual_network" "vnet" {
  name                = var.vnet_name
  address_space       = var.vnet_address_space
  location            = var.resource_group.location
  resource_group_name = var.resource_group.name
}

resource "azurerm_subnet" "subnets" {
  for_each = { for s in var.subnets : s.name => s }

  name                          = each.value.name
  resource_group_name           = var.resource_group.name
  virtual_network_name          = azurerm_virtual_network.vnet.name
  address_prefixes              = each.value.address_prefixes
  default_outbound_access_enabled = each.value.type == "public"
}


resource "azurerm_network_security_group" "private_nsg" {
  name                = "${var.vnet_name}-private-nsg"
  location            = var.resource_group.location
  resource_group_name = var.resource_group.name
}

resource "azurerm_network_security_group" "public_nsg" {
  name                = "${var.vnet_name}-public-nsg"
  location            = var.resource_group.location
  resource_group_name = var.resource_group.name
}

resource "azurerm_subnet_network_security_group_association" "private_assoc" {
  for_each = {
    for s in var.subnets : s.name => s if s.type == "private"
  }

  subnet_id                 = azurerm_subnet.subnets[each.key].id
  network_security_group_id = azurerm_network_security_group.private_nsg.id
}

resource "azurerm_subnet_network_security_group_association" "public_assoc" {
  for_each = {
    for s in var.subnets : s.name => s if s.type == "public"
  }

  subnet_id                 = azurerm_subnet.subnets[each.key].id
  network_security_group_id = azurerm_network_security_group.public_nsg.id
}

resource "azurerm_route_table" "public_route_table" {
  name                = "${var.vnet_name}-public-rt"
  location            = var.resource_group.location
  resource_group_name = var.resource_group.name
}

resource "azurerm_route_table" "private_route_table" {
  name                = "${var.vnet_name}-private-rt"
  location            = var.resource_group.location
  resource_group_name = var.resource_group.name
}

resource "azurerm_subnet_route_table_association" "public_assoc" {
  for_each = {
    for s in var.subnets : s.name => s if s.type == "public"
  }

  subnet_id      = azurerm_subnet.subnets[each.key].id
  route_table_id = azurerm_route_table.public_route_table.id
}

resource "azurerm_subnet_route_table_association" "private_assoc" {
  for_each = {
    for s in var.subnets : s.name => s if s.type == "private"
  }

  subnet_id      = azurerm_subnet.subnets[each.key].id
  route_table_id = azurerm_route_table.private_route_table.id
}

