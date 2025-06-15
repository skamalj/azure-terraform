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
