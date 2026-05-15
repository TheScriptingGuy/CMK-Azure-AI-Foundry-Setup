resource "random_string" "suffix" {
  length  = 5
  upper   = false
  special = false
}

locals {
  suffix = random_string.suffix.result

  resource_group_name = "rg-${var.name_prefix}-${local.suffix}"
  identity_name       = "id-${var.name_prefix}-cmk-${local.suffix}"
  key_vault_name      = substr("kv-${var.name_prefix}-${local.suffix}", 0, 24)
  cmk_key_name        = "${var.name_prefix}-cmk"
  account_name        = "ai-${var.name_prefix}-${local.suffix}"
}

# Fail-fast if a deployment references a model_key not present in model_catalog.
check "deployments_reference_known_models" {
  assert {
    condition = alltrue([
      for d in var.deployments : contains(keys(var.model_catalog), d.model_key)
    ])
    error_message = "One or more entries in var.deployments reference a model_key that does not exist in var.model_catalog."
  }
}
