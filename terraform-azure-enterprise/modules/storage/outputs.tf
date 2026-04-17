output "storage_account_id" {
  value = azurerm_storage_account.this.id
}

output "storage_account_name" {
  value = azurerm_storage_account.this.name
}

output "primary_blob_endpoint" {
  value = azurerm_storage_account.this.primary_blob_endpoint
}

output "container_names" {
  value = keys(azurerm_storage_container.containers)
}

output "blob_private_dns_zone_id" {
  value = azurerm_private_dns_zone.blob.id
}
