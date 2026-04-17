#!/usr/bin/env bash
###############################################################################
# create-service-principal.sh
#
# Creates per-environment Azure Service Principals with minimum required
# permissions for Terraform to deploy infrastructure.
#
# Least-privilege model:
#   - dev:     Contributor on dev subscription + User Access Administrator
#   - staging: Contributor on staging subscription
#   - prod:    Contributor on prod subscription (separate account recommended)
#
# The output credentials must be stored in Jenkins Credentials Store manually.
# Never commit credentials to source control.
#
# Usage:
#   ./scripts/create-service-principal.sh dev <subscription-id>
###############################################################################

set -euo pipefail

ENVIRONMENT=${1:?Usage: $0 <environment> <subscription-id>}
SUBSCRIPTION_ID=${2:?Usage: $0 <environment> <subscription-id>}

SP_NAME="sp-terraform-${ENVIRONMENT}-$(date +%Y%m)"

echo "=== Creating Service Principal ==="
echo "Name:           ${SP_NAME}"
echo "Environment:    ${ENVIRONMENT}"
echo "Subscription:   ${SUBSCRIPTION_ID}"
echo ""

# Create SP with Contributor role scoped to subscription
SP_OUTPUT=$(az ad sp create-for-rbac \
  --name "${SP_NAME}" \
  --role "Contributor" \
  --scopes "/subscriptions/${SUBSCRIPTION_ID}" \
  --output json)

CLIENT_ID=$(echo "$SP_OUTPUT" | python3 -c "import sys,json; print(json.load(sys.stdin)['appId'])")
CLIENT_SECRET=$(echo "$SP_OUTPUT" | python3 -c "import sys,json; print(json.load(sys.stdin)['password'])")
TENANT_ID=$(echo "$SP_OUTPUT" | python3 -c "import sys,json; print(json.load(sys.stdin)['tenant'])")

# User Access Administrator is needed to create role assignments (for managed identities)
az role assignment create \
  --assignee "${CLIENT_ID}" \
  --role "User Access Administrator" \
  --scope "/subscriptions/${SUBSCRIPTION_ID}"

# Key Vault Administrator — needed to create Key Vaults and manage keys
az role assignment create \
  --assignee "${CLIENT_ID}" \
  --role "Key Vault Administrator" \
  --scope "/subscriptions/${SUBSCRIPTION_ID}"

echo ""
echo "=== Service Principal Created ==="
echo ""
echo "Store these in Jenkins Credentials as 'azure-sp-${ENVIRONMENT}':"
echo "  Username (Client ID):     ${CLIENT_ID}"
echo "  Password (Client Secret): ${CLIENT_SECRET}"
echo ""
echo "Store these as secret text credentials:"
echo "  azure-subscription-id: ${SUBSCRIPTION_ID}"
echo "  azure-tenant-id:       ${TENANT_ID}"
echo ""
echo "Set these environment variables for the SP itself:"
cat <<EOF
export ARM_CLIENT_ID="${CLIENT_ID}"
export ARM_CLIENT_SECRET="${CLIENT_SECRET}"
export ARM_SUBSCRIPTION_ID="${SUBSCRIPTION_ID}"
export ARM_TENANT_ID="${TENANT_ID}"
EOF
echo ""
echo "WARNING: CLIENT_SECRET shown once. Store it immediately in Jenkins."
