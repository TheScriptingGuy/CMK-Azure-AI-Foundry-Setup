# CMK-Azure-AI-Foundry-Setup

Terraform to provision a **public-facing Azure AI Foundry** account with
**Customer-Managed Keys** (CMK) in Key Vault, and a config-driven deployment
of an OpenAI model (default: **gpt-5.4**) via the AI Foundry account.

The Terraform `opencode_env` output emits a paste-ready shell snippet that
configures the Azure OpenAI SDK or any compatible client:

```bash
terraform output -raw opencode_env
# export AZURE_OPENAI_API_KEY=...
# export AZURE_OPENAI_ENDPOINT=https://<account>.cognitiveservices.azure.com/openai
# export AZURE_OPENAI_DEPLOYMENT=gpt-5-4
# export OPENAI_API_VERSION=2024-10-21
# export AZURE_FOUNDRY_PROJECT_ENDPOINT=https://<account>.cognitiveservices.azure.com/api/projects/default
```

## Known limitation: model deployments on CMK accounts

Azure blocks model deployments (HTTP 400, error `715-123420`) on
**CMK-encrypted AIServices accounts** in **swedencentral**. This affects all
models and both the ARM API and the Azure CLI. A support ticket has been filed.

As a result the `var.deployments` default is kept at `gpt-5.4` in the config,
but a `terraform apply` will fail at the model-deployment step until Microsoft
resolves the restriction. The rest of the stack (Key Vault, managed identity,
AI Foundry account, project, role assignments) deploys cleanly.

## What CMK does (and doesn't) buy you here

The CMK setup encrypts the **AIServices account's metadata** under a key
*you* hold in Key Vault. Inference traffic runs through Azure's shared
infrastructure — "data in your control" means key-control over the Foundry
resource, not end-to-end customer-isolated inference.

## Architecture

```
terraform/
├── bootstrap/  (one-time, local state)
│   └── RG + Storage Account + tfstate container
│
└── main config (remote state in the bootstrap account)
    ├── modules/identity          → User-assigned managed identity (for CMK)
    ├── modules/keyvault          → KV (purge-protected, RBAC) + RSA 4096 key
    │                                + role assignment: UAMI gets
    │                                  "Key Vault Crypto Service Encryption User"
    ├── modules/ai-foundry        → AIServices account (kind=AIServices, CMK)
    │                                + project (azapi)
    └── modules/model-deployment  → One deployment per entry in var.deployments
                                     (parent: the AI Foundry account)
```

The root module uses module-level `depends_on = [module.keyvault]` on
`module.ai_foundry` so the KV role assignment lands before the account tries
to wrap its data key.

## Usage

### Automated (recommended) — deploy scripts

```powershell
# Direct Terraform deploy (no Docker needed):
.\deploy\scripts\deploy.ps1 -Action apply

# Via GitHub Actions locally using act + Docker:
.\deploy\scripts\deploy-with-docker.ps1 -Action apply
```

Both scripts handle `az login`, bootstrap, backend wiring, and role
assignments automatically. Use `-SkipBootstrap` if the remote state storage
account already exists.

### Manual

```bash
az login
az account set --subscription <SUBSCRIPTION_ID>

# 1) One-time bootstrap (local state).
cd terraform/bootstrap
terraform init
terraform apply -var "subscription_id=<SUBSCRIPTION_ID>"

# 2) Main config.
cd ..
terraform init \
  -backend-config="resource_group_name=<RG>" \
  -backend-config="storage_account_name=<SA>" \
  -backend-config="container_name=tfstate"
terraform apply \
  -var "subscription_id=<SUB>" \
  -var "tenant_id=<TENANT>" \
  -var 'key_vault_admin_object_ids=["<YOUR_OBJECT_ID>"]'
```

## GitHub Actions (cloud or local via `act`)

Two manual workflows live in `.github/workflows/`:

- `bootstrap.yml` — runs the one-time bootstrap, emits the backend config.
- `deploy.yml` — `plan` / `apply` / `destroy` against the main config.

```bash
cp .secrets.example .secrets   # fill in ARM_CLIENT_ID / SECRET / TENANT_ID
act workflow_dispatch -W .github/workflows/bootstrap.yml \
  --secret-file .secrets --input subscription_id=<SUB>
```

## Choosing a different model

Models are listed in `var.model_catalog` (`terraform/variables.tf`). To deploy
a different model, override `var.deployments`:

```hcl
# terraform.tfvars
deployments = [
  { model_key = "gpt-4o", deployment_name = "gpt-4o", capacity = 1 },
]
```

The **first** entry's endpoint flows into `opencode_env`. Add more entries to
deploy multiple models simultaneously.

## Default region

`swedencentral` — set via `var.location` (default in `terraform/variables.tf`).

## Layout

```
deploy/
  scripts/
    deploy.ps1               Direct Terraform deploy (az CLI auth, no Docker)
    deploy-with-docker.ps1   GitHub Actions emulation via act + Docker

terraform/
  bootstrap/                 One-time TF for the remote state account
  modules/
    identity/                UAMI
    keyvault/                KV + RSA key + CMK role assignment
    ai-foundry/              AIServices account + project
    model-deployment/        Model deployment under the AI Foundry account
    role-assignments/        Reusable role assignment block
  versions.tf
  providers.tf
  backend.tf
  variables.tf               Inputs + model_catalog
  locals.tf                  Resource naming
  main.tf                    Composes modules
  outputs.tf                 Including opencode_env

.github/workflows/
  bootstrap.yml              Manual: provision remote state
  deploy.yml                 Manual: plan / apply / destroy

.secrets.example             Template for ARM_CLIENT_ID/SECRET/TENANT_ID
```

## Out of scope

Private endpoints, VNet integration, AI Search / Cosmos / compute clusters,
CI/CD, Azure Policy, monitoring, multi-region, multi-subscription.
