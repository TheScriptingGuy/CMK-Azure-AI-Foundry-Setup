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
  type      = "Microsoft.CognitiveServices/accounts/deployments@2024-10-01"
  name      = var.deployment_name
  parent_id = var.account_id

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
      raiPolicyName = "Microsoft.DefaultV2" # TODO(verify): RAI policies may not apply to Anthropic; remove if API rejects it.
    }
  }

  tags = var.tags

  response_export_values = ["properties.provisioningState", "properties.model"]
}

# Pull the account's primary key so we can hand it back to the caller as the API key for OpenCode.
# AIServices keys are account-level; one key serves all deployments under the account.
data "azurerm_cognitive_account" "parent" {
  name                = var.account_name
  resource_group_name = regex("/resourceGroups/([^/]+)/", var.account_id)[0]
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
