# Module: storage

Enterprise Storage Account with CMK encryption, private endpoint, lifecycle policies, and WORM immutability.

## Resources Created
- Storage Account (ZRS in dev/staging, GZRS in prod)
- CMK encryption via Key Vault (HSM-backed)
- Storage containers with optional WORM immutability (7-year retention)
- Lifecycle management policy (cool after 30d, archive after 90d, delete after 365d)
- Private Endpoint for blob + Private DNS Zone
- Diagnostic settings to Log Analytics

## Key Decisions
- **GZRS in prod**: Survives both zone and regional failure. State is replicated asynchronously to secondary region.
- **`allow_nested_items_to_be_public = false`**: Belt-and-suspenders — even if someone creates a container, it cannot be made public.
- **Immutability locked only in prod**: Locked WORM cannot be shortened — keep unlocked in dev/staging to allow test cleanup.
- **Blob versioning + soft delete**: 30-day recovery window for accidental deletes. Point-in-time restore requires versioning.

## Storage Account Naming
Azure storage account names must be globally unique, 3-24 chars, alphanumeric only.
Formula: `st` + `workload` (≤8) + `environment` (≤7) + `location_short` (≤4) = max 23 chars.
