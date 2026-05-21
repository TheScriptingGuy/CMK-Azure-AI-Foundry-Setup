data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  tenant_id           = var.tenant_id

  sku_name = "standard"

  rbac_authorization_enabled    = true
  purge_protection_enabled      = true
  soft_delete_retention_days    = 90
  public_network_access_enabled = true

  tags = var.tags
}

# Grant the deploying principal (and any extra admins) Key Vault Administrator so it can create the key.
locals {
  admin_object_ids = distinct(concat(
    [data.azurerm_client_config.current.object_id],
    var.admin_object_ids,
  ))
}

resource "azurerm_role_assignment" "admin" {
  for_each = toset(local.admin_object_ids)

  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = each.value
}

# CMK identity needs to wrap/unwrap with the key.
resource "azurerm_role_assignment" "cmk_user" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Crypto Service Encryption User"
  principal_id         = var.cmk_identity_principal_id
}

resource "azurerm_key_vault_key" "cmk" {
  name         = var.cmk_key_name
  key_vault_id = azurerm_key_vault.this.id
  key_type     = "RSA"
  key_size     = 4096

  key_opts = [
    "wrapKey",
    "unwrapKey",
  ]

  depends_on = [azurerm_role_assignment.admin]
}
