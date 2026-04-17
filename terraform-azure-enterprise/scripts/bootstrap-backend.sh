#!/usr/bin/env bash
###############################################################################
# bootstrap-backend.sh
#
# Creates the Azure Storage account used for Terraform remote state.
# Run this script ONCE per environment BEFORE running `terraform init`.
#
# Why a separate script?
#   The Terraform backend itself cannot be managed by Terraform (chicken-and-egg).
#   This script creates the prerequisite infrastructure using Azure CLI.
#
# Prerequisites:
#   - Azure CLI installed and logged in (`az login` or service principal env vars)
#   - Contributor role on the target subscription
#
# Usage:
#   ./scripts/bootstrap-backend.sh dev eastus
#   ./scripts/bootstrap-backend.sh staging eastus
#   ./scripts/bootstrap-backend.sh prod eastus
###############################################################################

set -euo pipefail

ENVIRONMENT=${1:?Usage: $0 <environment> <location>}
LOCATION=${2:?Usage: $0 <environment> <location>}

# Derive location short code
case "$LOCATION" in
  eastus)       LOCATION_SHORT="eus" ;;
  westus)       LOCATION_SHORT="wus" ;;
  eastus2)      LOCATION_SHORT="eus2" ;;
  westeurope)   LOCATION_SHORT="weu" ;;
  northeurope)  LOCATION_SHORT="neu" ;;
  *)            LOCATION_SHORT="${LOCATION:0:3}" ;;
esac

RESOURCE_GROUP="rg-tfstate-${ENVIRONMENT}-${LOCATION_SHORT}"
STORAGE_ACCOUNT="sttfstate${ENVIRONMENT}${LOCATION_SHORT}"
CONTAINER_NAME="tfstate"

echo "=== Bootstrapping Terraform backend ==="
echo "Environment:     ${ENVIRONMENT}"
echo "Location:        ${LOCATION}"
echo "Resource Group:  ${RESOURCE_GROUP}"
echo "Storage Account: ${STORAGE_ACCOUNT}"
echo ""

# Create Resource Group
echo "[1/4] Creating resource group..."
az group create \
  --name "${RESOURCE_GROUP}" \
  --location "${LOCATION}" \
  --tags "environment=${ENVIRONMENT}" "managed_by=bootstrap-script" "purpose=terraform-state"

# Create Storage Account
# - Standard_RAGRS: Read-Access Geo-Redundant — state is replicated for DR
# - https-only, TLS 1.2 minimum
echo "[2/4] Creating storage account..."
az storage account create \
  --name "${STORAGE_ACCOUNT}" \
  --resource-group "${RESOURCE_GROUP}" \
  --location "${LOCATION}" \
  --sku "Standard_RAGRS" \
  --kind "StorageV2" \
  --min-tls-version "TLS1_2" \
  --https-only true \
  --allow-blob-public-access false \
  --tags "environment=${ENVIRONMENT}" "managed_by=bootstrap-script" "purpose=terraform-state"

# Enable versioning and soft delete on the state container
# Protects against accidental state corruption or deletion
echo "[3/4] Configuring storage properties..."
az storage account blob-service-properties update \
  --account-name "${STORAGE_ACCOUNT}" \
  --resource-group "${RESOURCE_GROUP}" \
  --enable-versioning true \
  --enable-delete-retention true \
  --delete-retention-days 30

# Create the container
echo "[4/4] Creating tfstate container..."
az storage container create \
  --name "${CONTAINER_NAME}" \
  --account-name "${STORAGE_ACCOUNT}" \
  --auth-mode login

# Lock the storage account with a CanNotDelete lock
# Prevents accidental deletion of the state backend
az lock create \
  --name "lock-tfstate-${ENVIRONMENT}" \
  --resource-group "${RESOURCE_GROUP}" \
  --lock-type CanNotDelete \
  --notes "Terraform state backend — do not delete"

echo ""
echo "=== Backend bootstrap complete ==="
echo ""
echo "Add to your backend.tf:"
echo "  resource_group_name  = \"${RESOURCE_GROUP}\""
echo "  storage_account_name = \"${STORAGE_ACCOUNT}\""
echo "  container_name       = \"${CONTAINER_NAME}\""
echo "  key                  = \"${ENVIRONMENT}/terraform.tfstate\""
