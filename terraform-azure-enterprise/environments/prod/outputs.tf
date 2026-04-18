output "hub_vnet_id" {
  value = module.networking.hub_vnet_id
}

output "firewall_private_ip" {
  description = "Used to update spoke UDRs — add to tfvars after first apply"
  value       = module.security.firewall_private_ip
}

output "key_vault_name" {
  value = module.security.key_vault_name
}

output "sql_server_fqdn" {
  description = "FQDN of SQL Server (resolves via private DNS)"
  value       = module.database.sql_server_fqdn
}

output "vmss_identity_principal_id" {
  description = "Use this to grant additional RBAC roles to the app"
  value       = module.compute.vmss_identity_principal_id
}

output "onprem_vm_private_ip" {
  description = "Private IP of simulated on-prem DC VM — use for connectivity tests"
  value       = module.simulated_onprem.onprem_vm_private_ip
}

output "onprem_vnet_address_space" {
  description = "Simulated on-prem CIDR — routes flow via VPN tunnel through hub"
  value       = module.simulated_onprem.onprem_vnet_address_space
}
