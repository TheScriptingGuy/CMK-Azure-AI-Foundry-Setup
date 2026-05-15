output "account_id" {
  description = "Resource ID of the AIServices account."
  value       = azapi_resource.account.id
}

output "account_name" {
  description = "Name of the AIServices account."
  value       = azapi_resource.account.name
}

output "account_endpoint" {
  description = "Inference endpoint of the AIServices account."
  value       = azapi_resource.account.output.properties.endpoint
}

output "account_primary_key" {
  description = "Primary key for the AIServices account."
  value       = data.azapi_resource_action.account_keys.output.key1
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
