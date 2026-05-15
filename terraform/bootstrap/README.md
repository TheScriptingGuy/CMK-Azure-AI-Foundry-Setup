# bootstrap

One-time provisioning of the Azure Storage backend that holds the main config's Terraform state.

State here is **local** on purpose — there is nowhere remote to put it until this code runs.

## Run

```bash
az login
az account set --subscription <SUBSCRIPTION_ID>

cd terraform/bootstrap
terraform init
terraform apply -var "subscription_id=<SUBSCRIPTION_ID>"
```

Capture the `backend_config` output and copy it into `../backend.tf`, then in the main config:

```bash
cd ..
terraform init
```

## Notes

- The storage account name is suffixed with a random 6-char string to dodge the global-uniqueness constraint.
- `use_azuread_auth = true` in the emitted backend block means the operator (or CI principal) needs **Storage Blob Data Contributor** on the container. Shared-key auth on the account is still on as a fallback; flip `shared_access_key_enabled` to `false` once everyone's on AAD auth.
- Do **not** put the Key Vault here. KV lifecycle belongs with the main config so it can be destroyed/recreated without touching the state account.
