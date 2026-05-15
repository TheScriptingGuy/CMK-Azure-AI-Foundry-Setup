# CMK-Azure-AI-Foundry-Setup

Terraform to provision a **public-facing Azure AI Foundry** account with
**Customer-Managed Keys** (CMK) in Key Vault, and a config-driven deployment
of an Anthropic model (default: **Claude Opus 4.7**, fallback **Opus 4.6**) via
Azure AI Foundry's Models-as-a-Service catalog.

The Terraform `opencode_env` output emits a paste-ready shell snippet that
configures **[OpenCode](https://github.com/sst/opencode)** (or any Anthropic
SDK client) to talk to the deployed model:

```bash
terraform output -raw opencode_env
# export ANTHROPIC_API_KEY=...
# export ANTHROPIC_BASE_URL=https://<account>.services.ai.azure.com/anthropic
# export ANTHROPIC_MODEL=claude-opus-4-7
```

## What CMK does (and doesn't) buy you here

The CMK setup encrypts the **AIServices account's metadata** under a key
*you* hold in Key Vault. Inference traffic to Anthropic-hosted MaaS models is
governed by Microsoft's and Anthropic's MaaS terms — it does **not** run inside
your subscription. "Data in your control" in this repo means key-control over
the Foundry resource, not end-to-end customer-isolated inference.

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
    ├── modules/ai-foundry        → AIServices account (kind=AIServices) with
    │                                CMK wiring + project (azapi)
    └── modules/model-deployment  → One Anthropic MaaS deployment per entry in
                                     var.deployments
```

The root module uses module-level `depends_on = [module.keyvault]` on
`module.ai_foundry` so the KV role assignment lands before the account tries
to wrap with the key.

## Usage

```bash
az login
az account set --subscription <SUBSCRIPTION_ID>

# 1) One-time bootstrap: create the remote state account.
cd terraform/bootstrap
terraform init
terraform apply -var "subscription_id=<SUBSCRIPTION_ID>"

# Copy the printed backend block into ../backend.tf.

# 2) Main config.
cd ..
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars: set subscription_id, tenant_id, and at least one
# admin object ID in key_vault_admin_object_ids (your own user normally).

terraform init
terraform apply
```

When apply succeeds:

```bash
terraform output -raw opencode_env > .env.opencode
source .env.opencode
opencode    # or curl $ANTHROPIC_BASE_URL/v1/messages ...
```

## GitHub Actions (cloud or local via `act`)

Two manual workflows live in `.github/workflows/`:

- `bootstrap.yml` — runs the one-time bootstrap, emits the backend config.
- `deploy.yml` — `plan` / `apply` / `destroy` against the main config; backend
  wired via `-backend-config` flags so `backend.tf` stays untouched.

Both are designed to run identically in GitHub and locally with
[`act`](https://github.com/nektos/act). See
[`.github/workflows/README.md`](.github/workflows/README.md) for SP setup
and the exact `act` invocations.

```bash
cp .secrets.example .secrets   # fill in ARM_CLIENT_ID / SECRET / TENANT_ID
act workflow_dispatch -W .github/workflows/bootstrap.yml \
  --secret-file .secrets --input subscription_id=<SUB>
```

## Choosing a different model

Models are listed in `var.model_catalog` (see `variables.tf`). To deploy a
different model, edit `var.deployments` in `terraform.tfvars`:

```hcl
deployments = [
  { model_key = "claude-sonnet-4-6", deployment_name = "sonnet", capacity = 1 },
]
```

To deploy more than one, add more entries — the **first** entry's endpoint
flows into `opencode_env`.

If a model isn't in the catalog yet, add it to `var.model_catalog` (see the
`TODO(verify)` comments — the exact publisher/offer/sku strings come from the
Azure portal Model Catalog or `az rest` against
`Microsoft.CognitiveServices/locations/<region>/models`).

## Verification TODOs

The provider surface for AI Foundry (AIServices-account shape) and Anthropic
MaaS deployments is still evolving. Six items in the code are marked
`TODO(verify)`; resolve them on first `terraform plan`:

1. AzureRM version that ships a first-class `azurerm_ai_services_project` —
   prefer it over `azapi_resource` if available.
2. Latest `azapi` API version for `Microsoft.CognitiveServices/accounts/projects`
   and `.../deployments`.
3. Whether a separate `Microsoft.SaaS/resources` marketplace subscription is
   still needed for Anthropic offers (commented-out fallback exists in
   `modules/model-deployment/main.tf`).
4. Whether **Claude Opus 4.7** is live on Azure AI Foundry MaaS in your region.
   If not, swap the default in `terraform.tfvars` to `claude-opus-4-6`.
5. Endpoint URL shape returned by the deployment — the module assumes
   `<account>.services.ai.azure.com/anthropic`; verify after first apply.
6. Exact field names on the deployment body
   (`properties.model.{format,name,version}` vs publisher/offer/sku at top).

## Layout

```
terraform/
  bootstrap/              one-time TF for the remote state account (local state)
  modules/
    identity/             UAMI
    keyvault/             KV + RSA key + CMK role assignment
    ai-foundry/           AIServices account + project
    model-deployment/     MaaS deployment under the account
  versions.tf             Provider pins
  providers.tf            Provider config
  backend.tf              azurerm backend (populate from bootstrap output)
  variables.tf            Inputs + model_catalog
  locals.tf               Naming + assertions
  main.tf                 Composes modules
  outputs.tf              Including opencode_env
  terraform.tfvars.example

.github/workflows/
  bootstrap.yml           Manual: provision remote state
  deploy.yml              Manual: plan / apply / destroy
  README.md               SP setup + `act` invocations

.secrets.example          Template for ARM_CLIENT_ID/SECRET/TENANT_ID (act)
.actrc                    Default flags for local `act` runs
```

## Running Act locally
  act workflow_dispatch -W .github/workflows/bootstrap.yml -P ubuntu-latest=-self-hosted `
    --secret-file .secrets --input subscription_id=<SUB>

## Out of scope

Private endpoints, VNet integration, AI Search / Cosmos / compute clusters,
CI/CD, Azure Policy, monitoring beyond what CMK requires, multi-region,
multi-subscription. Each is a future module if needed.
