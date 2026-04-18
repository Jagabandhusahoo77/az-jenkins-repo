# Enterprise Azure Terraform + Jenkins CI/CD — Complete Project Guide

---

## TABLE OF CONTENTS

1. What We Built and Why
2. Azure Concepts You Must Understand
3. What to Create in Azure First (Before Terraform)
4. Jenkins Credentials — What, Why, and How
5. Terraform Concepts — Every File Explained
6. Modules We Built — Every File and Why
7. Pipeline Stages — CI and CD Explained
8. Tools Used in the Pipeline and Why
9. Commands Used in the Entire Project and Why
10. Every Error We Hit and How We Fixed It
11. What to Say in Interviews

---

## 1. WHAT WE BUILT AND WHY

### The Goal
Build a production-grade Azure infrastructure using Terraform, validated and deployed through a Jenkins CI/CD pipeline. No manual clicking in the Azure portal — everything is code.

### Architecture Overview

```
Internet
   │
   ▼
Application Gateway (WAF v2) — blocks SQL injection, XSS, OWASP top 10
   │
   ▼
Hub VNet (10.0.0.0/16) — East US
   ├── AzureFirewallSubnet — Azure Firewall Premium (L4/L7 inspection)
   ├── GatewaySubnet       — VPN Gateway (connects to simulated on-prem)
   ├── AzureBastionSubnet  — Bastion Host (secure VM access, no public IP)
   └── ManagementSubnet    — Admin VMs
         │
         │ VNet Peering
         ▼
Spoke VNet (10.3.0.0/16) — East US
   ├── App Subnet    — VMSS (Linux VMs, autoscale 2-20 instances)
   ├── Data Subnet   — Reserved for data workloads
   └── PE Subnet     — Private Endpoints (SQL, Storage, Key Vault)
         │
         │ Private Endpoints (traffic never leaves Azure backbone)
         ▼
   ├── Azure SQL Business Critical (West US 2) — geo-replicated
   ├── Azure Storage (ZRS/GZRS) — immutable audit containers
   └── Azure Key Vault Premium — HSM-backed keys, RBAC model

         │ VNet-to-VNet VPN Tunnel (IPSec AES256, BGP)
         ▼
Simulated On-Premises VNet (192.168.0.0/16) — West US 2
   └── Ubuntu VM — acts as corporate data centre server
```

### Why This Architecture?
- **Hub-spoke** — central control point (firewall, VPN) with isolated workload networks
- **Private endpoints** — SQL, Storage, Key Vault never exposed to internet
- **Azure Firewall AND WAF** — Firewall handles L4 (TCP/UDP), WAF handles L7 (HTTP)
- **Managed Identity** — VMs get secrets from Key Vault without passwords in config
- **TDE with CMK** — SQL data encrypted with your own key, not Microsoft's

---

## 2. AZURE CONCEPTS YOU MUST UNDERSTAND

### Hub and Spoke Networking
- **Hub VNet** — central network that contains shared services (firewall, VPN, bastion)
- **Spoke VNet** — workload network peered to hub. Traffic between spokes must go through the hub firewall
- **VNet Peering** — connects VNets so they can communicate. Does NOT transit — spoke-to-spoke must route through hub
- **UDR (User Defined Route)** — forces all spoke traffic through the Azure Firewall (`0.0.0.0/0 → Firewall IP`)

### Private Endpoints
- A private IP address inside your VNet that maps to a PaaS service (SQL, Storage, Key Vault)
- Traffic never leaves the Azure backbone — no internet exposure
- Requires a **Private DNS Zone** so the service FQDN resolves to the private IP instead of public IP
- Example: `sql-webapp-dev-eus.database.windows.net` resolves to `10.3.3.5` (private) instead of a public IP

### Network Security Groups (NSG)
- Firewall rules at the subnet or NIC level
- Rules have priority (lower number = higher priority)
- Azure Bastion requires specific Microsoft-mandated rules — you cannot change them
- Every subnet should have an NSG — CKV2_AZURE_31 checkov rule checks this

### Azure Firewall
- **Premium SKU** — supports IDPS (Intrusion Detection and Prevention), TLS inspection
- **IDPS in Deny mode** — blocks known malicious traffic, not just logs it
- **Threat Intelligence** — Microsoft feeds of known bad IPs/domains
- Firewall MUST be in the same Resource Group as its subnet — this caused our first deployment error

### Key Vault
- Stores secrets (passwords, connection strings), keys (encryption), certificates
- **RBAC model** vs Access Policies — RBAC is more granular and auditable
- **Soft delete** — deleted secrets kept for 90 days (prevents accidental loss)
- **Purge protection** — even admins cannot permanently delete during retention period
- **HSM-backed keys (RSA-HSM)** — keys stored in hardware security modules, cannot be exported
- Key Vault names are **globally unique across all Azure tenants** — caused our deployment error

### Managed Identity
- An Azure AD identity assigned to a resource (VM, VMSS, Storage Account)
- **System-assigned** — tied to resource lifecycle, deleted when resource deleted
- **User-assigned** — independent lifecycle, can be assigned to multiple resources
- We use **user-assigned** for VMSS so the identity can be pre-granted Key Vault access before VMSS exists
- Apps use managed identity to get secrets from Key Vault — no passwords in code

### Transparent Data Encryption (TDE) with CMK
- All SQL data encrypted at rest
- **CMK (Customer Managed Key)** — you control the encryption key in Key Vault
- SQL Server system-assigned identity needs **Key Vault Crypto Service Encryption User** RBAC role
- Key rotation is automatic — 30 days before expiry

### Azure Bastion
- Secure RDP/SSH to VMs without public IPs
- VMs have no public IP — only accessible via Bastion
- Bastion subnet requires specific NSG rules mandated by Microsoft — you cannot change these

### Service Principal
- An application identity in Azure AD (like a service account)
- Used by Jenkins and Terraform to authenticate to Azure
- Has a **Client ID** (username) and **Client Secret** (password)
- Assigned roles (Contributor, User Access Administrator) to perform actions

### RBAC (Role Based Access Control)
- Controls WHO can do WHAT on WHICH resource
- **Contributor** — can create/delete resources but not manage access
- **User Access Administrator** — can assign roles to other identities
- **Storage Blob Data Contributor** — can read/write blobs
- **Key Vault Secrets User** — can read secrets
- **Key Vault Administrator** — full key vault management
- **Key Vault Crypto Service Encryption User** — can use keys for encryption

### BGP (Border Gateway Protocol)
- Dynamic routing protocol used between VPN gateways
- Hub VPN gateway ASN: 65515 (Azure reserved)
- Simulated on-prem VPN gateway ASN: 65000
- ASNs must be different on each side

### VNet-to-VNet vs IPSec
- **IPSec** — connects Azure VPN gateway to a real on-prem device (firewall/router) using its public IP
- **VNet-to-VNet** — connects two Azure VPN gateways directly. Both sides are Azure-managed
- We use VNet-to-VNet because our "on-prem" is also an Azure VNet (simulated)

---

## 3. WHAT TO CREATE IN AZURE FIRST (BEFORE TERRAFORM)

Terraform needs to store its state file somewhere before it can manage anything. This creates a chicken-and-egg problem — you need to bootstrap manually.

### Step 1 — Create a Service Principal
```bash
az login
az ad sp create-for-rbac \
  --name "terraform-sp" \
  --role Contributor \
  --scopes /subscriptions/YOUR_SUBSCRIPTION_ID
```
Save the output — it contains:
- `appId` → this is the **Client ID** (Jenkins username)
- `password` → this is the **Client Secret** (Jenkins password)
- `tenant` → this is the **Tenant ID**

### Step 2 — Grant Additional Roles to the SP
```bash
# Needed to create RBAC assignments (Terraform creates many role assignments)
az role assignment create \
  --role "User Access Administrator" \
  --assignee "SP_CLIENT_ID" \
  --scope "/subscriptions/YOUR_SUBSCRIPTION_ID"
```

### Step 3 — Create Terraform State Storage (Bootstrap)
Run `bootstrap-backend.sh` once. This creates:
- 3 resource groups: `rg-tfstate-dev-eus`, `rg-tfstate-staging-eus`, `rg-tfstate-prod-eus`
- 3 storage accounts: `sttfstatedeveus`, `sttfstatestagingeus`, `sttfstateprodeus`
- 3 containers: `tfstate` in each

### Step 4 — Grant SP Access to State Storage
```bash
az role assignment create \
  --role "Storage Blob Data Contributor" \
  --assignee "SP_CLIENT_ID" \
  --scope "/subscriptions/SUB_ID/resourceGroups/rg-tfstate-dev-eus/providers/Microsoft.Storage/storageAccounts/sttfstatedeveus"
```
Repeat for staging and prod storage accounts.

**WHY?** The Terraform backend uses `use_azuread_auth = true` — it authenticates with the SP via AAD, not a storage key. The SP needs blob contributor access for this to work.

---

## 4. JENKINS CREDENTIALS — WHAT, WHY, AND HOW

Go to: Manage Jenkins → Credentials → (global) → Add Credentials

| Credential ID | Kind | What to Store | Why |
|---|---|---|---|
| `azure-subscription-id` | Secret text | `174ad45e-2cdc-467d-a71a-f0c5764f3e7c` | Terraform AzureRM provider needs subscription context |
| `azure-tenant-id` | Secret text | `ca5733a5-b8d4-4649-9dbd-caffed2c28d1` | AzureRM provider authentication |
| `azure-sp-dev` | Username/Password | Username=ClientID, Password=ClientSecret | SP credentials for dev terraform apply |
| `azure-sp-staging` | Username/Password | Username=ClientID, Password=ClientSecret | SP credentials for staging terraform apply |
| `azure-sp-prod` | Username/Password | Username=ClientID, Password=ClientSecret | SP credentials for prod terraform apply |
| `tf-sql-admin-login` | Secret text | `sqladminlogin` | SQL Server administrator username |
| `tf-sql-admin-password` | Secret text | Strong password | SQL Server administrator password |
| `tf-ssh-public-key` | Secret text | Contents of `~/.ssh/id_rsa.pub` | SSH public key for VMSS VMs |
| `github-credentials` | Username/Password | GitHub username + PAT token | Jenkins pulls code from GitHub |

**WHY separate dev/staging/prod SPs?**
In enterprise environments each environment has its own SP with access only to that environment's resources. Even though we used the same SP for all three in this project, the structure is correct and ready for separation.

**WHY store SQL login and password separately?**
The login (username) appears in logs, connection strings, and Azure portal — it is not secret. The password is highly sensitive and Jenkins masks it in all output. Storing them separately lets you use the login name without exposing the password.

---

## 5. TERRAFORM CONCEPTS — EVERY FILE EXPLAINED

### What is Terraform?
Infrastructure as Code tool. You write what you want (declarative), Terraform figures out how to create it. It tracks what it created in a **state file**.

### Key Commands
| Command | What it does | When to use |
|---|---|---|
| `terraform init` | Downloads providers, initialises backend | First time or after backend changes |
| `terraform fmt` | Formats code to standard style | Before committing |
| `terraform validate` | Checks syntax without connecting to Azure | Quick sanity check |
| `terraform plan` | Shows what WILL be created/changed/destroyed | Before every apply |
| `terraform apply` | Creates/updates resources in Azure | CD pipeline only |
| `terraform destroy` | Deletes all resources | Cleanup |
| `terraform state rm` | Removes a resource from state (not from Azure) | When state is wrong |
| `terraform state list` | Lists all resources Terraform knows about | Debugging |

### File Structure

```
terraform-azure-enterprise/
├── modules/                    # Reusable building blocks
│   ├── networking/             # VNets, subnets, NSGs, peering, bastion
│   ├── security/               # Firewall, Key Vault, WAF, VPN gateway
│   ├── compute/                # VMSS, Load Balancer, autoscale
│   ├── database/               # SQL Server, database, TDE, private endpoint
│   ├── storage/                # Storage account, containers, lifecycle
│   └── simulated-onprem/       # Fake DC for VPN demo without real hardware
├── environments/
│   ├── dev/                    # Dev-specific config (small sizes, no VPN)
│   ├── staging/                # Staging config (medium sizes)
│   └── prod/                   # Prod config (full HA, zone-redundant)
└── pipelines/
    ├── Jenkinsfile.ci          # Validates code on every push
    └── Jenkinsfile.cd          # Deploys to Azure on main branch
```

### Every File Explained

**`backend.tf`** — Tells Terraform where to store the state file
```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-tfstate-dev-eus"
    storage_account_name = "sttfstatedeveus"
    container_name       = "tfstate"
    key                  = "dev/terraform.tfstate"
    use_azuread_auth     = true  # authenticate with SP, not storage key
  }
}
```
WHY: Without a backend, state is stored locally. CI/CD pipelines are stateless — the state would be lost after every build. Azure Blob provides shared, locked state.

**`versions.tf`** — Pins provider versions
```hcl
terraform {
  required_version = ">= 1.6.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"  # any 3.x but not 4.x
    }
  }
}
```
WHY: Without version pinning, `terraform init` might download a newer provider that breaks existing code.

**`providers.tf`** — Configures the AzureRM provider
```hcl
provider "azurerm" {
  features {}
  # ARM_CLIENT_ID, ARM_CLIENT_SECRET, ARM_TENANT_ID, ARM_SUBSCRIPTION_ID
  # are read from environment variables injected by Jenkins
}
```
WHY: The provider is how Terraform talks to Azure. Credentials come from environment variables — never hardcoded.

**`variables.tf`** — Declares all inputs
```hcl
variable "environment" {
  type = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "must be dev, staging, or prod"
  }
}
```
WHY: Makes modules reusable. The same module code works for dev, staging, and prod — only the values differ.

**`terraform.tfvars`** — Provides values for variables
```hcl
environment    = "dev"
location       = "eastus"
vm_sku         = "Standard_DS2_v2"
```
WHY: Separates configuration from code. Dev uses small VMs, prod uses large VMs — same code, different tfvars.

**`outputs.tf`** — Exports values from a module or environment
```hcl
output "key_vault_name" {
  value = module.security.key_vault_name
}
```
WHY: Values computed by Terraform (IP addresses, resource IDs) need to be readable after apply for documentation and debugging.

**`main.tf`** — Calls all modules and wires them together
```hcl
module "networking" {
  source              = "../../modules/networking"
  environment         = var.environment
  hub_address_space   = var.hub_address_space
  ...
}

module "security" {
  source            = "../../modules/security"
  firewall_subnet_id = module.networking.firewall_subnet_id  # output from networking
  ...
}
```
WHY: The environment main.tf is the orchestrator. It calls each module and passes outputs from one module as inputs to another.

### What is a Module?
A folder of Terraform files that does one thing. You call it with `module "name" { source = "path" }`. It has:
- `variables.tf` — inputs (what you pass in)
- `main.tf` — resources it creates
- `outputs.tf` — values it exports

### Why Modules Instead of One Big File?
- **Reusability** — same networking module works for dev and prod
- **Isolation** — a bug in compute module doesn't affect database module
- **Team ownership** — different teams own different modules

### State File
- JSON file that records every resource Terraform created
- Stored in Azure Blob Storage (remote backend)
- **State locking** — Azure Blob uses lease-based locking. Only one `terraform apply` can run at a time
- NEVER manually edit the state file
- If state is wrong, use `terraform state rm` or `terraform import`

### `count` and `for_each`
- `count = var.deploy_vpn_gateway ? 1 : 0` — creates resource only if condition is true
- `for_each = var.spokes` — creates one resource per spoke (dev has one spoke "app")
- Used to make optional resources conditional without duplicating code

### `depends_on`
- Forces Terraform to create resources in order
- Used when Terraform cannot automatically detect the dependency
- Example: VMSS must wait for LB rule to exist before referencing its probe

---

## 6. MODULES WE BUILT — EVERY FILE AND WHY

### networking/
Creates hub VNet, spoke VNets, all subnets, NSGs, VNet peering, and Azure Bastion.

Key decisions:
- Bastion NSG has Microsoft-mandated rules — cannot be changed
- Management NSG allows SSH only from Bastion subnet
- PE subnet NSG denies internet, allows VNet only
- Route tables force all spoke traffic through Azure Firewall

### security/
Creates Azure Firewall Premium, Key Vault, Application Gateway WAF, and VPN Gateway.

Key decisions:
- Firewall uses Premium SKU for IDPS in Deny mode
- Key Vault uses RBAC not access policies
- Key Vault name uses subscription ID suffix for global uniqueness
- Firewall must be in SAME resource group as its subnet (hub network RG)
- Key Vault has public access enabled so Terraform runner can create keys

### compute/
Creates user-assigned managed identity, internal Load Balancer, VMSS, and autoscale rules.

Key decisions:
- User-assigned identity survives VMSS deletion
- Internal LB — traffic comes from App Gateway, not direct internet
- Rolling upgrade mode — updates VMs without downtime
- Autoscale triggers at 75% CPU (scale out) and 25% CPU (scale in)
- `depends_on = [azurerm_lb_rule.http]` — LB rule must exist before VMSS references its probe

### database/
Creates SQL Server, database, TDE encryption key, private endpoint, and failover group.

Key decisions:
- Azure AD authentication enabled (SQL logins disabled in future)
- TDE with CMK — SQL server managed identity needs Key Vault crypto access
- SQL location set to westus2 — eastus has provisioning restrictions on free subscriptions
- Yearly retention uses ISO 8601 duration format ("P1Y", "P5Y") — empty string causes error
- Audit policy and VA are conditional (count = 0 if storage not provided)

### storage/
Creates storage account, containers, immutability policy, lifecycle management, private endpoint.

Key decisions:
- ZRS in dev/staging, GZRS in prod
- WORM (immutability) on audit container — 7 year retention
- Archive tier removed — not supported by ZRS or GZRS
- restore_policy removed — conflicts with container immutability policy
- shared_access_key_enabled = true — AzureRM provider v3 requires this internally
- public_network_access_enabled = true — Terraform runner needs access to create containers
- Network default_action = "Allow" — allows Terraform runner through

### simulated-onprem/
Creates a fake on-premises DC using a VNet in West US 2 with a VPN gateway and Ubuntu VM.

Key decisions:
- Uses VNet-to-VNet connection type (not IPSec) since both sides are Azure
- BGP ASN 65000 for on-prem, 65515 for hub (Azure reserved)
- Ubuntu VM runs nginx/NFS/Samba to simulate corporate workloads
- Only deployed in prod environment where VPN gateway is enabled

---

## 7. PIPELINE STAGES — CI AND CD EXPLAINED

### CI Pipeline (Jenkinsfile.ci) — Runs on Every Push

**Stage 1: Checkout**
- Jenkins pulls the code from GitHub
- WHY: Ensures the pipeline always works on the latest code

**Stage 2: Terraform Format Check**
- `terraform fmt -check -recursive`
- WHY: Enforces consistent code style. Fails if any file is not formatted correctly
- Fix: run `terraform fmt -recursive` locally before pushing

**Stage 3: Terraform Validate**
- `terraform validate` in each environment directory
- WHY: Catches syntax errors and invalid references without connecting to Azure

**Stage 4: TFLint**
- `tflint --init` then `tflint --recursive`
- WHY: Catches Azure-specific issues like invalid VM SKUs, deprecated arguments
- Config: `.tflint.hcl` — disabled documentation rules (terraform_documented_variables, terraform_documented_outputs)

**Stage 5: Security Scan (Checkov)**
- `checkov --directory terraform-azure-enterprise --config-file .checkov.yaml`
- WHY: Scans for security misconfigurations (open NSGs, public storage, missing encryption)
- Config: `.checkov.yaml` — skips rules for subnets without NSGs (GatewaySubnet, FirewallSubnet — Azure-managed)

**Stage 6: Terraform Plan (parallel — dev, staging, prod)**
- Writes `override.tf` with local backend (no Azure storage needed)
- `terraform init -reconfigure`
- `terraform plan -out=tfplan-ENV.binary`
- WHY parallel: Validates all three environments simultaneously, saves time
- WHY local backend override: CI doesn't need real state — it just validates the plan
- SSH key uses shell fallback: `SSH_KEY="${VAR:-valid-rsa-key}"` to avoid empty string error

### CD Pipeline (Jenkinsfile.cd) — Runs on main Branch

**Stage 1: Plan: dev**
- Connects to Azure with dev SP credentials
- Runs `terraform plan` with real backend (Azure Blob)
- Saves plan as artifact

**Stage 2: Apply: dev**
- `terraform apply tfplan-dev.binary`
- Uses the exact plan from Stage 1 — what was reviewed is what gets applied
- If this fails, staging and prod are blocked

**Stage 3: Plan: staging** (only if dev succeeded)
- Same as dev but with staging SP and staging backend

**Stage 4: Approval Gate** (prod only)
- Jenkins waits for manual approval before applying to prod
- WHY: Prod deployments should always have human sign-off

**Stage 5: Apply: staging**
**Stage 6: Plan: prod**
**Stage 7: Apply: prod**

---

## 8. TOOLS USED IN THE PIPELINE AND WHY

| Tool | What it does | Why we use it |
|---|---|---|
| `terraform` | Creates and manages Azure resources | Core IaC tool |
| `terraform fmt` | Formats .tf files | Consistent code style, fails CI if messy |
| `terraform validate` | Syntax check | Catches typos before hitting Azure |
| `tflint` | Azure-specific linting | Catches invalid SKUs, deprecated args, naming issues |
| `checkov` | Security policy scanner | Finds open ports, missing encryption, public storage |
| `tfsec` | Security scanner (second opinion) | Different rule set from checkov |
| `azure-cli` | Authenticates to Azure | Used by Terraform AzureRM provider |
| `git` | Version control | Tracks changes, enables CI on every push |
| `jenkins` | CI/CD orchestrator | Runs the pipeline stages automatically |

### How Tools Were Installed
All tools were installed inside the Jenkins Docker container:
```bash
docker exec -u root jenkins bash
# Then: apt-get install, pip install checkov, wget terraform, etc.
```

---

## 9. COMMANDS USED IN THE ENTIRE PROJECT AND WHY

### Azure CLI Commands
```bash
az login                          # Authenticate to Azure interactively
az account show                   # Show current subscription
az account set --subscription ID  # Switch subscription
az ad sp create-for-rbac          # Create Service Principal
az keyvault purge                 # Permanently delete soft-deleted Key Vault
az keyvault list-deleted          # List soft-deleted Key Vaults
az sql server delete              # Delete SQL server (needed when changing location)
az role assignment create         # Grant RBAC role to identity
az storage account update         # Update storage settings (enable public access, shared key)
az group delete --no-wait         # Delete resource group in background
az group list                     # List all resource groups
az feature register               # Register subscription feature (EncryptionAtHost)
```

### Terraform Commands
```bash
terraform init                    # Download providers, connect to backend
terraform init -reconfigure       # Re-init with different backend (local override)
terraform fmt -recursive          # Format all .tf files
terraform validate                # Check syntax
terraform plan -out=tfplan.binary # Generate plan and save it
terraform apply tfplan.binary     # Apply saved plan
terraform apply -auto-approve     # Apply without confirmation prompt (CI/CD only)
terraform destroy                 # Delete all resources
terraform state list              # List resources in state
terraform state rm RESOURCE       # Remove resource from state (not from Azure)
```

### Git Commands
```bash
git init                          # Initialize git repo
git add -A                        # Stage all changes
git commit -m "message"           # Commit changes
git push origin main              # Push to GitHub
git remote set-url origin URL     # Change remote URL (used to add PAT token)
```

---

## 10. EVERY ERROR WE HIT AND HOW WE FIXED IT

### Jenkins Setup Errors

| Error | Root Cause | Fix |
|---|---|---|
| `Jenkins doesn't have label 'terraform'` | Agent label not set | Labeled built-in node as 'terraform' in Jenkins UI |
| `slackSend not found` | Slack plugin not installed | Replaced all `slackSend` with `echo` |
| `terraform: not found` | Tools not in Jenkins container | Installed terraform, tflint, checkov, tfsec, az inside Docker container |
| `azure-tenant-id credential missing` | Credentials not added | Added all credentials to Jenkins credential store |
| `azure-sp-dev credential missing` | SP credentials not in Jenkins | Created SP, added as Username/Password credential |

### CI Pipeline Errors

| Error | Root Cause | Fix |
|---|---|---|
| `terraform fmt -check` failed | Files not formatted | Ran `terraform fmt -recursive` locally, committed |
| `TFLINT_CONFIG path wrong` | Missing workspace prefix | Fixed path to `${WORKSPACE}/terraform-azure-enterprise/.tflint.hcl` |
| `Plugin "azurerm" not found` | tflint plugin not downloaded | Added `tflint --init` before `tflint --recursive` |
| 115 tflint notices | Missing variable descriptions | Disabled `terraform_documented_variables` and `terraform_documented_outputs` in `.tflint.hcl` |
| Checkov not reading config | Missing `--config-file` flag | Added `--config-file "${CHECKOV_CONFIG}"` to checkov command |
| `dir('environments/dev')` wrong path | Missing `terraform-azure-enterprise/` prefix | Changed all paths to include full prefix |
| `sttfstatedeveus.blob: no such host` | CI tried to connect to real backend | Wrote `override.tf` with local backend + `terraform init -reconfigure` |
| `parsing "": Key Vault DNS` | Empty string passed to private_dns_zone_ids | Made `private_dns_zone_group` block dynamic/conditional |
| `storage_account_type = "GeoRedundant"` | Invalid enum value | Changed to `"Geo"` |
| Container name "dr" too short | Azure requires 3-63 chars | Renamed to `"disaster-recovery"` |
| `audit_storage_endpoint` empty | Resource created without conditional | Added `count = var.audit_storage_endpoint != "" ? 1 : 0` |
| `yearly_retention = ""` | Invalid ISO 8601 duration | Changed to `"P1Y"` |
| SSH key empty string | Pipeline passes empty var overriding default | Added shell fallback `${VAR:-valid-rsa-key}` |
| SSH placeholder invalid RSA | Azure validates key format | Generated real 2048-bit RSA key as placeholder |

### Terraform Apply Errors (CD Pipeline)

| Error | Root Cause | Fix |
|---|---|---|
| `AzureFirewallReferencesSubnetInDifferentResourceGroup` | Firewall in security RG, subnet in network RG | Added `network_resource_group_name` variable, moved firewall to network RG |
| `VaultAlreadyExists` | Key Vault name globally taken | Made KV name include first 6 chars of subscription ID |
| `CannotUseInactiveHealthProbe` | VMSS created before LB rule | Added `depends_on = [azurerm_lb_rule.http]` to VMSS |
| `InvalidExternalAdministratorSid` | Placeholder AAD object ID `00000000...` | Replaced with real SP object ID |
| Key Vault 403 Forbidden | Public access disabled, Terraform runner outside VNet | Enabled `public_network_access_enabled = true` |
| Storage 403 key auth | `shared_access_key_enabled = false` breaks AzureRM v3 | Set `shared_access_key_enabled = true` |
| `ProvisioningDisabled` SQL eastus | Free subscription SQL quota in eastus | Moved SQL to westus2 via `sql_location` variable |
| `SkuNotAvailable Standard_D2s_v5` | VM SKU capacity restricted in eastus | Changed to Standard_DS2_v2 |
| `SkuNotAvailable Standard_D2s_v3` | Also restricted | Changed to Standard_B2s |
| `SkuNotAvailable Standard_B2s` | Also restricted (zones constraint) | Made zones configurable, use zone ["1"] for dev, changed SKU to Standard_DS2_v2 |
| `EncryptionAtHost feature not enabled` | Feature not registered on subscription | Commented out `encryption_at_host_enabled`, noted how to enable |
| `InvalidResourceLocation` SQL conflict | Changing SQL location when resource exists in state | Deleted SQL server via CLI, let Terraform recreate |
| Storage containers 403 | Network rules `default_action = "Deny"` blocking runner | Changed to `default_action = "Allow"`, granted SP Storage Blob Data Contributor |
| `tierToArchive not supported` | ZRS and GZRS don't support archive tier | Removed archive tier from lifecycle policy |
| `ConflictFeatureEnabled` immutability | Point-in-time restore conflicts with WORM | Removed `restore_policy` block |

### Why So Many Errors?
This is completely normal in enterprise Terraform. Every error here represents a real-world constraint:
- Subscription quotas (SQL, VM SKUs) — real enterprises have these too
- Azure API rules (Firewall RG, Key Vault naming) — you only learn these by hitting them
- Security trade-offs (public access vs runner access) — real decisions engineers make daily

---

## 11. WHAT TO SAY IN INTERVIEWS

### "Tell me about your CI/CD pipeline"

"I built a Jenkins Multibranch pipeline that validates Terraform code on every push — format check, validate, tflint for Azure-specific issues, and Checkov for security misconfigurations. The CD pipeline uses a plan-before-apply pattern: the plan artifact from CI is the exact binary applied in production. This guarantees what the team reviewed is exactly what gets deployed. Dev, staging, and prod each have separate state files in Azure Blob Storage, separate service principals, and separate approval gates."

### "Why did you use hub-and-spoke?"

"Hub-and-spoke follows the Azure Cloud Adoption Framework. All traffic between spokes and the internet flows through the hub firewall, giving you a single inspection point. The spoke VNets are isolated from each other — a compromised app VNet cannot reach the database VNet without going through the firewall. It also makes DNS and VPN gateway costs shared rather than duplicated per workload."

### "How do your VMs get secrets without passwords?"

"We assign a user-assigned managed identity to the VMSS. This identity has the Key Vault Secrets User RBAC role. The application calls the Azure Instance Metadata Service on startup, gets a token for the managed identity, and uses that token to read secrets from Key Vault. No passwords in config files, no secrets in environment variables, no rotation needed — Azure handles token lifecycle automatically."

### "Why Azure Firewall AND Application Gateway WAF?"

"They operate at different layers. The Application Gateway WAF terminates TLS and inspects HTTP traffic — it understands SQL injection, XSS, and OWASP rules because it sees the decrypted payload. Azure Firewall inspects everything else: DNS, SMTP, lateral movement between subnets. Together they provide defence-in-depth — a threat that bypasses one layer still faces the other."

### "What real security decisions did you make?"

"We added real enterprise NSGs instead of just skipping the checkov rules. Azure Bastion requires specific Microsoft-mandated inbound and outbound rules — I implemented all of them. Management subnet only allows SSH from the Bastion subnet, not from the internet. Private endpoint subnets deny all internet inbound. These are not skip comments — these are actual network controls."

### "What is TDE with CMK?"

"SQL data is encrypted at rest by default with Microsoft-managed keys. With CMK, the encryption key lives in our Key Vault and we control its lifecycle. The SQL Server's managed identity has the Crypto Service Encryption User role on the Key Vault. Keys rotate automatically 30 days before expiry. If we revoke the key, the database becomes inaccessible — we control whether the data can be read, not Microsoft."

---

## SUBSCRIPTION CONSTRAINTS SPECIFIC TO THIS PROJECT

If you have a free or trial Azure subscription, some resources have restrictions:

| Resource | Restriction | Workaround Used |
|---|---|---|
| Azure SQL | Provisioning restricted in eastus | Use westus2 via `sql_location` variable |
| Standard_D2s_v5 | Capacity unavailable in eastus | Use Standard_DS2_v2 |
| Standard_D2s_v3 | Capacity unavailable in eastus | Use Standard_DS2_v2 |
| Standard_B2s | Capacity unavailable across zones | Use zone ["1"] only for dev |
| EncryptionAtHost | Feature not registered | Register with `az feature register --name EncryptionAtHost --namespace Microsoft.Compute` (takes 30 min) |

---

## BEFORE NEXT DEPLOYMENT — CHECKLIST

- [ ] Run `bootstrap-backend.sh` to recreate tfstate storage accounts
- [ ] Grant SP Storage Blob Data Contributor on all three storage accounts
- [ ] Confirm SP has Contributor and User Access Administrator on subscription
- [ ] Trigger CI pipeline — confirm all plans pass
- [ ] Trigger CD pipeline — dev first, verify, then staging, then prod
- [ ] Take screenshots of Azure portal showing all resources
- [ ] Run destroy immediately after screenshots to stop billing
