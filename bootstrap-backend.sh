#!/bin/bash
set -e

LOCATION="eastus"

declare -A ENVS
ENVS["dev"]="rg-tfstate-dev-eus|sttfstatedeveus"
ENVS["staging"]="rg-tfstate-staging-eus|sttfstatestagingeus"
ENVS["prod"]="rg-tfstate-prod-eus|sttfstateprodeus"

for ENV in dev staging prod; do
  IFS='|' read -r RG SA <<< "${ENVS[$ENV]}"

  echo ""
  echo "=== $ENV ==="

  az group create --name "$RG" --location "$LOCATION" --output none
  echo "  [1/4] Resource group created: $RG"

  az storage account create \
    --name "$SA" \
    --resource-group "$RG" \
    --location "$LOCATION" \
    --sku Standard_GRS \
    --kind StorageV2 \
    --min-tls-version TLS1_2 \
    --https-only true \
    --allow-blob-public-access false \
    --output none
  echo "  [2/4] Storage account created: $SA"

  az storage account blob-service-properties update \
    --account-name "$SA" \
    --resource-group "$RG" \
    --enable-versioning true \
    --output none
  echo "  [3/4] Versioning enabled"

  az storage container create \
    --name "tfstate" \
    --account-name "$SA" \
    --auth-mode login \
    --output none
  echo "  [4/4] Container created: tfstate"

done

echo ""
echo "Bootstrap complete."
