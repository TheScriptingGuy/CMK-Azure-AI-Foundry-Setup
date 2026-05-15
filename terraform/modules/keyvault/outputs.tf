output "id" {
  description = "Resource ID of the Key Vault."
  value       = azurerm_key_vault.this.id
}

output "vault_uri" {
  description = "DNS URI of the vault, e.g. https://<name>.vault.azure.net/."
  value       = azurerm_key_vault.this.vault_uri
}

output "key_id" {
  description = "Versioned ID of the CMK key."
  value       = azurerm_key_vault_key.cmk.id
}

output "key_versionless_id" {
  description = "Versionless ID of the CMK key. Use this for auto-rotation."
  value       = azurerm_key_vault_key.cmk.versionless_id
}

output "key_name" {
  description = "Name of the CMK key."
  value       = azurerm_key_vault_key.cmk.name
}

output "cmk_role_assignment_id" {
  description = "Role assignment ID for the CMK identity (depend on this to enforce ordering)."
  value       = azurerm_role_assignment.cmk_user.id
}
