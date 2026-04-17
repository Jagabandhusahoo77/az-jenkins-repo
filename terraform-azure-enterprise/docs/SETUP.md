# Setup Guide

## Prerequisites

| Tool | Version | Install |
|---|---|---|
| Terraform | >= 1.6 | `brew install terraform` or [tfenv](https://github.com/tfutils/tfenv) |
| Azure CLI | >= 2.55 | `brew install azure-cli` |
| TFLint | >= 0.50 | `brew install tflint` |
| Checkov | >= 3.0 | `pip install checkov` |
| tfsec | >= 1.28 | `brew install tfsec` |
| Go | >= 1.21 | Required for Terratest only |

## Step 1: Azure Authentication

```bash
# Interactive login for local development
az login

# Verify correct subscription is selected
az account show
az account set --subscription "<subscription-id>"
```

## Step 2: Bootstrap Remote State Backend

Run **once per environment** before the first `terraform init`:

```bash
# Create backend for dev
chmod +x scripts/bootstrap-backend.sh
./scripts/bootstrap-backend.sh dev eastus

# Create backend for staging
./scripts/bootstrap-backend.sh staging eastus

# Create backend for prod
./scripts/bootstrap-backend.sh prod eastus
```

## Step 3: Create Service Principals (CI/CD)

```bash
chmod +x scripts/create-service-principal.sh

# Create one SP per environment — minimum privilege per env
./scripts/create-service-principal.sh dev     <dev-subscription-id>
./scripts/create-service-principal.sh staging <staging-subscription-id>
./scripts/create-service-principal.sh prod    <prod-subscription-id>
```

Store the output credentials in **Jenkins Credentials Store**:
- Credential type: `Username with password`
- ID: `azure-sp-dev` / `azure-sp-staging` / `azure-sp-prod`
- Username: Client ID
- Password: Client Secret

## Step 4: Configure tfvars

Edit `environments/<env>/terraform.tfvars` with your actual values:

```hcl
aad_admin_object_id = "<your-ad-group-object-id>"
security_alert_emails = ["your-team@company.com"]
```

## Step 5: Set Sensitive Variables

Sensitive values are passed as environment variables, not in tfvars:

```bash
export TF_VAR_sql_admin_login="sqladmin"
export TF_VAR_sql_admin_password="<strong-password>"
export TF_VAR_ssh_public_key="$(cat ~/.ssh/id_rsa.pub)"
```

For Jenkins, these are stored as **Secret Text** credentials:
- `tf-sql-admin-login`
- `tf-sql-admin-password`
- `tf-ssh-public-key`

## Step 6: First Deployment

```bash
cd environments/dev

# Initialise with backend
terraform init

# Install TFLint plugins
tflint --init

# Validate
terraform validate

# Plan (review carefully)
terraform plan -out=tfplan.binary

# Apply
terraform apply tfplan.binary
```

> **Note on first apply**: The `firewall_private_ip` output will be empty on bootstrap
> because the firewall is created in the same apply. The UDRs use this IP. Run
> `terraform apply` a **second time** after the first to wire up the routes correctly.
> This is a known limitation of the chicken-and-egg Firewall IP dependency.

## Step 7: Jenkins Setup

### Install Required Jenkins Plugins
- Azure Credentials Plugin
- Pipeline
- Multibranch Pipeline
- Blue Ocean (optional, better UI)
- Slack Notification Plugin

### Configure Multibranch Pipeline (CI)
1. New Item → Multibranch Pipeline
2. Branch Sources → GitHub → your org/repo
3. Build Configuration → by Jenkinsfile → `pipelines/Jenkinsfile.ci`
4. Scan Triggers → Periodically if not otherwise run: `1 hour`

### Configure Deployment Pipeline (CD)
1. New Item → Pipeline
2. Pipeline Definition → Pipeline script from SCM
3. SCM: GitHub → your repo → branch `main`
4. Script Path: `pipelines/Jenkinsfile.cd`
5. Build Triggers: **Only** allow trigger from CI pipeline (no cron)

### Configure Jenkins Agent
The pipeline requires an agent with label `terraform`. Create a node/agent with:
- Java installed
- `terraform`, `tflint`, `checkov`, `tfsec`, `az` in PATH
- Sufficient disk (2GB+) for Terraform providers cache

## Troubleshooting

**`Error: Backend configuration changed`**
```bash
terraform init -reconfigure
```

**`Error: A resource with the ID already exists`**
The resource was created outside Terraform. Import it:
```bash
terraform import azurerm_resource_group.compute /subscriptions/.../resourceGroups/rg-compute-dev-eus
```

**`Error: insufficient privileges to complete the operation`**
The Service Principal needs `User Access Administrator` for RBAC assignments.
Re-run `create-service-principal.sh` or add the role manually.

**Key Vault purge protection prevents destroy**
```bash
# Recover the soft-deleted vault first
az keyvault recover --name kv-webapp-dev-eus
# Then destroy
terraform destroy
```
