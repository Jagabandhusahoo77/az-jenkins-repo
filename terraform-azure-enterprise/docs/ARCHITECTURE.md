# Architecture Decision Record

## 1. Network Topology — Hub and Spoke

**Decision**: Hub-and-spoke VNet topology with Azure Firewall in the hub.

**Why**:
- **Central inspection**: All spoke-to-internet and spoke-to-spoke traffic flows through the hub firewall. One policy governs all workloads.
- **Shared services**: VPN Gateway, Bastion, and DNS live in the hub. Spokes consume them via peering without duplication.
- **Isolation**: Spoke VNets cannot talk to each other directly — all east-west traffic is inspected and logged.
- **CAF alignment**: Azure CAF's Enterprise Landing Zone pattern uses this topology at scale.

**How it works**:
- User-Defined Routes (UDRs) on each spoke subnet force `0.0.0.0/0` to the Azure Firewall private IP.
- Azure Firewall policy allows specific FQDNs (allowlist egress) and blocks all else.
- VNet Peering with `allow_gateway_transit = true` on hub lets spokes use the hub's VPN Gateway.

## 2. Identity — Managed Identity + RBAC

**Decision**: User-assigned managed identity on VMSS; no service account passwords in config.

**Why**:
- Managed identities have no credentials to rotate, store, or leak.
- User-assigned (vs system-assigned) means the identity survives VMSS deletion and can be pre-granted Key Vault roles in the same Terraform apply.
- RBAC on Key Vault (instead of legacy access policies) gives per-operation auditability and integrates with Azure AD Privileged Identity Management (PIM).

**Flow**:
```
VMSS boot → IMDS token request → Azure AD issues token
     → Token used to call Key Vault → Secret returned
     → App starts with secrets in memory (never on disk)
```

## 3. Data Security — Customer-Managed Keys

**Decision**: All data at rest (SQL, Storage) encrypted with CMK stored in Key Vault Premium (HSM-backed).

**Why**:
- Platform-managed keys (PMK) mean Microsoft technically holds the key. CMK ensures only the customer can decrypt.
- Required for ISO 27001, SOC2 Type II, PCI-DSS, HIPAA compliance.
- Key rotation policy auto-rotates yearly with 30-day advance notification.

## 4. Database — Azure SQL with Private Endpoint

**Decision**: Azure SQL Database (PaaS) with private endpoint; no public network access.

**Why PaaS over IaaS SQL**:
- Microsoft manages patching, backups, HA, and replication.
- Built-in zone redundancy and geo-replication (Business Critical tier in prod).
- Azure Defender for SQL provides runtime threat detection without agent deployment.

**Why private endpoint**:
- SQL never traverses the public internet. DNS resolves `*.database.windows.net` to the private IP via Private DNS Zone linked to hub and spokes.
- Eliminates IP allowlisting; access is network-topology-controlled.

## 5. Application Gateway + Azure Firewall (Defence in Depth)

**Decision**: Application Gateway WAF v2 in each spoke + Azure Firewall Premium in hub.

**Why both**:
| Layer | Tool | What it protects against |
|---|---|---|
| L7 (HTTP) | AppGW WAF v2 (OWASP CRS 3.2) | SQL injection, XSS, CSRF, scanner bots |
| L4/L7 (all traffic) | Azure Firewall Premium | Lateral movement, C2 callbacks, DNS tunnelling, IDPS |

HTTP/S traffic path: `Internet → AppGW (TLS termination + WAF) → Internal LB → VMSS`
Other egress path: `VMSS → UDR → Azure Firewall → Internet`

## 6. Multi-Region Design (Prod)

**Decision**: Primary region East US; DR in West US via SQL failover group + GRS storage.

**Recovery targets**:
- RPO (data loss): < 1 hour (SQL auto-failover after 60 min)
- RTO (downtime): < 2 hours (manual DNS cutover to secondary AppGW)

**Why not active-active**:
- Active-active requires synchronous SQL replication, doubling database cost.
- For most workloads, 2-hour RTO is acceptable and costs 40% less than active-active.

## 7. State Management — Remote Backend with Locking

**Decision**: Azure Blob Storage backend with Azure AD authentication and blob versioning.

**Why**:
- Blob Storage provides **lease-based locking** — only one `terraform apply` runs at a time.
- `use_azuread_auth = true` means the Service Principal's identity (not a storage key) is used — access is revocable and auditable.
- Blob versioning provides a 30-day history of state files — essential for recovering from botched applies.
- State per environment in separate storage accounts prevents cross-environment state corruption.

## 8. CI/CD Separation of Concerns

**Decision**: Two separate Jenkinsfiles — CI (Multibranch) and CD (Centralised).

**Why**:
- CI runs on every branch push. It validates, lints, scans, and plans — but never applies. Safe to run on feature branches.
- CD runs only on merge to `main`. It applies in sequence with a manual gate before prod. Keeps the blast radius contained.
- Separate pipelines allow different Service Principal permissions: CI SP is read-only; CD SP has Contributor.
