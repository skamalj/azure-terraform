
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=4.33.0"
    }
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

// @! add code to add nsg rules for public and private subnets. Accept rules as list of objects in the variable


resource "azurerm_network_security_rule" "private_nsg_rules" {
  for_each = { for rule in var.private_nsg_rules : rule.name => rule }

  name                        = each.value.name
  priority                    = each.value.priority
  direction                   = each.value.direction
  access                      = each.value.access
  protocol                    = each.value.protocol
  source_port_range           = each.value.source_port_range
  destination_port_range      = each.value.destination_port_range
  source_address_prefix      = each.value.source_address_prefix
  destination_address_prefix = each.value.destination_address_prefix

  network_security_group_name = azurerm_network_security_group.private_nsg.name
  resource_group_name        = var.resource_group.name
}

resource "azurerm_network_security_rule" "public_nsg_rules" {
  for_each = { for rule in var.public_nsg_rules : rule.name => rule }

  name                        = each.value.name
  priority                    = each.value.priority
  direction                   = each.value.direction
  access                      = each.value.access
  protocol                    = each.value.protocol
  source_port_range           = each.value.source_port_range
  destination_port_range      = each.value.destination_port_range
  source_address_prefix      = each.value.source_address_prefix
  destination_address_prefix = each.value.destination_address_prefix

  network_security_group_name = azurerm_network_security_group.public_nsg.name
  resource_group_name        = var.resource_group.name
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

