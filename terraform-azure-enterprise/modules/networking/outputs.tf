output "hub_vnet_id" {
  description = "Resource ID of the hub VNet"
  value       = azurerm_virtual_network.hub.id
}

output "hub_vnet_name" {
  description = "Name of the hub VNet"
  value       = azurerm_virtual_network.hub.name
}

output "firewall_subnet_id" {
  description = "ID of AzureFirewallSubnet"
  value       = azurerm_subnet.firewall.id
}

output "gateway_subnet_id" {
  description = "ID of GatewaySubnet"
  value       = azurerm_subnet.gateway.id
}

output "spoke_vnet_ids" {
  description = "Map of spoke name -> VNet resource ID"
  value       = { for k, v in azurerm_virtual_network.spoke : k => v.id }
}

output "spoke_app_subnet_ids" {
  description = "Map of spoke name -> app subnet ID"
  value       = { for k, v in azurerm_subnet.spoke_app : k => v.id }
}

output "spoke_data_subnet_ids" {
  description = "Map of spoke name -> data subnet ID"
  value       = { for k, v in azurerm_subnet.spoke_data : k => v.id }
}

output "spoke_pe_subnet_ids" {
  description = "Map of spoke name -> private endpoint subnet ID"
  value       = { for k, v in azurerm_subnet.spoke_pe : k => v.id }
}

output "bastion_public_ip" {
  description = "Public IP address of Azure Bastion"
  value       = azurerm_public_ip.bastion.ip_address
}
