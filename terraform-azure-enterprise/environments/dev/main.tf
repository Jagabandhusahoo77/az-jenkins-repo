###############################################################################
# environments/dev/main.tf
#
# Root module for the dev environment.
# Orchestrates all child modules with dev-appropriate sizing and settings.
###############################################################################

###############################################################################
# Resource Groups
# Separate RGs per concern for RBAC scope and cost tracking
###############################################################################
resource "azurerm_resource_group" "network" {
  name     = "rg-network-${var.environment}-${var.location_short}"
  location = var.location
  tags     = local.tags
}

resource "azurerm_resource_group" "security" {
  name     = "rg-security-${var.environment}-${var.location_short}"
  location = var.location
  tags     = local.tags
}

resource "azurerm_resource_group" "compute" {
  name     = "rg-compute-${var.environment}-${var.location_short}"
  location = var.location
  tags     = local.tags
}

resource "azurerm_resource_group" "data" {
  name     = "rg-data-${var.environment}-${var.location_short}"
  location = var.location
  tags     = local.tags
}

###############################################################################
# Networking — hub-spoke topology
###############################################################################
module "networking" {
  source = "../../modules/networking"

  hub_name                 = var.hub_name
  environment              = var.environment
  location                 = var.location
  location_short           = var.location_short
  resource_group_name      = azurerm_resource_group.network.name
  hub_address_space        = var.hub_address_space
  firewall_subnet_prefix   = var.firewall_subnet_prefix
  gateway_subnet_prefix    = var.gateway_subnet_prefix
  bastion_subnet_prefix    = var.bastion_subnet_prefix
  management_subnet_prefix = var.management_subnet_prefix
  spokes                   = var.spokes
  tags                     = local.tags

  depends_on = [azurerm_resource_group.network]
}

###############################################################################
# Security — Firewall, Key Vault, (no VPN in dev to save cost)
###############################################################################
module "security" {
  source = "../../modules/security"

  hub_name                    = var.hub_name
  workload                    = var.workload
  environment                 = var.environment
  location                    = var.location
  location_short              = var.location_short
  resource_group_name         = azurerm_resource_group.security.name
  network_resource_group_name = azurerm_resource_group.network.name
  firewall_subnet_id          = module.networking.firewall_subnet_id
  gateway_subnet_id           = module.networking.gateway_subnet_id
  pe_subnet_id                = module.networking.spoke_pe_subnet_ids["app"]
  hub_vnet_id                 = module.networking.hub_vnet_id
  spoke_vnet_ids              = module.networking.spoke_vnet_ids
  kv_allowed_ips              = var.kv_allowed_ips
  deploy_vpn_gateway          = false # VPN Gateway ~$140/month — skip in dev
  tags                        = local.tags

  depends_on = [module.networking]
}

###############################################################################
# Storage
###############################################################################
module "storage" {
  source = "../../modules/storage"

  workload            = var.workload
  environment         = var.environment
  location            = var.location
  location_short      = var.location_short
  resource_group_name = azurerm_resource_group.data.name
  pe_subnet_id        = module.networking.spoke_pe_subnet_ids["app"]
  hub_vnet_id         = module.networking.hub_vnet_id
  spoke_vnet_ids      = module.networking.spoke_vnet_ids
  key_vault_id        = module.security.key_vault_id
  containers          = var.storage_containers
  tags                = local.tags

  depends_on = [module.security]
}

###############################################################################
# Database
###############################################################################
module "database" {
  source = "../../modules/database"

  workload              = var.workload
  environment           = var.environment
  location              = var.location
  location_short        = var.location_short
  resource_group_name   = azurerm_resource_group.data.name
  sql_admin_login       = var.sql_admin_login
  sql_admin_password    = var.sql_admin_password
  aad_admin_login       = var.aad_admin_login
  aad_admin_object_id   = var.aad_admin_object_id
  db_sku_name           = var.db_sku_name
  db_max_size_gb        = var.db_max_size_gb
  pe_subnet_id          = module.networking.spoke_pe_subnet_ids["app"]
  hub_vnet_id           = module.networking.hub_vnet_id
  spoke_vnet_ids        = module.networking.spoke_vnet_ids
  key_vault_id          = module.security.key_vault_id
  security_alert_emails = var.security_alert_emails
  tags                  = local.tags

  depends_on = [module.security]
}

###############################################################################
# Compute — VMSS application tier
###############################################################################
module "compute" {
  source = "../../modules/compute"

  workload            = var.workload
  environment         = var.environment
  location            = var.location
  location_short      = var.location_short
  resource_group_name = azurerm_resource_group.compute.name
  resource_group_id   = azurerm_resource_group.compute.id
  app_subnet_id       = module.networking.spoke_app_subnet_ids["app"]
  vm_sku              = var.vm_sku
  instance_count      = var.instance_count
  autoscale_min       = var.autoscale_min
  autoscale_max       = var.autoscale_max
  ssh_public_key      = var.ssh_public_key
  lb_frontend_ip      = var.lb_frontend_ip
  key_vault_id        = module.security.key_vault_id
  key_vault_uri       = module.security.key_vault_uri
  tags                = local.tags

  depends_on = [module.networking, module.security]
}

###############################################################################
# Route Tables — lives here (not in networking module) to break the cycle:
# networking needs security's firewall IP, security needs networking's subnet ID.
# Both are available at environment scope after both modules resolve.
###############################################################################
resource "azurerm_route_table" "spoke" {
  for_each = var.spokes

  name                          = "rt-${each.key}-${var.environment}-${var.location_short}"
  location                      = var.location
  resource_group_name           = azurerm_resource_group.network.name
  bgp_route_propagation_enabled = false

  route {
    name                   = "default-to-firewall"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = module.security.firewall_private_ip
  }

  tags = local.tags

  depends_on = [module.networking, module.security]
}

resource "azurerm_subnet_route_table_association" "spoke_app" {
  for_each = var.spokes

  subnet_id      = module.networking.spoke_app_subnet_ids[each.key]
  route_table_id = azurerm_route_table.spoke[each.key].id
}

resource "azurerm_subnet_route_table_association" "spoke_data" {
  for_each = var.spokes

  subnet_id      = module.networking.spoke_data_subnet_ids[each.key]
  route_table_id = azurerm_route_table.spoke[each.key].id
}

###############################################################################
# Locals
###############################################################################
locals {
  tags = merge(var.tags, {
    environment = var.environment
    managed_by  = "terraform"
    project     = var.project_name
    owner       = var.owner
  })
}
