output "account_id" {
  description = "Resource ID of the AIServices account."
  value       = azurerm_cognitive_account.this.id
}

output "account_name" {
  description = "Name of the AIServices account."
  value       = azurerm_cognitive_account.this.name
}

output "account_endpoint" {
  description = "Inference endpoint of the AIServices account (e.g. https://<name>.services.ai.azure.com/)."
  value       = azurerm_cognitive_account.this.endpoint
}

output "account_primary_key" {
  description = "Primary key for the AIServices account."
  value       = azurerm_cognitive_account.this.primary_access_key
  sensitive   = true
}

output "project_id" {
  description = "Resource ID of the AI Foundry project."
  value       = azapi_resource.project.id
}

output "project_name" {
  description = "Name of the AI Foundry project."
  value       = azapi_resource.project.name
}
