output "onprem_vnet_id" {
  description = "VNet ID of the simulated on-premises network"
  value       = azurerm_virtual_network.onprem.id
}

output "onprem_vnet_address_space" {
  description = "Address space of the simulated on-prem VNet"
  value       = azurerm_virtual_network.onprem.address_space
}

output "onprem_gateway_public_ip" {
  description = "Public IP of the simulated on-prem VPN gateway"
  value       = azurerm_public_ip.onprem_gw.ip_address
}

output "onprem_vm_private_ip" {
  description = "Private IP of the simulated DC VM"
  value       = azurerm_network_interface.onprem_vm.private_ip_address
}

output "onprem_resource_group_name" {
  description = "Resource group containing simulated on-prem resources"
  value       = azurerm_resource_group.onprem.name
}
