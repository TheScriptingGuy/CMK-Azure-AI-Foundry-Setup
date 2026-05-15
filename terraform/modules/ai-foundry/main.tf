# AIServices account (the new Foundry shape: Microsoft.CognitiveServices/accounts, kind=AIServices).
# CMK is wired via the customer_managed_key block, which targets the UAMI passed in.
# Root module is responsible for ordering this AFTER the KV role assignment via `depends_on = [module.keyvault]`.
resource "azurerm_cognitive_account" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location

  kind     = "AIServices"
  sku_name = "S0"

  public_network_access_enabled = true
  local_auth_enabled            = true # API keys for the MaaS endpoint
  custom_subdomain_name         = var.name

  identity {
    type         = "UserAssigned"
    identity_ids = [var.cmk_identity_id]
  }

  customer_managed_key {
    key_vault_key_id   = "${trimsuffix(var.cmk_key_vault_uri, "/")}/keys/${var.cmk_key_name}"
    identity_client_id = var.cmk_identity_client_id
  }

  tags = var.tags
}

# AI Foundry project under the AIServices account.
# TODO(verify): azurerm_ai_services_project may have landed in a recent provider version — prefer it over azapi if available.
# TODO(verify): API version (2024-10-01 was the GA version at the time of writing; check `az provider show -n Microsoft.CognitiveServices --query "resourceTypes[?resourceType=='accounts/projects'].apiVersions"`).
resource "azapi_resource" "project" {
  type      = "Microsoft.CognitiveServices/accounts/projects@2024-10-01"
  name      = var.project_name
  parent_id = azurerm_cognitive_account.this.id
  location  = var.location

  identity {
    type         = "UserAssigned"
    identity_ids = [var.cmk_identity_id]
  }

  body = {
    properties = {
      displayName = var.project_name
      description = "Default AI Foundry project for CMK-Azure-AI-Foundry-Setup."
    }
  }

  tags = var.tags

  response_export_values = ["properties.endpoints", "identity"]
}
