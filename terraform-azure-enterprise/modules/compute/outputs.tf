output "vmss_id" {
  description = "Resource ID of the VMSS"
  value       = azurerm_linux_virtual_machine_scale_set.app.id
}

output "vmss_identity_principal_id" {
  description = "Principal ID of the VMSS managed identity"
  value       = azurerm_user_assigned_identity.vmss.principal_id
}

output "vmss_identity_id" {
  description = "Resource ID of the user-assigned managed identity"
  value       = azurerm_user_assigned_identity.vmss.id
}

output "lb_id" {
  description = "Resource ID of the internal Load Balancer"
  value       = azurerm_lb.internal.id
}

output "lb_frontend_ip" {
  description = "Frontend private IP of the internal Load Balancer"
  value       = var.lb_frontend_ip
}

output "backend_pool_id" {
  description = "ID of the LB backend address pool (used by AppGW for routing)"
  value       = azurerm_lb_backend_address_pool.vmss.id
}
