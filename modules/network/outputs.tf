output "vnet" {
  description = "Virtual Network object"
  value = {
    id                = azurerm_virtual_network.vnet.id
    name              = azurerm_virtual_network.vnet.name
    address_space     = azurerm_virtual_network.vnet.address_space
    location          = azurerm_virtual_network.vnet.location
    resource_group    = var.resource_group.name
  }
}

output "subnets" {
  description = "Map of subnet objects keyed by subnet name"
  value = {
    for subnet_name, subnet in azurerm_subnet.subnets :
    subnet_name => {
      id                   = subnet.id
      name                 = subnet.name
      address_prefixes     = subnet.address_prefixes
      resource_group       = var.resource_group.name
      virtual_network_name = azurerm_virtual_network.vnet.name
      default_outbound_access_enabled = subnet.default_outbound_access_enabled
      type                 = local.subnets_map[subnet_name].type
    }
  }
}

output "private_nsg" {
  description = "Network Security Group object for private subnets"
  value = {
    id                = azurerm_network_security_group.private_nsg.id
    name              = azurerm_network_security_group.private_nsg.name
    resource_group    = var.resource_group.name
    location          = azurerm_network_security_group.private_nsg.location
  }
}

output "public_nsg" {
  description = "Network Security Group object for public subnets"
  value = {
    id                = azurerm_network_security_group.public_nsg.id
    name              = azurerm_network_security_group.public_nsg.name
    resource_group    = var.resource_group.name
    location          = azurerm_network_security_group.public_nsg.location
  }
}

output "public_route_table" {
  description = "Route Table object for public subnets"
  value = {
    id                = azurerm_route_table.public_route_table.id
    name              = azurerm_route_table.public_route_table.name
    resource_group    = var.resource_group.name
    location          = azurerm_route_table.public_route_table.location
  }
}

output "private_route_table" {
  description = "Route Table object for private subnets"
  value = {
    id                = azurerm_route_table.private_route_table.id
    name              = azurerm_route_table.private_route_table.name
    resource_group    = var.resource_group.name
    location          = azurerm_route_table.private_route_table.location
  }
}
