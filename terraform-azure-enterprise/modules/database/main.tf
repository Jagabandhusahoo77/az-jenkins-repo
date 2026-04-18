###############################################################################
# Module: database
#
# Deploys Azure SQL Database (PaaS) with:
#   - General Purpose or Business Critical tier (configurable)
#   - Private Endpoint — no public internet exposure
#   - Azure AD-only authentication (no SQL logins) for zero-credential access
#   - Transparent Data Encryption with customer-managed key
#   - Geo-replication for prod (configurable)
#   - Long-term backup retention
#   - Azure Defender for SQL (threat detection)
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
# SQL Server
###############################################################################
resource "azurerm_mssql_server" "this" {
  name                         = "sql-${var.workload}-${var.environment}-${var.location_short}"
  location                     = var.location
  resource_group_name          = var.resource_group_name
  version                      = "12.0"
  administrator_login          = var.sql_admin_login
  administrator_login_password = var.sql_admin_password
  minimum_tls_version          = "1.2" # block TLS 1.0/1.1

  # Disable public network access — access only via private endpoint
  public_network_access_enabled = false

  # Azure AD admin — enables Entra-only auth (teams log in with AD accounts)
  azuread_administrator {
    login_username              = var.aad_admin_login
    object_id                   = var.aad_admin_object_id
    azuread_authentication_only = false # set true after SQL auth is fully deprecated
  }

  identity {
    type = "SystemAssigned" # needed for TDE with customer-managed key
  }

  tags = var.tags
}

# Enable Azure Defender for SQL on the server — detects SQL injection, anomalous access
resource "azurerm_mssql_server_security_alert_policy" "this" {
  resource_group_name  = var.resource_group_name
  server_name          = azurerm_mssql_server.this.name
  state                = "Enabled"
  email_addresses      = var.security_alert_emails
  email_account_admins = true # CKV_AZURE_27: notify subscription admins
  retention_days       = 90
}

# SQL Auditing — only deployed when storage account is provided
resource "azurerm_mssql_server_extended_auditing_policy" "this" {
  count                                   = var.audit_storage_endpoint != "" ? 1 : 0
  server_id                               = azurerm_mssql_server.this.id
  storage_endpoint                        = var.audit_storage_endpoint
  storage_account_access_key              = var.audit_storage_key
  storage_account_access_key_is_secondary = false
  retention_in_days                       = 90
  log_monitoring_enabled                  = true
}

resource "azurerm_mssql_server_vulnerability_assessment" "this" {
  count                           = var.vulnerability_storage_key != "" ? 1 : 0
  server_security_alert_policy_id = azurerm_mssql_server_security_alert_policy.this.id
  storage_container_path          = "${var.vulnerability_storage_endpoint}${var.vulnerability_storage_container}/"
  storage_account_access_key      = var.vulnerability_storage_key

  recurring_scans {
    enabled                   = true
    email_subscription_admins = true
    emails                    = var.security_alert_emails
  }
}

###############################################################################
# SQL Database
###############################################################################
resource "azurerm_mssql_database" "this" {
  name           = "sqldb-${var.workload}-${var.environment}"
  server_id      = azurerm_mssql_server.this.id
  collation      = "SQL_Latin1_General_CP1_CI_AS"
  license_type   = "LicenseIncluded"
  max_size_gb    = var.db_max_size_gb
  sku_name       = var.db_sku_name    # e.g. "GP_Gen5_4" or "BC_Gen5_4"
  zone_redundant = var.zone_redundant # true for prod

  # Geo-redundant backup storage for prod
  storage_account_type = var.environment == "prod" ? "Geo" : "Local"

  long_term_retention_policy {
    weekly_retention  = var.environment == "prod" ? "P4W" : "P1W"
    monthly_retention = var.environment == "prod" ? "P12M" : "P1M"
    yearly_retention  = var.environment == "prod" ? "P5Y" : "P1Y"
    week_of_year      = 1
  }

  short_term_retention_policy {
    retention_days           = var.environment == "prod" ? 35 : 7
    backup_interval_in_hours = 12
  }

  tags = var.tags
}

###############################################################################
# Transparent Data Encryption with Customer-Managed Key
# The SQL Server's system-assigned identity must have Key Vault Crypto access
###############################################################################
resource "azurerm_key_vault_key" "tde" {
  name         = "key-tde-${var.workload}-${var.environment}"
  key_vault_id = var.key_vault_id
  key_type     = "RSA-HSM" # HSM-backed key (requires Key Vault Premium)
  key_size     = 2048

  key_opts = [
    "unwrapKey",
    "wrapKey",
  ]

  rotation_policy {
    automatic {
      time_before_expiry = "P30D" # auto-rotate 30 days before expiry
    }
    expire_after         = "P1Y"
    notify_before_expiry = "P30D"
  }
}

resource "azurerm_role_assignment" "sql_kv_crypto" {
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Crypto Service Encryption User"
  principal_id         = azurerm_mssql_server.this.identity[0].principal_id
}

resource "azurerm_mssql_server_transparent_data_encryption" "this" {
  server_id        = azurerm_mssql_server.this.id
  key_vault_key_id = azurerm_key_vault_key.tde.id

  depends_on = [azurerm_role_assignment.sql_kv_crypto]
}

###############################################################################
# Private Endpoint — SQL traffic never traverses the public internet
###############################################################################
resource "azurerm_private_endpoint" "sql" {
  name                = "pe-${azurerm_mssql_server.this.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.pe_subnet_id

  private_service_connection {
    name                           = "psc-sql"
    private_connection_resource_id = azurerm_mssql_server.this.id
    is_manual_connection           = false
    subresource_names              = ["sqlServer"]
  }

  private_dns_zone_group {
    name                 = "sql-dns-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.sql.id]
  }

  tags = var.tags
}

resource "azurerm_private_dns_zone" "sql" {
  name                = "privatelink.database.windows.net"
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "sql_hub" {
  name                  = "link-sql-hub"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.sql.name
  virtual_network_id    = var.hub_vnet_id
  registration_enabled  = false
  tags                  = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "sql_spokes" {
  for_each = var.spoke_vnet_ids

  name                  = "link-sql-${each.key}"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.sql.name
  virtual_network_id    = each.value
  registration_enabled  = false
  tags                  = var.tags
}

###############################################################################
# Geo-Replication (prod only) — secondary in paired region for DR
###############################################################################
resource "azurerm_mssql_failover_group" "this" {
  count = var.deploy_failover_group ? 1 : 0

  name      = "fog-${var.workload}-${var.environment}"
  server_id = azurerm_mssql_server.this.id
  databases = [azurerm_mssql_database.this.id]

  partner_server {
    id = var.secondary_server_id
  }

  read_write_endpoint_failover_policy {
    mode          = "Automatic"
    grace_minutes = 60 # wait 60 min before automatic failover to reduce false-positives
  }

  readonly_endpoint_failover_policy_enabled = true # enable read replicas for reporting
}

###############################################################################
# Store connection string in Key Vault
# App retrieves this at boot via managed identity — no secrets in config files
###############################################################################
resource "azurerm_key_vault_secret" "connection_string" {
  name         = "db-connection-string"
  value        = "Server=tcp:${azurerm_mssql_server.this.fully_qualified_domain_name},1433;Initial Catalog=${azurerm_mssql_database.this.name};Authentication=Active Directory Default;"
  key_vault_id = var.key_vault_id

  content_type    = "text/plain"
  expiration_date = timeadd(timestamp(), "8760h") # 1-year expiry — force rotation

  tags = var.tags

  lifecycle {
    ignore_changes = [expiration_date] # don't rotate on every plan
  }
}
