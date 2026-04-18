variable "workload" {
  description = "Short name identifying the workload (e.g. 'api', 'web')"
  type        = string
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
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "resource_group_id" {
  description = "Resource ID of the resource group (for RBAC assignment)"
  type        = string
}

variable "app_subnet_id" {
  description = "Subnet ID for the VMSS NIC"
  type        = string
}

variable "vm_sku" {
  description = "VM size (e.g. Standard_D2s_v5)"
  type        = string
  default     = "Standard_D2s_v5"
}

variable "instance_count" {
  description = "Initial instance count (autoscale will override)"
  type        = number
  default     = 2
}

variable "autoscale_min" {
  description = "Minimum instance count"
  type        = number
  default     = 2
}

variable "autoscale_max" {
  description = "Maximum instance count"
  type        = number
  default     = 10
}

variable "admin_username" {
  description = "OS admin username (no 'admin', 'root' etc.)"
  type        = string
  default     = "azureuser"
}

variable "ssh_public_key" {
  description = "SSH public key for VM access"
  type        = string
  sensitive   = true
  default     = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC0 placeholder-for-ci-plan"
}

variable "app_port" {
  description = "TCP port the application listens on"
  type        = number
  default     = 8080
}

variable "health_probe_path" {
  description = "HTTP path for the LB health probe"
  type        = string
  default     = "/health"
}

variable "lb_frontend_ip" {
  description = "Static private IP for the internal Load Balancer frontend"
  type        = string
}

variable "key_vault_id" {
  description = "Key Vault ID for RBAC role assignment"
  type        = string
}

variable "key_vault_uri" {
  description = "Key Vault URI passed to cloud-init for secret retrieval"
  type        = string
}

variable "disk_encryption_set_id" {
  description = "Disk Encryption Set ID for customer-managed key encryption"
  type        = string
  default     = null
}

variable "tags" {
  type    = map(string)
  default = {}
}
