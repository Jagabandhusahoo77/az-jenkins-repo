output "firewall_id" {
  description = "Resource ID of Azure Firewall"
  value       = azurerm_firewall.this.id
}

output "firewall_private_ip" {
  description = "Private IP of Azure Firewall — used in spoke UDRs"
  value       = azurerm_firewall.this.ip_configuration[0].private_ip_address
}

output "firewall_public_ip" {
  description = "Public IP of Azure Firewall"
  value       = azurerm_public_ip.firewall.ip_address
}

output "key_vault_id" {
  description = "Resource ID of the Key Vault"
  value       = azurerm_key_vault.this.id
}

output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       = azurerm_key_vault.this.vault_uri
}

output "key_vault_name" {
  description = "Name of the Key Vault"
  value       = azurerm_key_vault.this.name
}

output "keyvault_private_dns_zone_id" {
  description = "ID of the Key Vault private DNS zone — pass to networking module"
  value       = azurerm_private_dns_zone.keyvault.id
}

output "vpn_gateway_id" {
  description = "Resource ID of the VPN Gateway (null if not deployed)"
  value       = var.deploy_vpn_gateway ? azurerm_virtual_network_gateway.vpn[0].id : null
}

output "appgw_public_ips" {
  description = "Map of spoke name -> Application Gateway public IP"
  value       = { for k, v in azurerm_public_ip.appgw : k => v.ip_address }
}
