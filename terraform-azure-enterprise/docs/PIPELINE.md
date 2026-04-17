# CI/CD Pipeline Guide

## Overview

```
Developer pushes code
        │
        ▼
┌─────────────────────────────────────────────────────────────────┐
│  CI PIPELINE (Multibranch — runs on every branch)               │
│                                                                  │
│  ┌────────┐  ┌──────────────────────────────────┐  ┌─────────┐ │
│  │Checkout│→ │   Parallel Validation             │→ │Security │ │
│  └────────┘  │ validate:dev  validate:staging    │  │ Scan    │ │
│              │ validate:prod  TFLint              │  │Checkov  │ │
│              └──────────────────────────────────-┘  │tfsec    │ │
│                                                      └────┬────┘ │
│                                                           ▼      │
│              ┌──────────────────────────────────┐              │ │
│              │   Parallel Terraform Plan         │              │ │
│              │ plan:dev  plan:staging  plan:prod │              │ │
│              └──────────────────────────────────┘              │ │
│                          │                                       │
│              [Optional] Terratest (develop branch only)         │
└──────────────────────────┼──────────────────────────────────────┘
                           │ Merge to main triggers
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│  CD PIPELINE (Centralised — runs only on main)                  │
│                                                                  │
│  ┌──────┐      ┌─────────────┐      ┌──────────────────────┐  │
│  │ dev  │─auto→│   staging   │─auto→│ APPROVAL GATE (4hr)  │  │
│  │apply │      │    apply    │      │ review plan artifact  │  │
│  └──────┘      └─────────────┘      │ release-managers group│  │
│                                      └──────────┬───────────┘  │
│                                                  │ Approved      │
│                                                  ▼               │
│                                          ┌──────────────┐       │
│                                          │  prod apply  │       │
│                                          └──────────────┘       │
└─────────────────────────────────────────────────────────────────┘
```

## CI Pipeline Stages

### Stage 1: Checkout
Checks out code, prints build metadata (branch, commit, tool versions).

### Stage 2: Terraform Format
```bash
terraform fmt -check -recursive -diff .
```
Exits non-zero if any file is not formatted. Developers must run `terraform fmt -recursive` locally. This is a hard gate — broken formatting blocks all subsequent stages.

### Stage 3: Validate & Lint (parallel)
- **validate:dev/staging/prod** — `terraform init -backend=false && terraform validate`  
  Checks syntax and internal consistency without touching Azure.
- **TFLint** — validates Azure-specific rules (invalid VM sizes, deprecated attributes, naming conventions).

### Stage 4: Security Scan (parallel)
- **Checkov** — CIS/NIST/PCI-DSS benchmark checks. LOW/MEDIUM are soft-fail; HIGH/CRITICAL block the build.
- **tfsec** — Secondary scan. CRITICAL findings block the build.

Skippable via `SKIP_SECURITY_SCAN` parameter — requires PR review and is logged.

### Stage 5: Terraform Plan (parallel)
Plans all three environments concurrently. Saves `.binary` plan files as artifacts. These same artifacts are used by the CD pipeline to guarantee that what was reviewed is what gets applied.

### Stage 6: Terratest (conditional)
Only runs on `develop` branch or when `RUN_TERRATEST=true`. Creates real Azure resources (~10 min), runs assertions, destroys. Not run on every feature commit to save cost.

## CD Pipeline Stages

### Validate Trigger
Blocks execution if not on `main` branch. Prevents accidental deploys from feature branches.

### Deploy: dev (automatic)
Runs `terraform init → plan → apply`. Failure blocks staging and prod.

### Deploy: staging (automatic)
Runs after successful dev. Failure blocks prod and sends Slack alert.

### Approval: prod (manual gate)
The approver receives a notification with:
- Link to plan artifact (review what will change)
- Commit SHA and build number
- 4-hour timeout (auto-aborts, does not fail — allowing retry)

Approvers must be in the `release-managers` Jenkins group.

### Deploy: prod (after approval)
Re-runs plan (catches any drift since CI plan), then applies. On failure: alerts oncall, does NOT auto-rollback (partial state must be assessed manually).

## Credential Architecture

```
Jenkins Credentials Store
├── azure-sp-dev          (Username/Password — ARM_CLIENT_ID/SECRET for dev)
├── azure-sp-staging      (Username/Password — for staging)
├── azure-sp-prod         (Username/Password — for prod)
├── azure-subscription-id (Secret Text — per environment in separate bindings)
├── azure-tenant-id       (Secret Text)
├── tf-sql-admin-login    (Secret Text → TF_VAR_sql_admin_login)
├── tf-sql-admin-password (Secret Text → TF_VAR_sql_admin_password)
└── tf-ssh-public-key     (Secret Text → TF_VAR_ssh_public_key)
```

Each environment's SP has minimum permissions scoped only to that environment's subscription. A compromised dev SP cannot affect prod.

## Branch Strategy

```
main          ──●──────────────●──────── (CD triggers on merge)
                ↑              ↑
develop       ──●──●──●───────●───────── (Terratest runs here)
                    ↑
feature/*         ──●──●──              (full CI, no Terratest)
```

## Environment Promotion

Code flows in one direction: `feature → develop → main → [dev auto] → [staging auto] → [prod gated]`

There is no "skip staging" mechanism by design. If staging needs to be bypassed for an emergency:
1. Create a hotfix branch from main
2. Get approval via standard PR process
3. The approval gate in CD still applies — there is no "emergency bypass" in the pipeline itself

## Rollback Strategy

Terraform does not have a built-in rollback command. Rollback strategies:

1. **Revert commit** (preferred): `git revert` the offending commit, push to main, let CD re-apply.
2. **State manipulation** (last resort): `terraform state rm` the problematic resource, then re-apply a previous config.
3. **For prod DB failures**: SQL failover group auto-promotes secondary after 60 min. Manual failback via Azure Portal or `az sql failover-group set-primary`.
