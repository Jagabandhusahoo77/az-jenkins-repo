###############################################################################
# backend.tf — remote state in Azure Blob Storage
#
# WHY remote state?
#   - State is shared across team members and CI/CD pipelines
#   - Azure Blob Storage provides state locking (lease-based) preventing
#     concurrent applies that could corrupt state
#   - State is encrypted at rest using Storage Service Encryption
#
# Bootstrap: Run scripts/bootstrap-backend.sh ONCE before `terraform init`
# The backend block cannot use variables — values must be literals or passed
# via -backend-config flags (used by the Jenkins pipeline).
###############################################################################
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-tfstate-dev-eus"
    storage_account_name = "sttfstatedeveus" # created by bootstrap script
    container_name       = "tfstate"
    key                  = "dev/terraform.tfstate"

    # Authentication uses the Service Principal from environment variables:
    # ARM_CLIENT_ID, ARM_CLIENT_SECRET, ARM_SUBSCRIPTION_ID, ARM_TENANT_ID
    # These are injected by Jenkins from Azure credentials binding — never hardcoded
    use_azuread_auth = true # prefer AAD over storage key for audit trail
  }
}
