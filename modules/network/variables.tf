variable "resource_group" {
  description = "The resource group object"
  type = object({
    name     = string
    location = string
  })
}

variable "vnet_name" {
  type = string
}

variable "vnet_address_space" {
  type = list(string)
}

variable "subnets" {
  description = "List of subnets with name, address_prefixes, and type (public/private)"
  type = list(object({
    name             = string
    address_prefixes = list(string)
    type             = optional(string, "private") # values: "public" or "private"
  }))
}


variable "nsg_name" {
  type = string
  default = null
}

variable "route_table_name" {
  type = string
  default = null
}

variable "public_nsg_rules" {
  description = "List of NSG rules"
  type        = list(object({
    name                       = string
    priority                   = number
    direction                  = string
    access                     = string
    protocol                   = string
    source_port_range          = string
    destination_port_range     = string
    source_address_prefix      = string
    destination_address_prefix = string
  }))
  default     = []
}

variable "private_nsg_rules" {
  description = "List of NSG rules"
  type        = list(object({
    name                       = string
    priority                   = number
    direction                  = string
    access                     = string
    protocol                   = string
    source_port_range          = string
    destination_port_range     = string
    source_address_prefix      = string
    destination_address_prefix = string
  }))
  default     = []
}