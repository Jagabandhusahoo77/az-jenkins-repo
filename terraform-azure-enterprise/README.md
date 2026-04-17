# Enterprise Azure Infrastructure — Terraform

Production-grade Azure infrastructure project following the [Azure Cloud Adoption Framework (CAF)](https://docs.microsoft.com/en-us/azure/cloud-adoption-framework/).

## Architecture Overview

```
                           ┌─────────────────────────────────────────┐
                           │           HUB VNET (10.0.0.0/16)        │
                           │  ┌──────────────┐  ┌──────────────────┐ │
 ┌──────────────┐  BGP VPN │  │  Azure        │  │   VPN Gateway    │ │ ◄── On-Premises
 │  On-Premises │◄─────────┤  │  Firewall     │  │  (BGP Enabled)   │ │
 └──────────────┘          │  │  (Premium)    │  └──────────────────┘ │
                           │  └──────┬───────┘                        │
                           │         │ Inspect all spoke egress        │
                           └─────────┼───────────────────────────────-┘
                    VNet Peering     │
          ┌──────────────────────────┼──────────────────────┐
          │                          │                       │
          ▼                          ▼                       ▼
┌──────────────────┐    ┌──────────────────┐    ┌──────────────────┐
│  DEV SPOKE       │    │  STAGING SPOKE   │    │  PROD SPOKE      │
│  10.1.0.0/16     │    │  10.2.0.0/16     │    │  10.3.0.0/16     │
│ ┌──────────────┐ │    │ ┌──────────────┐ │    │ ┌──────────────┐ │
│ │ AppGW (WAF)  │ │    │ │ AppGW (WAF)  │ │    │ │ AppGW (WAF)  │ │
│ │ VMSS + LB   │ │    │ │ VMSS + LB   │ │    │ │ VMSS + LB   │ │
│ │ SQL (private)│ │    │ │ SQL (private)│ │    │ │ SQL (BC,HA) │ │
│ │ Storage      │ │    │ │ Storage      │ │    │ │ Storage(GRS) │ │
│ └──────────────┘ │    │ └──────────────┘ │    │ └──────────────┘ │
└──────────────────┘    └──────────────────┘    └──────────────────┘
```

## Project Structure

```
terraform-azure-enterprise/
├── modules/
│   ├── networking/     # Hub-spoke VNets, NSGs, Bastion, UDRs
│   ├── compute/        # VMSS, internal LB, managed identity, autoscale
│   ├── database/       # Azure SQL, private endpoint, CMK, failover group
│   ├── security/       # Azure Firewall, AppGW WAF, Key Vault, VPN GW
│   └── storage/        # Storage accounts, CMK, lifecycle, private endpoints
├── environments/
│   ├── dev/            # Dev: minimal sizing, no VPN GW, 2–4 VMSS instances
│   ├── staging/        # Staging: prod-like config, no HA
│   └── prod/           # Prod: zone-redundant, geo-replicated, full HA
├── pipelines/
│   ├── Jenkinsfile.ci  # CI: fmt, validate, lint, security scan, plan
│   └── Jenkinsfile.cd  # CD: plan, manual approval, apply (dev→staging→prod)
├── tests/
│   └── networking_test.go  # Terratest integration tests
├── scripts/
│   ├── bootstrap-backend.sh         # One-time backend storage creation
│   └── create-service-principal.sh  # Per-environment SP creation
├── docs/
│   ├── ARCHITECTURE.md
│   ├── SETUP.md
│   └── PIPELINE.md
├── .tflint.hcl    # TFLint rules
└── .checkov.yaml  # Checkov security scan config
```

## Key Design Decisions

| Decision | Rationale |
|---|---|
| Hub-and-spoke topology | Single egress point, centralised firewall inspection, cost-effective shared services |
| Azure Firewall Premium | Enables FQDN-based rules, IDPS, TLS inspection for corp traffic |
| Application Gateway WAF v2 | L7 load balancing + OWASP CRS 3.2 for web-facing apps |
| Private endpoints everywhere | SQL, Storage, Key Vault never exposed to public internet |
| Customer-managed keys (CMK) | Satisfies compliance requirements (ISO 27001, SOC2, PCI-DSS) |
| User-assigned managed identity | Identity survives resource deletion, can be pre-authorised |
| AAD-only SQL auth | Eliminates SQL passwords; access tied to corporate identity lifecycle |
| RBAC over Key Vault access policies | Auditable, granular, integrated with PIM |
| Zone-redundant resources in prod | Survives AZ failure with zero downtime |
| Geo-redundant storage + SQL failover group | Survives regional failure (DR RTO < 1 hour) |

## Quick Start

See [docs/SETUP.md](docs/SETUP.md) for detailed setup instructions.

```bash
# 1. Create backend storage (once per environment)
./scripts/bootstrap-backend.sh dev eastus

# 2. Create Service Principal
./scripts/create-service-principal.sh dev <subscription-id>

# 3. Set environment variables
export ARM_CLIENT_ID="..."
export ARM_CLIENT_SECRET="..."
export ARM_SUBSCRIPTION_ID="..."
export ARM_TENANT_ID="..."
export TF_VAR_sql_admin_password="..."
export TF_VAR_ssh_public_key="$(cat ~/.ssh/id_rsa.pub)"

# 4. Deploy dev
cd environments/dev
terraform init
terraform plan
terraform apply
```

## Environments

| Environment | VM SKU | VMSS Min/Max | SQL SKU | HA | Cost/Month* |
|---|---|---|---|---|---|
| dev | D2s_v5 | 2/4 | GP_Gen5_2 | No | ~$400 |
| staging | D4s_v5 | 2/6 | GP_Gen5_4 | No | ~$900 |
| prod | D8s_v5 | 4/20 | BC_Gen5_8 | ZRS + GRS | ~$3,500 |

*Estimates only — vary by region and actual usage*

## Security Posture

- **Network**: Hub firewall + NSGs + private endpoints + no public VM IPs
- **Identity**: Managed identity, AAD auth, least-privilege RBAC, no shared credentials
- **Data**: CMK encryption (SQL, Storage), TLS 1.2+, private connectivity only
- **Secrets**: Azure Key Vault (Premium, purge-protected), RBAC access model
- **Compliance**: Checkov CIS benchmark scanning in CI, Azure Defender for SQL
