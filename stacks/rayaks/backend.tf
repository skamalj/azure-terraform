terraform {
  backend "azurerm" {
    resource_group_name  = "terraformrg"
    storage_account_name = "terraformstorageact"
    container_name       = "tfstate"
    key                  = "rayaks.terraform.tfstate"
  }
}
