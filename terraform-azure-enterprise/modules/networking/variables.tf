variable "hub_name" {
  description = "Short name for the hub (used in resource naming, e.g. 'hub')"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev | staging | prod)"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging, or prod."
  }
}

variable "location" {
  description = "Primary Azure region"
  type        = string
}

variable "location_short" {
  description = "Short location code used in resource names (e.g. 'eus' for East US)"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group to deploy into"
  type        = string
}

variable "hub_address_space" {
  description = "CIDR block for the hub VNet"
  type        = string
  default     = "10.0.0.0/16"
}

variable "firewall_subnet_prefix" {
  description = "CIDR for AzureFirewallSubnet (must be /26 or larger)"
  type        = string
  default     = "10.0.1.0/26"
}

variable "gateway_subnet_prefix" {
  description = "CIDR for GatewaySubnet"
  type        = string
  default     = "10.0.0.0/27"
}

variable "bastion_subnet_prefix" {
  description = "CIDR for AzureBastionSubnet (must be /26 or larger)"
  type        = string
  default     = "10.0.0.64/26"
}

variable "management_subnet_prefix" {
  description = "CIDR for management subnet"
  type        = string
  default     = "10.0.2.0/24"
}

variable "dns_servers" {
  description = "Custom DNS server IPs (leave empty to use Azure default)"
  type        = list(string)
  default     = []
}

variable "spokes" {
  description = "Map of spoke VNets to create. Key is the spoke name."
  type = map(object({
    address_space      = string
    app_subnet_prefix  = string
    data_subnet_prefix = string
    pe_subnet_prefix   = string
    delegate_to_web    = bool
  }))
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default     = {}
}
