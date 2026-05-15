# Deploy an Anthropic MaaS model into the AIServices account.
#
# TODO(verify): three open questions to resolve on first `terraform plan`:
#   1. API version. 2024-10-01 was GA at the time of writing; newer versions may exist.
#      Check: az provider show -n Microsoft.CognitiveServices \
#               --query "resourceTypes[?resourceType=='accounts/deployments'].apiVersions"
#   2. Whether a separate Microsoft.SaaS/resources marketplace subscription is required for
#      Anthropic offers. The deployment call appears to create it implicitly in current API
#      versions; if you get a "marketplace agreement not signed" error, uncomment the
#      azapi_resource.marketplace_subscription block below.
#   3. Field shape on the deployment body. The body below uses the model.format/name/version
#      convention (same as Azure OpenAI deployments). If Anthropic offers require
#      publisher/offer/sku at the top of properties, swap the body accordingly.
resource "azapi_resource" "deployment" {
  type      = "Microsoft.CognitiveServices/accounts/deployments@2025-09-01"
  name      = var.deployment_name
  parent_id = var.account_id

  # modelProviderData is absent from azapi's embedded schema for all
  # available API versions; schema_validation_enabled = false is required.
  # The value is JSON-encoded as a string because azapi v2 filters unknown
  # nested objects even with validation disabled.
  schema_validation_enabled = false

  body = {
    sku = {
      name     = var.model.sku
      capacity = var.capacity
    }
    properties = {
      model = {
        format  = var.model.model_format
        name    = var.model.model_name
        version = var.model.model_version
      }
      modelProviderData = {
        industry         = var.model_provider_data.industry
        organizationName = var.model_provider_data.organization_name
        countryCode      = var.model_provider_data.country_code
      }
    }
  }

  tags = var.tags

  response_export_values = ["properties.provisioningState", "properties.model"]
}


# Uncomment if the deployment call complains about a missing marketplace subscription.
# resource "azapi_resource" "marketplace_subscription" {
#   type      = "Microsoft.SaaS/resources@2018-03-01-beta"
#   name      = "${var.account_name}-${var.deployment_name}-marketplace"
#   parent_id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
#   location  = "global"
#   body = {
#     properties = {
#       publisherId          = var.model.publisher
#       offerId              = var.model.offer
#       planId               = var.model.sku
#       termId               = null
#       quantity             = 1
#       autoRenew            = false
#       paymentChannelType   = "SubscriptionDelegated"
#       paymentChannelMetadata = {
#         AzureSubscriptionId = data.azurerm_client_config.current.subscription_id
#       }
#     }
#   }
# }
