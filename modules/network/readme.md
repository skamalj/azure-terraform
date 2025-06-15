# Terraform Azure VNet Module

This module creates an Azure Virtual Network with multiple subnets, associated Network Security Groups (NSGs), and route tables for public and private subnet segregation.

---

## Features

- Creates a Virtual Network with configurable address space.
- Supports multiple subnets with individual address prefixes and public/private designation.
- Creates separate NSGs for public and private subnets.
- Creates separate route tables for public and private subnets.
- Automatically associates subnets with corresponding NSGs and route tables.

---

## Usage Example

```hcl
module "vnet" {
  source = "../../modules/network/vnet"

  vnet_name          = "my-vnet"
  vnet_address_space = ["10.0.0.0/16"]

  resource_group = {
    name     = "myResourceGroup"
    location = "Central India"
  }

  subnets = [
    {
      name             = "public-subnet-1"
      address_prefixes = ["10.0.1.0/24"]
      type             = "public"
    },
    {
      name             = "private-subnet-1"
      address_prefixes = ["10.0.2.0/24"]
      type             = "private"
    }
  ]
}
```

---

## Inputs

| Name                | Description                                          | Type           | Required | Default |
|---------------------|----------------------------------------------------|----------------|----------|---------|
| `vnet_name`         | Name of the virtual network                         | `string`       | yes      | n/a     |
| `vnet_address_space` | Address space for the VNet                          | `list(string)` | yes      | n/a     |
| `resource_group`    | Object with resource group `name` and `location`    | `object`       | yes      | n/a     |
| `subnets`           | List of subnet objects with `name`, `address_prefixes`, and `type` (`public` or `private`) | `list(object)` | yes      | n/a     |

Example `subnets` element:

```hcl
{
  name             = "subnet-name"
  address_prefixes = ["10.0.1.0/24"]
  type             = "public" # or "private"
}
```

---

## Outputs

| Name                  | Description                                           |
|-----------------------|-----------------------------------------------------|
| `vnet`                | Object with VNet details (id, name, address space, location) |
| `subnets`             | Map of subnet objects keyed by subnet name (id, name, address prefixes, type, etc.) |
| `private_nsg`         | Private subnet Network Security Group object (id, name) |
| `public_nsg`          | Public subnet Network Security Group object (id, name)  |
| `private_route_table` | Private subnet route table object (id, name)             |
| `public_route_table`  | Public subnet route table object (id, name)              |

---

## Notes

- Subnets are associated with their respective NSGs and route tables automatically based on the `type` property.
- The `default_outbound_access_enabled` is enabled for public subnets.
- You can modify NSG rules after deployment as per your security requirements.
- This module expects the resource group details (`name` and `location`) to be passed in as an object, so resource group creation should happen outside this module.

---

## Requirements

- Terraform >= 1.0
- AzureRM provider >= 3.0

---
