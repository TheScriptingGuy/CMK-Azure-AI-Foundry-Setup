# GitHub Actions

Two manual workflows. Both run identically in GitHub and locally via
[`act`](https://github.com/nektos/act).

| Workflow | Purpose | Frequency |
|---|---|---|
| `bootstrap.yml` | Provision the remote-state storage account. Emits the backend config as artifact + run summary. | Once per environment. |
| `deploy.yml` | Plan / apply / destroy the main Foundry + CMK config. Backend wired via `-backend-config` flags. | Every change. |

## Auth model

Service principal credentials (`ARM_CLIENT_ID`, `ARM_CLIENT_SECRET`,
`ARM_TENANT_ID`) passed as repo secrets in GitHub or a `.secrets` file
for `act`.

The deploy workflow resolves the SP's own object ID at runtime and grants
it Key Vault Administrator via `TF_VAR_key_vault_admin_object_ids`, so the
SP can create the CMK key.

> OIDC would be cleaner in cloud but doesn't work locally with `act`. To
> switch later, replace the SP env vars and the `az login` step with
> `azure/login@v2` using `client-id` + `tenant-id` + `subscription-id` and
> `permissions: id-token: write`.

## SP setup (one-time)

```bash
SUB=<SUBSCRIPTION_ID>

az ad sp create-for-rbac \
  --name "cmk-foundry-tf-deploy" \
  --role Contributor \
  --scopes "/subscriptions/$SUB"
# → captures appId (ARM_CLIENT_ID), password (ARM_CLIENT_SECRET), tenant (ARM_TENANT_ID)

# Terraform creates role assignments → SP also needs User Access Administrator.
PRINCIPAL_ID=$(az ad sp show --id <appId> --query id -o tsv)
az role assignment create \
  --role "User Access Administrator" \
  --assignee-object-id "$PRINCIPAL_ID" \
  --assignee-principal-type ServicePrincipal \
  --scope "/subscriptions/$SUB"
```

Put the three values into GitHub repo secrets (or `.secrets` locally).

## Running locally with `act`

Two supported modes:

- **Container mode (default, recommended)** — needs Docker Desktop running. `.actrc`
  pins `catthehacker/ubuntu:act-latest`, a Linux image that ships the tools the
  workflows need. Workflows run inside the container exactly as on GitHub-hosted
  runners.
- **Host mode (no Docker, Windows-friendly)** — pass
  `-P ubuntu-latest=-self-hosted`. `act` runs each `run:` block directly on your
  host. The workflows set `defaults.run.shell: bash`, so `act` invokes Git Bash
  on Windows instead of PowerShell — required, because the steps use
  bash-style line continuations and `$VAR` expansion. You must have `bash`,
  `terraform`, and `az` on your PATH; `hashicorp/setup-terraform` will still
  download Terraform per-run.

Install `act` with `winget install nektos.act`, `choco install act-cli`, or
`brew install act`.

```bash
cp .secrets.example .secrets
# Fill in ARM_CLIENT_ID / ARM_CLIENT_SECRET / ARM_TENANT_ID.

# 1) Bootstrap (once per environment)
# Container mode (Docker running):
act workflow_dispatch \
  -W .github/workflows/bootstrap.yml \
  --secret-file .secrets \
  --input subscription_id=<SUB>

# Host mode (no Docker, e.g. Windows without Docker Desktop):
act workflow_dispatch \
  -W .github/workflows/bootstrap.yml \
  -P ubuntu-latest=-self-hosted \
  --secret-file .secrets \
  --input subscription_id=<SUB>

# Grab backend values from the artifact written into ./artifacts/ by act.

# 2) Deploy
act workflow_dispatch \
  -W .github/workflows/deploy.yml \
  --secret-file .secrets \
  --input subscription_id=<SUB> \
  --input action=plan \
  --input backend_resource_group=<RG_FROM_BOOTSTRAP> \
  --input backend_storage_account=<SA_FROM_BOOTSTRAP>

# When the plan looks good:
act workflow_dispatch \
  -W .github/workflows/deploy.yml \
  --secret-file .secrets \
  --input subscription_id=<SUB> \
  --input action=apply \
  --input backend_resource_group=<RG_FROM_BOOTSTRAP> \
  --input backend_storage_account=<SA_FROM_BOOTSTRAP>
```

`act` defaults the artifact path to `./artifacts/`; pass
`--artifact-server-path ./artifacts` if your version doesn't.

## Differences between local and cloud runs

- **Artifacts**: `act` writes them to a local directory; GitHub stores them
  on the run. Same workflow code either way.
- **`GITHUB_STEP_SUMMARY`**: `act` prints the summary to stdout; GitHub
  renders it in the run page.
- **OIDC / federated identity**: not available under `act`. The SP-creds
  path used here works in both.
