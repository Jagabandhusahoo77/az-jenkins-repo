###############################################################################
# Module: security
#
# Contains the three security pillars:
#   1. Azure Firewall — centralised L4/L7 inspection for hub-spoke traffic
#   2. Application Gateway (WAF v2) — L7 load balancing + OWASP rules for apps
#   3. Azure Key Vault — secrets / certificates / keys with RBAC access model
#
# WHY Azure Firewall AND Application Gateway?
#   AppGW WAF terminates TLS and inspects HTTP — it's application-aware.
#   Azure Firewall inspects all other egress (DNS, pip access, lateral movement).
#   Together they provide defence-in-depth at both L4 and L7.
###############################################################################

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

###############################################################################
# Azure Firewall
###############################################################################
resource "azurerm_public_ip" "firewall" {
  name                = "pip-afw-${var.environment}-${var.location_short}"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1", "2", "3"] # zone redundant

  tags = var.tags
}

resource "azurerm_firewall_policy" "this" {
  name                     = "afwp-${var.environment}-${var.location_short}"
  location                 = var.location
  resource_group_name      = var.resource_group_name
  sku                      = "Premium"
  threat_intelligence_mode = "Deny" # Deny blocks known-bad IPs, not just alerts

  dns {
    proxy_enabled = true
  }

  intrusion_detection {
    mode = "Deny" # IDPS in Deny mode — blocks malicious traffic, not just logs
  }

  tags = var.tags
}

# Application rule collection — allow specific outbound FQDNs (allowlist egress)
resource "azurerm_firewall_policy_rule_collection_group" "app_rules" {
  name               = "DefaultAppRuleCollectionGroup"
  firewall_policy_id = azurerm_firewall_policy.this.id
  priority           = 200

  application_rule_collection {
    name     = "Allow-WindowsUpdate"
    priority = 100
    action   = "Allow"
    rule {
      name             = "WindowsUpdate"
      source_addresses = ["10.0.0.0/8"]
      protocols {
        type = "Https"
        port = 443
      }
      destination_fqdns = [
        "*.update.microsoft.com",
        "*.windowsupdate.com",
        "go.microsoft.com",
      ]
    }
  }

  application_rule_collection {
    name     = "Allow-AzureServices"
    priority = 110
    action   = "Allow"
    rule {
      name             = "AzureServiceTags"
      source_addresses = ["10.0.0.0/8"]
      protocols {
        type = "Https"
        port = 443
      }
      destination_fqdn_tags = [
        "AzureKubernetesService",
        "WindowsDiagnostics",
        "MicrosoftActiveProtectionService",
      ]
    }
  }

  network_rule_collection {
    name     = "Allow-DNS"
    priority = 200
    action   = "Allow"
    rule {
      name                  = "Allow-DNS-Outbound"
      protocols             = ["UDP", "TCP"]
      source_addresses      = ["10.0.0.0/8"]
      destination_addresses = ["168.63.129.16"] # Azure DNS
      destination_ports     = ["53"]
    }
  }
}

resource "azurerm_firewall" "this" {
  name                = "afw-${var.hub_name}-${var.environment}-${var.location_short}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku_name            = "AZFW_VNet"
  sku_tier            = "Premium"
  firewall_policy_id  = azurerm_firewall_policy.this.id
  zones               = ["1", "2", "3"]

  ip_configuration {
    name                 = "configuration"
    subnet_id            = var.firewall_subnet_id
    public_ip_address_id = azurerm_public_ip.firewall.id
  }

  tags = var.tags
}

###############################################################################
# Application Gateway v2 with WAF (Web Application Firewall)
# Deployed per-spoke; use for_each to support multiple spokes
###############################################################################
resource "azurerm_public_ip" "appgw" {
  for_each = var.appgw_configs

  name                = "pip-appgw-${each.key}-${var.environment}-${var.location_short}"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1", "2", "3"]

  tags = var.tags
}

resource "azurerm_application_gateway" "this" {
  for_each = var.appgw_configs

  name                = "agw-${each.key}-${var.environment}-${var.location_short}"
  location            = var.location
  resource_group_name = var.resource_group_name

  sku {
    name     = "WAF_v2"
    tier     = "WAF_v2"
    capacity = each.value.capacity # autoscale overrides this if min/max set
  }

  autoscale_configuration {
    min_capacity = each.value.autoscale_min
    max_capacity = each.value.autoscale_max
  }

  ssl_policy {
    policy_type          = "Predefined"
    policy_name          = "AppGwSslPolicy20220101" # TLS 1.2+ only, disables TLS 1.0/1.1
    min_protocol_version = "TLSv1_2"
  }

  gateway_ip_configuration {
    name      = "appgw-ip-config"
    subnet_id = each.value.subnet_id
  }

  frontend_port {
    name = "port-443"
    port = 443
  }

  frontend_port {
    name = "port-80"
    port = 80
  }

  frontend_ip_configuration {
    name                 = "public-frontend"
    public_ip_address_id = azurerm_public_ip.appgw[each.key].id
  }

  # Backend pool — populated by compute module via AzureRM data source or passed in
  backend_address_pool {
    name = "backend-pool-${each.key}"
  }

  backend_http_settings {
    name                  = "http-settings-${each.key}"
    cookie_based_affinity = "Disabled"
    protocol              = "Http"
    port                  = 80
    request_timeout       = 60

    # Health probe
    probe_name = "health-probe-${each.key}"
  }

  probe {
    name                = "health-probe-${each.key}"
    protocol            = "Http"
    path                = each.value.health_probe_path
    host                = "127.0.0.1"
    interval            = 30
    timeout             = 30
    unhealthy_threshold = 3
  }

  http_listener {
    name                           = "https-listener-${each.key}"
    frontend_ip_configuration_name = "public-frontend"
    frontend_port_name             = "port-443"
    protocol                       = "Https"
    ssl_certificate_name           = "ssl-cert-${each.key}"
  }

  http_listener {
    name                           = "http-listener-${each.key}"
    frontend_ip_configuration_name = "public-frontend"
    frontend_port_name             = "port-80"
    protocol                       = "Http"
  }

  # HTTP -> HTTPS redirect rule
  redirect_configuration {
    name                 = "http-to-https-redirect"
    redirect_type        = "Permanent"
    target_listener_name = "https-listener-${each.key}"
    include_path         = true
    include_query_string = true
  }

  request_routing_rule {
    name                        = "http-redirect-rule"
    rule_type                   = "Basic"
    http_listener_name          = "http-listener-${each.key}"
    redirect_configuration_name = "http-to-https-redirect"
    priority                    = 10
  }

  request_routing_rule {
    name                       = "https-routing-rule"
    rule_type                  = "Basic"
    http_listener_name         = "https-listener-${each.key}"
    backend_address_pool_name  = "backend-pool-${each.key}"
    backend_http_settings_name = "http-settings-${each.key}"
    priority                   = 20
  }

  # SSL certificate sourced from Key Vault (managed identity access)
  ssl_certificate {
    name                = "ssl-cert-${each.key}"
    key_vault_secret_id = each.value.ssl_cert_secret_id
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [var.appgw_identity_id]
  }

  waf_configuration {
    enabled          = true
    firewall_mode    = "Prevention" # Prevention blocks; Detection only logs
    rule_set_type    = "OWASP"
    rule_set_version = "3.2" # OWASP CRS 3.2 — latest stable

    # Disable specific rules only when they cause false positives in your app
    # Document the reason before disabling any rule
  }

  tags = var.tags
}

###############################################################################
# Azure Key Vault
# Uses RBAC access model (not legacy Access Policies) for auditability
###############################################################################
data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "this" {
  name                       = "kv-${var.workload}-${var.environment}-${var.location_short}"
  location                   = var.location
  resource_group_name        = var.resource_group_name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "premium" # premium supports HSM-backed keys
  soft_delete_retention_days = 90        # 90-day retention prevents accidental permanent deletion
  purge_protection_enabled   = true      # blocks permanent deletion even by admins — required for compliance

  # Disable public network access; all access via private endpoint
  public_network_access_enabled = false
  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"
    ip_rules       = var.kv_allowed_ips
  }

  enable_rbac_authorization = true # RBAC over access policies — more granular, auditable

  tags = var.tags
}

# Private endpoint for Key Vault — keeps secrets off the public internet
resource "azurerm_private_endpoint" "keyvault" {
  name                = "pe-${azurerm_key_vault.this.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.pe_subnet_id

  private_service_connection {
    name                           = "psc-keyvault"
    private_connection_resource_id = azurerm_key_vault.this.id
    is_manual_connection           = false
    subresource_names              = ["vault"]
  }

  dynamic "private_dns_zone_group" {
    for_each = var.keyvault_private_dns_zone_id != "" ? [1] : []
    content {
      name                 = "keyvault-dns-zone-group"
      private_dns_zone_ids = [var.keyvault_private_dns_zone_id]
    }
  }

  tags = var.tags
}

# Grant the Terraform Service Principal "Key Vault Administrator" during initial setup
# Post-setup, this role should be removed and per-workload roles granted
resource "azurerm_role_assignment" "terraform_kv_admin" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Grant each workload managed identity read access to secrets
resource "azurerm_role_assignment" "workload_kv_secrets_user" {
  for_each = var.workload_identity_ids

  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = each.value
}

###############################################################################
# Private DNS Zones — required for private endpoint name resolution
###############################################################################
resource "azurerm_private_dns_zone" "keyvault" {
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "keyvault_hub" {
  name                  = "link-kv-hub"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.keyvault.name
  virtual_network_id    = var.hub_vnet_id
  registration_enabled  = false

  tags = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "keyvault_spokes" {
  for_each = var.spoke_vnet_ids

  name                  = "link-kv-${each.key}"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.keyvault.name
  virtual_network_id    = each.value
  registration_enabled  = false

  tags = var.tags
}

###############################################################################
# VPN Gateway — simulates on-premises connectivity
###############################################################################
resource "azurerm_public_ip" "vpn_gateway" {
  count = var.deploy_vpn_gateway ? 1 : 0

  name                = "pip-vpngw-${var.environment}-${var.location_short}"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1", "2", "3"]

  tags = var.tags
}

resource "azurerm_virtual_network_gateway" "vpn" {
  count = var.deploy_vpn_gateway ? 1 : 0

  name                = "vpngw-${var.hub_name}-${var.environment}-${var.location_short}"
  location            = var.location
  resource_group_name = var.resource_group_name
  type                = "Vpn"
  vpn_type            = "RouteBased"
  sku                 = "VpnGw2AZ" # Zone-redundant, supports BGP
  enable_bgp          = true       # BGP allows dynamic routing with on-prem
  active_active       = false      # Set true for HA with two public IPs

  ip_configuration {
    name                          = "vpngw-ipconfig"
    public_ip_address_id          = azurerm_public_ip.vpn_gateway[0].id
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = var.gateway_subnet_id
  }

  bgp_settings {
    asn = 65515 # Azure-side ASN (65515 is reserved for Azure VPN Gateways)
  }

  tags = var.tags
}

# Local Network Gateway — represents the on-premises VPN device
resource "azurerm_local_network_gateway" "onprem" {
  count = var.deploy_vpn_gateway ? 1 : 0

  name                = "lgw-onprem-${var.environment}-${var.location_short}"
  location            = var.location
  resource_group_name = var.resource_group_name
  gateway_address     = var.onprem_vpn_ip
  address_space       = var.onprem_address_spaces

  tags = var.tags
}

resource "azurerm_virtual_network_gateway_connection" "to_onprem" {
  count = var.deploy_vpn_gateway ? 1 : 0

  name                = "cn-to-onprem-${var.environment}-${var.location_short}"
  location            = var.location
  resource_group_name = var.resource_group_name

  type                       = "IPsec"
  virtual_network_gateway_id = azurerm_virtual_network_gateway.vpn[0].id
  local_network_gateway_id   = azurerm_local_network_gateway.onprem[0].id

  # Shared key should be stored in Key Vault and fetched via data source in production
  shared_key = var.vpn_shared_key

  ipsec_policy {
    dh_group         = "DHGroup14"
    ike_encryption   = "AES256"
    ike_integrity    = "SHA256"
    ipsec_encryption = "AES256"
    ipsec_integrity  = "SHA256"
    pfs_group        = "PFS14"
  }

  tags = var.tags
}
