# Module: database

Deploys Azure SQL Database with full enterprise security: private endpoint, CMK, AAD auth, Defender.

## Resources Created
- Azure SQL Server (TLS 1.2+, no public access, system-assigned identity)
- Azure SQL Database (configurable SKU, zone-redundant option)
- Azure Defender + Vulnerability Assessment
- TDE Customer-Managed Key (HSM-backed, auto-rotating)
- Private Endpoint + Private DNS Zone
- SQL Failover Group (optional, for prod DR)
- Key Vault secret with connection string

## Key Decisions
- **AAD authentication**: `azuread_authentication_only = false` allows break-glass SQL login. Set `true` post-migration when SQL auth is fully deprecated.
- **CMK auto-rotation**: Key expires in 1 year, auto-rotates 30 days before expiry. SQL Server continues working during rotation (dual-key window).
- **Connection string in Key Vault**: Uses AAD Default authentication — app uses managed identity, no SQL password in the string.

## Failover Group (prod only)
```hcl
deploy_failover_group = true
secondary_server_id   = "<secondary-region-sql-server-id>"
```
Auto-failover after 60 minutes of primary unavailability. Read-only endpoint enabled for reporting workloads.
