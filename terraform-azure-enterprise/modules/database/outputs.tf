output "sql_server_id" {
  value = azurerm_mssql_server.this.id
}

output "sql_server_fqdn" {
  value = azurerm_mssql_server.this.fully_qualified_domain_name
}

output "sql_database_id" {
  value = azurerm_mssql_database.this.id
}

output "sql_database_name" {
  value = azurerm_mssql_database.this.name
}

output "sql_private_dns_zone_id" {
  description = "Private DNS zone ID for SQL Server — link additional VNets to this"
  value       = azurerm_private_dns_zone.sql.id
}

output "connection_string_secret_id" {
  description = "Key Vault secret ID containing the DB connection string"
  value       = azurerm_key_vault_secret.connection_string.id
}
