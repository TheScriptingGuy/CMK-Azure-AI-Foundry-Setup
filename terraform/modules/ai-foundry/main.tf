data "azurerm_client_config" "current" {}

locals {
  # Decompose the versioned key ID (https://<vault>.vault.azure.net/keys/<name>/<version>)
  # into the three components the ARM encryption block needs separately.
  _key_parts    = split("/", var.cmk_key_id)
  key_vault_uri = "https://${local._key_parts[2]}/"
  key_name      = local._key_parts[4]
  key_version   = local._key_parts[5]
}

# Use azapi_resource instead of azurerm_cognitive_account so we can set
# allowProjectManagement = true, which azurerm v4.x does not expose.
resource "azapi_resource" "account" {
  type      = "Microsoft.CognitiveServices/accounts@2025-06-01"
  name      = var.name
  parent_id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${var.resource_group_name}"
  location  = var.location

  identity {
    type         = "UserAssigned"
    identity_ids = [var.cmk_identity_id]
  }

  # schema_validation_enabled = false to pass allowProjectManagement through
  # in case it is absent from azapi's embedded 2025-06-01 account schema.
  schema_validation_enabled = false

  body = {
    kind = "AIServices"
    sku  = { name = "S0" }
    properties = {
      customSubDomainName    = var.name
      publicNetworkAccess    = "Enabled"
      allowProjectManagement = true
      encryption = {
        keySource          = "Microsoft.KeyVault"
        keyVaultProperties = {
          keyVaultUri      = local.key_vault_uri
          keyName          = local.key_name
          keyVersion       = local.key_version
          identityClientId = var.cmk_identity_client_id
        }
      }
    }
  }

  tags = var.tags

  response_export_values = ["properties.endpoint", "properties.endpoints"]
}

data "azapi_resource_action" "account_keys" {
  type        = "Microsoft.CognitiveServices/accounts@2025-06-01"
  resource_id = azapi_resource.account.id
  action      = "listKeys"
  method      = "POST"

  response_export_values = ["key1", "key2"]
}

resource "azapi_resource" "project" {
  type      = "Microsoft.CognitiveServices/accounts/projects@2025-06-01"
  name      = var.project_name
  parent_id = azapi_resource.account.id
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
