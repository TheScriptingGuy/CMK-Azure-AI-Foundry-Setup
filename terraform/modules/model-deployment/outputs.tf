output "deployment_id" {
  description = "Resource ID of the deployment."
  value       = azapi_resource.deployment.id
}

output "deployment_name" {
  description = "Name of the deployment (also the model alias used in API calls)."
  value       = azapi_resource.deployment.name
}

output "endpoint_url" {
  description = "Base URL for API calls on this deployment (/openai for OpenAI-format models, /anthropic for Anthropic MaaS)."
  value = var.model.model_format == "OpenAI" ? (
    "${trimsuffix(var.account_endpoint, "/")}/openai"
  ) : (
    "${trimsuffix(var.account_endpoint, "/")}/anthropic"
  )
}

output "primary_key" {
  description = "Account primary key. Use as ANTHROPIC_API_KEY."
  value       = var.primary_key
  sensitive   = true
}

output "model_name" {
  description = "Model name as deployed (use as ANTHROPIC_MODEL)."
  value       = var.model.model_name
}
