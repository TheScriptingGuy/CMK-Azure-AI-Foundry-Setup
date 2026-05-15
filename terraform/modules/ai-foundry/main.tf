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
  allow_project_management      = true

  identity {
    type         = "UserAssigned"
    identity_ids = [var.cmk_identity_id]
  }

  customer_managed_key {
    key_vault_key_id   = var.cmk_key_id
    identity_client_id = var.cmk_identity_client_id
  }

  tags = var.tags
}

resource "azapi_resource" "project" {
  type      = "Microsoft.CognitiveServices/accounts/projects@2025-06-01"
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
