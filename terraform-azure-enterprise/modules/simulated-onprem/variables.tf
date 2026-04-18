variable "environment" {
  type = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging, or prod."
  }
}

variable "onprem_location" {
  description = "Azure region for simulated on-prem (use a paired region — e.g. westus2 when hub is eastus)"
  type        = string
  default     = "westus2"
}

variable "onprem_address_space" {
  description = "VNet CIDR — use 192.168.0.0/16 to mimic typical corporate RFC1918 range"
  type        = string
  default     = "192.168.0.0/16"
}

variable "onprem_gateway_subnet_prefix" {
  description = "GatewaySubnet — must be at least /27"
  type        = string
  default     = "192.168.0.0/27"
}

variable "onprem_workload_subnet_prefix" {
  description = "Subnet for simulated DC workload VMs"
  type        = string
  default     = "192.168.1.0/24"
}

variable "onprem_vm_ip" {
  description = "Static private IP for the simulated DC VM"
  type        = string
  default     = "192.168.1.10"
}

variable "hub_location" {
  description = "Region of the hub VNet (where the hub VPN gateway lives)"
  type        = string
}

variable "hub_resource_group_name" {
  description = "Resource group of the hub (connection resource lives here)"
  type        = string
}

variable "hub_vpn_gateway_id" {
  description = "Resource ID of the hub VPN gateway"
  type        = string
}

variable "hub_address_space" {
  description = "Hub VNet CIDR — used in NSG rule to allow hub-initiated SSH"
  type        = string
  default     = "10.0.0.0/16"
}

variable "vpn_shared_key" {
  description = "Pre-shared key for the VPN tunnel — store in Key Vault, inject via data source"
  type        = string
  sensitive   = true
}

variable "ssh_public_key" {
  description = "SSH public key for the simulated DC VM"
  type        = string
  sensitive   = true
}

variable "tags" {
  type    = map(string)
  default = {}
}
