terraform {
  backend "azurerm" {
    resource_group_name  = "rg-tfstate-prod-eus"
    storage_account_name = "sttfstateprodeus"
    container_name       = "tfstate"
    key                  = "prod/terraform.tfstate"
    use_azuread_auth     = true
  }
}
