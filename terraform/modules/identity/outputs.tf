output "id" {
  description = "Resource ID of the user-assigned managed identity."
  value       = azurerm_user_assigned_identity.this.id
}

output "principal_id" {
  description = "Object (principal) ID of the identity. Use this for role assignments."
  value       = azurerm_user_assigned_identity.this.principal_id
}

output "client_id" {
  description = "Client (application) ID of the identity."
  value       = azurerm_user_assigned_identity.this.client_id
}

output "tenant_id" {
  description = "Tenant ID of the identity."
  value       = azurerm_user_assigned_identity.this.tenant_id
}
