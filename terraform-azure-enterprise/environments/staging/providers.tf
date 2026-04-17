###############################################################################
# providers.tf — Azure provider configuration
#
# Credentials are NOT configured here. They come from environment variables
# set by the Jenkins pipeline's Azure credentials binding:
#   ARM_CLIENT_ID       — Service Principal app ID
#   ARM_CLIENT_SECRET   — Service Principal secret (from Jenkins credential store)
#   ARM_SUBSCRIPTION_ID — Target subscription
#   ARM_TENANT_ID       — Azure AD tenant
###############################################################################
provider "azurerm" {
  features {
    key_vault {
      # Prevent accidental deletion of Key Vault during `terraform destroy`
      recover_soft_deleted_key_vaults = true
      purge_soft_delete_on_destroy    = false
    }

    resource_group {
      # Prevent destroying non-empty resource groups — safety net
      prevent_deletion_if_contains_resources = true
    }

    virtual_machine_scale_set {
      # Roll back to previous image version if health probe fails after upgrade
      roll_instances_when_required = true
      force_delete                 = false
    }
  }
}

provider "azuread" {
  # Uses same ARM_TENANT_ID, ARM_CLIENT_ID, ARM_CLIENT_SECRET env vars
}
