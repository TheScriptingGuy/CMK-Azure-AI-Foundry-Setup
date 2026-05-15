output "deployment_id" {
  description = "Resource ID of the deployment."
  value       = azapi_resource.deployment.id
}

output "deployment_name" {
  description = "Name of the deployment (also the model alias used in API calls)."
  value       = azapi_resource.deployment.name
}

output "endpoint_url" {
  description = <<EOT
Base URL for the Anthropic-compatible API on this deployment.
TODO(verify): the path suffix may differ — confirm via `az cognitiveservices account deployment show` after first apply.
EOT
  value       = "${trimsuffix(var.account_endpoint, "/")}/anthropic"
}

output "primary_key" {
  description = "Account primary key. Use as ANTHROPIC_API_KEY."
  value       = data.azurerm_cognitive_account.parent.primary_access_key
  sensitive   = true
}

output "model_name" {
  description = "Model name as deployed (use as ANTHROPIC_MODEL)."
  value       = var.model.model_name
}
