###############################################################################
# Module: storage
#
# Enterprise storage account configuration:
#   - Zone-redundant (ZRS) in dev/staging, Geo-zone-redundant (GZRS) in prod
#   - Private endpoint — no public blob access
#   - Customer-managed encryption key
#   - Immutability policy for audit/compliance containers
#   - Lifecycle management to tier old blobs to cool/archive
#   - Soft delete and versioning for accidental-deletion protection
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

resource "azurerm_storage_account" "this" {
  name                = "st${var.workload}${var.environment}${var.location_short}"
  location            = var.location
  resource_group_name = var.resource_group_name
  account_tier        = "Standard"
  # GZRS for prod: survives both zone and regional failure
  account_replication_type   = var.environment == "prod" ? "GZRS" : "ZRS"
  account_kind               = "StorageV2"
  min_tls_version            = "TLS1_2"
  https_traffic_only_enabled = true

  # Block all public access — blobs accessible only via private endpoint
  public_network_access_enabled   = false
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = true # AzureRM provider v3 requires key auth internally to verify storage readiness
  local_user_enabled              = false # CKV_AZURE_244: disable local users

  blob_properties {
    versioning_enabled  = true
    change_feed_enabled = true # required for point-in-time restore

    delete_retention_policy {
      days = 30
    }

    container_delete_retention_policy {
      days = 30
    }

    restore_policy {
      days = 29 # must be less than delete_retention_policy.days
    }
  }

  identity {
    type = "SystemAssigned"
  }

  # CKV2_AZURE_41: SAS tokens expire after 1 hour maximum
  sas_policy {
    expiration_period = "01.00:00:00"
    expiration_action = "Log"
  }

  # CKV_AZURE_33: enable queue service logging
  queue_properties {
    logging {
      delete                = true
      read                  = true
      write                 = true
      version               = "1.0"
      retention_policy_days = 10
    }
  }

  network_rules {
    default_action             = "Deny"
    bypass                     = ["AzureServices", "Logging", "Metrics"]
    virtual_network_subnet_ids = var.allowed_subnet_ids
    ip_rules                   = var.allowed_ip_ranges
  }

  tags = var.tags
}

###############################################################################
# Customer-Managed Encryption Key
###############################################################################
resource "azurerm_role_assignment" "storage_kv_crypto" {
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Crypto Service Encryption User"
  principal_id         = azurerm_storage_account.this.identity[0].principal_id
}

resource "azurerm_key_vault_key" "storage" {
  name         = "key-st-${var.workload}-${var.environment}"
  key_vault_id = var.key_vault_id
  key_type     = "RSA-HSM"
  key_size     = 2048
  key_opts     = ["unwrapKey", "wrapKey"]

  rotation_policy {
    automatic {
      time_before_expiry = "P30D"
    }
    expire_after         = "P1Y"
    notify_before_expiry = "P30D"
  }
}

resource "azurerm_storage_account_customer_managed_key" "this" {
  storage_account_id = azurerm_storage_account.this.id
  key_vault_id       = var.key_vault_id
  key_name           = azurerm_key_vault_key.storage.name

  depends_on = [azurerm_role_assignment.storage_kv_crypto]
}

###############################################################################
# Storage Containers
###############################################################################
resource "azurerm_storage_container" "containers" {
  for_each = var.containers

  name                  = each.key
  storage_account_name  = azurerm_storage_account.this.name
  container_access_type = "private" # never "blob" or "container" for enterprise storage
}

# Immutability policy for compliance/audit containers (WORM — Write Once Read Many)
resource "azurerm_storage_container_immutability_policy" "audit" {
  for_each = { for k, v in var.containers : k => v if v.immutable }

  storage_container_resource_manager_id = azurerm_storage_container.containers[each.key].resource_manager_id
  immutability_period_in_days           = 2555                      # 7 years — typical compliance requirement
  locked                                = var.environment == "prod" # lock only in prod to allow dev changes
}

###############################################################################
# Lifecycle Management — automatic tiering reduces storage costs
###############################################################################
resource "azurerm_storage_management_policy" "this" {
  storage_account_id = azurerm_storage_account.this.id

  rule {
    name    = "tier-to-cool"
    enabled = true
    filters {
      blob_types = ["blockBlob"]
    }
    actions {
      base_blob {
        tier_to_cool_after_days_since_modification_greater_than    = 30
        tier_to_archive_after_days_since_modification_greater_than = 90
        delete_after_days_since_modification_greater_than          = 365
      }
      snapshot {
        delete_after_days_since_creation_greater_than = 30
      }
      version {
        delete_after_days_since_creation = 90
      }
    }
  }
}

###############################################################################
# Private Endpoint
###############################################################################
resource "azurerm_private_endpoint" "blob" {
  name                = "pe-${azurerm_storage_account.this.name}-blob"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.pe_subnet_id

  private_service_connection {
    name                           = "psc-blob"
    private_connection_resource_id = azurerm_storage_account.this.id
    is_manual_connection           = false
    subresource_names              = ["blob"]
  }

  private_dns_zone_group {
    name                 = "blob-dns-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.blob.id]
  }

  tags = var.tags
}

resource "azurerm_private_dns_zone" "blob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "blob_hub" {
  name                  = "link-blob-hub"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.blob.name
  virtual_network_id    = var.hub_vnet_id
  registration_enabled  = false
  tags                  = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "blob_spokes" {
  for_each = var.spoke_vnet_ids

  name                  = "link-blob-${each.key}"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.blob.name
  virtual_network_id    = each.value
  registration_enabled  = false
  tags                  = var.tags
}

###############################################################################
# Diagnostic Settings — send logs to Log Analytics
###############################################################################
resource "azurerm_monitor_diagnostic_setting" "storage" {
  count                      = var.log_analytics_workspace_id != "" ? 1 : 0
  name                       = "diag-${azurerm_storage_account.this.name}"
  target_resource_id         = "${azurerm_storage_account.this.id}/blobServices/default"
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "StorageRead"
  }
  enabled_log {
    category = "StorageWrite"
  }
  enabled_log {
    category = "StorageDelete"
  }

  metric {
    category = "Transaction"
    enabled  = true
  }
}
