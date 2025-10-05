output "vnet_id" {
  value = module.vnet.vnet.id
}

output "public_nsg_id" {
  value = module.vnet.public_nsg.id
}

output "subnet_ids" {
  value = { for name, subnet in module.vnet.subnets : name => subnet.id }
}

output "aks_cluster" {
  value = module.aks.aks_cluster.identity[0].principal_id
  description = "The principal ID of the AKS cluster's managed identity."
  sensitive = false
}