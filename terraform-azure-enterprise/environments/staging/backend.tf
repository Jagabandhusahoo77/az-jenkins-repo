terraform {
  backend "azurerm" {
    resource_group_name  = "rg-tfstate-staging-eus"
    storage_account_name = "sttfstatestagingeus"
    container_name       = "tfstate"
    key                  = "staging/terraform.tfstate"
    use_azuread_auth     = true
  }
}
