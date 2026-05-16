output "resource_group_name" {
  description = "Resource group containing all deployed resources."
  value       = azurerm_resource_group.this.name
}

output "account_name" {
  description = "Name of the AIServices account."
  value       = module.ai_foundry.account_name
}

output "account_endpoint" {
  description = "Inference endpoint of the AIServices account."
  value       = module.ai_foundry.account_endpoint
}

output "project_name" {
  description = "Name of the AI Foundry project."
  value       = module.ai_foundry.project_name
}

output "project_endpoint" {
  description = "Foundry Agent Service endpoint for this project. Use with the azure-ai-projects SDK to create agents with tools (e.g. WebSearchTool). Format: https://<account>.services.ai.azure.com/api/projects/<project>"
  value       = "${trimsuffix(module.ai_foundry.account_endpoint, "/")}/api/projects/${module.ai_foundry.project_name}"
}

output "key_vault_uri" {
  description = "URI of the Key Vault that holds the CMK."
  value       = module.keyvault.vault_uri
}

output "cmk_key_id" {
  description = "Versioned ID of the CMK key encrypting the AIServices account."
  value       = module.keyvault.key_id
}

output "deployments" {
  description = "Map of deployment_name -> deployment info. Empty when var.deployments = []."
  value = {
    for name, m in module.model_deployment : name => {
      endpoint_url = m.endpoint_url
      model_name   = m.model_name
    }
  }
}

output "opencode_env" {
  description = "Paste-ready shell snippet for the first deployment. Only populated when var.deployments is non-empty. Retrieve with: terraform output -raw opencode_env"
  sensitive   = true
  value = length(var.deployments) > 0 ? (
    var.model_catalog[var.deployments[0].model_key].model_format == "OpenAI" ? join("\n", [
      "export AZURE_OPENAI_API_KEY=${module.model_deployment[var.deployments[0].deployment_name].primary_key}",
      "export AZURE_OPENAI_ENDPOINT=${module.model_deployment[var.deployments[0].deployment_name].endpoint_url}",
      "export AZURE_OPENAI_DEPLOYMENT=${var.deployments[0].deployment_name}",
      "export OPENAI_API_VERSION=2024-10-21",
      "export AZURE_FOUNDRY_PROJECT_ENDPOINT=${trimsuffix(module.ai_foundry.account_endpoint, "/")}/api/projects/${module.ai_foundry.project_name}",
    ]) : join("\n", [
      "export ANTHROPIC_API_KEY=${module.model_deployment[var.deployments[0].deployment_name].primary_key}",
      "export ANTHROPIC_BASE_URL=${module.model_deployment[var.deployments[0].deployment_name].endpoint_url}",
      "export ANTHROPIC_MODEL=${module.model_deployment[var.deployments[0].deployment_name].model_name}",
    ])
  ) : "# No deployments configured. Set var.deployments to add a model deployment."
}
