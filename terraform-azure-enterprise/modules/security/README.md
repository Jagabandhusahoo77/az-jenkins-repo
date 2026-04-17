# Module: security

Deploys the three security pillars: Azure Firewall, Application Gateway WAF, and Key Vault.

## Resources Created
- Azure Firewall Premium (zone-redundant) + Firewall Policy with app/network rules
- Application Gateway v2 WAF (per spoke, optional)
- Azure Key Vault Premium (purge-protected, RBAC model) + Private Endpoint
- Private DNS Zone for Key Vault
- VPN Gateway + Local Network Gateway + IPsec connection (optional)

## Key Decisions
- **Firewall Premium**: Enables IDPS and TLS inspection. `threat_intel_mode = "Alert"` logs but doesn't block known-bad IPs initially — switch to `"Deny"` after false-positive tuning.
- **Key Vault purge protection**: Cannot be disabled after enabling. Required for compliance. Means `terraform destroy` will soft-delete, not purge — run `az keyvault recover` to undo.
- **RBAC over Access Policies**: Allows JIT (Privileged Identity Management) and per-operation audit.

## Usage

```hcl
module "security" {
  source = "../../modules/security"

  hub_name            = "hub"
  workload            = "webapp"     # max 11 chars
  environment         = "dev"
  location            = "eastus"
  location_short      = "eus"
  resource_group_name = azurerm_resource_group.security.name
  firewall_subnet_id  = module.networking.firewall_subnet_id
  gateway_subnet_id   = module.networking.gateway_subnet_id
  pe_subnet_id        = module.networking.spoke_pe_subnet_ids["app"]
  hub_vnet_id         = module.networking.hub_vnet_id
  spoke_vnet_ids      = module.networking.spoke_vnet_ids
  deploy_vpn_gateway  = false
}
```
