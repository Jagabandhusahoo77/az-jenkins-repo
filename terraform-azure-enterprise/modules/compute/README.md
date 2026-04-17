# Module: compute

Deploys a zone-balanced Linux VMSS behind an internal Standard Load Balancer with autoscaling.

## Resources Created
- User-assigned managed identity (for Key Vault access)
- Internal Standard Load Balancer (zone-redundant)
- Linux VMSS (Ubuntu 22.04, rolling upgrades, terminate notification)
- Azure Monitor Autoscale (CPU-based scale-out/in)
- RBAC assignments for the managed identity

## Key Decisions
- **User-assigned identity**: Pre-grantable before VMSS exists; survives VMSS recreation.
- **Rolling upgrade mode**: `max_batch_instance_percent = 20` ensures 80% capacity during upgrades.
- **`lifecycle { ignore_changes = [instances] }`**: Prevents Terraform from fighting autoscale manager over instance count.
- **`disable_outbound_snat = true`**: Forces egress through Azure Firewall (via UDR), not LB SNAT.

## Usage

```hcl
module "compute" {
  source = "../../modules/compute"

  workload            = "webapp"
  environment         = "dev"
  location            = "eastus"
  location_short      = "eus"
  resource_group_name = azurerm_resource_group.compute.name
  resource_group_id   = azurerm_resource_group.compute.id
  app_subnet_id       = module.networking.spoke_app_subnet_ids["app"]
  vm_sku              = "Standard_D2s_v5"
  instance_count      = 2
  autoscale_min       = 2
  autoscale_max       = 10
  ssh_public_key      = var.ssh_public_key
  lb_frontend_ip      = "10.1.1.100"
  key_vault_id        = module.security.key_vault_id
  key_vault_uri       = module.security.key_vault_uri
}
```
