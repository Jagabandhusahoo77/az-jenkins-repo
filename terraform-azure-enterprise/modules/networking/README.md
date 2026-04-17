# Module: networking

Implements Azure Hub-and-Spoke topology per Azure CAF.

## Resources Created
- Hub VNet + AzureFirewallSubnet, GatewaySubnet, AzureBastionSubnet, Management subnet
- N spoke VNets (one per entry in `var.spokes`) + app/data/PE subnets
- Bidirectional VNet Peering (hub ↔ each spoke)
- NSGs for app tier and data tier with deny-all-inbound defaults
- UDRs forcing spoke egress through Azure Firewall
- Azure Bastion (zone-redundant)

## Usage

```hcl
module "networking" {
  source = "../../modules/networking"

  hub_name            = "hub"
  environment         = "dev"
  location            = "eastus"
  location_short      = "eus"
  resource_group_name = azurerm_resource_group.network.name
  hub_address_space   = "10.0.0.0/16"

  spokes = {
    app = {
      address_space      = "10.1.0.0/16"
      app_subnet_prefix  = "10.1.1.0/24"
      data_subnet_prefix = "10.1.2.0/24"
      pe_subnet_prefix   = "10.1.3.0/24"
      delegate_to_web    = false
    }
  }

  firewall_private_ip = module.security.firewall_private_ip
  tags = local.tags
}
```

## Outputs
- `hub_vnet_id` — used by security module for DNS zone links
- `firewall_subnet_id` — passed to security module for Firewall deployment
- `spoke_app_subnet_ids` — passed to compute module for VMSS NIC
- `spoke_pe_subnet_ids` — passed to database/storage for private endpoints
