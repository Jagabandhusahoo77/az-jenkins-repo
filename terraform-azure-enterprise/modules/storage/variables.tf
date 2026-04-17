variable "workload" {
  description = "Short name (max 8 chars — storage account names are limited to 24 alphanumeric)"
  type        = string
  validation {
    condition     = length(var.workload) <= 8
    error_message = "workload must be 8 characters or fewer for storage account naming."
  }
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

variable "location_short" {
  description = "Short location code (max 4 chars for storage account naming)"
  type        = string
}

variable "resource_group_name" {
  type = string
}

variable "pe_subnet_id" {
  type = string
}

variable "hub_vnet_id" {
  type = string
}

variable "spoke_vnet_ids" {
  type    = map(string)
  default = {}
}

variable "key_vault_id" {
  type = string
}

variable "allowed_subnet_ids" {
  description = "Subnet IDs allowed to access the storage account via service endpoint"
  type        = list(string)
  default     = []
}

variable "allowed_ip_ranges" {
  description = "IP ranges allowed for emergency/management access"
  type        = list(string)
  default     = []
}

variable "containers" {
  description = "Map of container name -> config"
  type = map(object({
    immutable = bool
  }))
  default = {
    app-data = { immutable = false }
    audit    = { immutable = true }
    backups  = { immutable = false }
  }
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace for diagnostic logs"
  type        = string
  default     = ""
}

variable "tags" {
  type    = map(string)
  default = {}
}
