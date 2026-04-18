###############################################################################
# variables.tf — all inputs declared; values come from terraform.tfvars
# Sensitive values are marked sensitive = true so they're redacted in logs
###############################################################################

variable "project_name" {
  description = "Project name for tagging"
  type        = string
  default     = "enterprise-azure"
}

variable "owner" {
  description = "Team or individual owner for tagging"
  type        = string
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "eastus"
}

variable "location_short" {
  type    = string
  default = "eus"
}

variable "hub_name" {
  type    = string
  default = "hub"
}

variable "workload" {
  description = "Workload short name used across all resource names"
  type        = string
}

# Networking
variable "hub_address_space" {
  type    = string
  default = "10.0.0.0/16"
}

variable "firewall_subnet_prefix" {
  type    = string
  default = "10.0.1.0/26"
}

variable "gateway_subnet_prefix" {
  type    = string
  default = "10.0.0.0/27"
}

variable "bastion_subnet_prefix" {
  type    = string
  default = "10.0.0.64/26"
}

variable "management_subnet_prefix" {
  type    = string
  default = "10.0.2.0/24"
}

variable "spokes" {
  type = map(object({
    address_space      = string
    app_subnet_prefix  = string
    data_subnet_prefix = string
    pe_subnet_prefix   = string
    delegate_to_web    = bool
  }))
}

# Security
variable "kv_allowed_ips" {
  type    = list(string)
  default = []
}

variable "vpn_shared_key" {
  description = "Pre-shared key for the VPN tunnel to simulated on-prem"
  type        = string
  sensitive   = true
  default     = "ci-placeholder-vpn-key-32chars!!"
}

# Storage
variable "storage_containers" {
  type = map(object({
    immutable = bool
  }))
  default = {
    app-data = { immutable = false }
    audit    = { immutable = true }
    backups  = { immutable = false }
  }
}

# Database
variable "sql_admin_login" {
  type      = string
  sensitive = true
}

variable "sql_admin_password" {
  type      = string
  sensitive = true
}

variable "aad_admin_login" {
  type = string
}

variable "aad_admin_object_id" {
  type = string
}

variable "db_sku_name" {
  type    = string
  default = "GP_Gen5_2"
}

variable "db_max_size_gb" {
  type    = number
  default = 32
}

variable "security_alert_emails" {
  type    = list(string)
  default = []
}

# Compute
variable "vm_sku" {
  type    = string
  default = "Standard_D2s_v5"
}

variable "instance_count" {
  type    = number
  default = 2
}

variable "autoscale_min" {
  type    = number
  default = 2
}

variable "autoscale_max" {
  type    = number
  default = 4
}

variable "ssh_public_key" {
  type      = string
  sensitive = true
}

variable "lb_frontend_ip" {
  type    = string
  default = "10.1.1.100"
}

variable "tags" {
  type    = map(string)
  default = {}
}
