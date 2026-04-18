variable "workload" {
  type = string
}

variable "environment" {
  type = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging, or prod."
  }
}

variable "location" {
  type = string
}

variable "sql_location" {
  description = "Azure region for SQL Server — can differ from main location if eastus has quota restrictions"
  type        = string
  default     = ""
}

variable "location_short" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "sql_admin_login" {
  description = "SQL Server administrator username (for break-glass; normal access uses AAD)"
  type        = string
  sensitive   = true
}

variable "sql_admin_password" {
  description = "SQL Server administrator password (stored in Key Vault, never hardcoded)"
  type        = string
  sensitive   = true
}

variable "aad_admin_login" {
  description = "Display name of the Azure AD admin group or user"
  type        = string
}

variable "aad_admin_object_id" {
  description = "Object ID of the Azure AD admin"
  type        = string
}

variable "db_sku_name" {
  description = "SQL Database SKU (e.g. GP_Gen5_2, BC_Gen5_4)"
  type        = string
  default     = "GP_Gen5_2"
}

variable "db_max_size_gb" {
  description = "Maximum database size in GB"
  type        = number
  default     = 32
}

variable "zone_redundant" {
  description = "Enable zone redundancy (prod only, adds cost)"
  type        = bool
  default     = false
}

variable "pe_subnet_id" {
  description = "Subnet ID for private endpoints"
  type        = string
}

variable "hub_vnet_id" {
  description = "Hub VNet ID for DNS zone link"
  type        = string
}

variable "spoke_vnet_ids" {
  description = "Map of spoke name -> VNet ID for DNS zone links"
  type        = map(string)
  default     = {}
}

variable "key_vault_id" {
  description = "Key Vault ID for TDE key and connection string secret"
  type        = string
}

variable "security_alert_emails" {
  description = "Email addresses for SQL Defender alerts"
  type        = list(string)
  default     = []
}

variable "vulnerability_storage_endpoint" {
  description = "Storage account endpoint for vulnerability assessment reports"
  type        = string
  default     = ""
}

variable "vulnerability_storage_container" {
  description = "Blob container name for vulnerability assessment reports"
  type        = string
  default     = "vulnerability-assessment"
}

variable "vulnerability_storage_key" {
  description = "Storage account access key for vulnerability assessment"
  type        = string
  sensitive   = true
  default     = ""
}

variable "audit_storage_endpoint" {
  description = "Storage account endpoint for SQL audit logs"
  type        = string
  default     = ""
}

variable "audit_storage_key" {
  description = "Storage account access key for SQL audit logs"
  type        = string
  sensitive   = true
  default     = ""
}

variable "deploy_failover_group" {
  description = "Deploy SQL failover group (prod HA)"
  type        = bool
  default     = false
}

variable "secondary_server_id" {
  description = "Resource ID of the secondary SQL Server for failover group"
  type        = string
  default     = ""
}

variable "tags" {
  type    = map(string)
  default = {}
}
