variable "hub_name" {
  type = string
}

variable "workload" {
  description = "Workload name used in Key Vault naming (max 11 chars due to KV name limit of 24)"
  type        = string
  validation {
    condition     = length(var.workload) <= 11
    error_message = "workload must be 11 characters or fewer to stay within the 24-char Key Vault name limit."
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
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "network_resource_group_name" {
  description = "Resource group of the hub VNet — Firewall must be in same RG as its subnet"
  type        = string
}

variable "firewall_subnet_id" {
  description = "ID of AzureFirewallSubnet in the hub VNet"
  type        = string
}

variable "gateway_subnet_id" {
  description = "ID of GatewaySubnet in the hub VNet"
  type        = string
}

variable "pe_subnet_id" {
  description = "Subnet ID for private endpoints"
  type        = string
}

variable "hub_vnet_id" {
  description = "Hub VNet ID (for DNS zone link)"
  type        = string
}

variable "spoke_vnet_ids" {
  description = "Map of spoke name -> VNet ID (for DNS zone links)"
  type        = map(string)
  default     = {}
}

variable "appgw_configs" {
  description = "Map of Application Gateway configurations per spoke"
  type = map(object({
    subnet_id          = string
    capacity           = number
    autoscale_min      = number
    autoscale_max      = number
    health_probe_path  = string
    ssl_cert_secret_id = string
  }))
  default = {}
}

variable "appgw_identity_id" {
  description = "User-assigned managed identity ID for AppGW to read Key Vault certs"
  type        = string
  default     = ""
}

variable "kv_allowed_ips" {
  description = "IP ranges allowed to access Key Vault over public internet (for emergency break-glass)"
  type        = list(string)
  default     = []
}

variable "workload_identity_ids" {
  description = "Map of workload name -> principal ID for Key Vault Secrets User role"
  type        = map(string)
  default     = {}
}

variable "keyvault_private_dns_zone_id" {
  description = "Existing private DNS zone ID for Key Vault (use output from this module)"
  type        = string
  default     = ""
}

variable "deploy_vpn_gateway" {
  description = "Whether to deploy the VPN Gateway (expensive — skip for dev)"
  type        = bool
  default     = false
}

variable "onprem_vpn_ip" {
  description = "Public IP of the on-premises VPN device"
  type        = string
  default     = "1.2.3.4"
}

variable "onprem_address_spaces" {
  description = "On-premises CIDR blocks accessible via VPN"
  type        = list(string)
  default     = ["192.168.0.0/16"]
}

variable "vpn_shared_key" {
  description = "IPsec pre-shared key (fetch from Key Vault in prod, not hardcoded)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "tags" {
  type    = map(string)
  default = {}
}
