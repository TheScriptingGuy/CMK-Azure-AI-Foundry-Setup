variable "subscription_id" {
  description = "Azure subscription ID to deploy into."
  type        = string
}

variable "tenant_id" {
  description = "Azure AD tenant ID. Used for Key Vault tenant scoping."
  type        = string
}

variable "location" {
  description = "Azure region. Anthropic MaaS availability is limited; eastus2 and swedencentral are the safest bets."
  type        = string
  default     = "swedencentral"
}

variable "name_prefix" {
  description = "Prefix used to name all resources. Lowercase alphanumeric, 3-11 chars."
  type        = string
  default     = "cmkfoundry"

  validation {
    condition     = can(regex("^[a-z0-9]{3,11}$", var.name_prefix))
    error_message = "name_prefix must be 3-11 lowercase alphanumeric characters."
  }
}

variable "project_name" {
  description = "Name of the AI Foundry project under the AIServices account."
  type        = string
  default     = "default"
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default = {
    component = "cmk-azure-ai-foundry-setup"
    managedBy = "terraform"
  }
}

variable "model_catalog" {
  description = <<EOT
Static catalog of supported Anthropic MaaS models on Azure AI Foundry.
Add or update entries here as Anthropic publishes new offers to the Azure Marketplace.
TODO(verify): exact publisher/offer/sku/model_version strings come from the portal Model Catalog
              or `az rest --method get --uri ".../providers/Microsoft.CognitiveServices/locations/<region>/models?api-version=2024-10-01"`.
EOT
  type = map(object({
    publisher     = string
    offer         = string
    sku           = string
    model_name    = string
    model_version = string
    model_format  = string
  }))
  default = {
    "claude-opus-4-7" = {
      publisher     = "Anthropic"
      offer         = "claude-opus-4-7"
      sku           = "GlobalStandard"
      model_name    = "claude-opus-4-7"
      model_version = "1"
      model_format  = "Anthropic"
    }
    "claude-opus-4-6" = {
      publisher     = "Anthropic"
      offer         = "claude-opus-4-6"
      sku           = "GlobalStandard"
      model_name    = "claude-opus-4-6"
      model_version = "1"
      model_format  = "Anthropic"
    }
    "claude-sonnet-4-6" = {
      publisher     = "Anthropic"
      offer         = "claude-sonnet-4-6"
      sku           = "GlobalStandard"
      model_name    = "claude-sonnet-4-6"
      model_version = "1"
      model_format  = "Anthropic"
    }
  }
}

variable "deployments" {
  description = <<EOT
Models to deploy under the AI Foundry project.
The first entry's endpoint + key feed the `opencode_env` output.
Every model_key must exist in model_catalog (enforced by validation below).
EOT
  type = list(object({
    model_key       = string
    deployment_name = string
    capacity        = optional(number, 1)
  }))
  # NOTE: Anthropic MaaS model deployments require an Azure subscription with
  # a valid payment instrument (Pay-As-You-Go or EA). Visual Studio Enterprise
  # (MSDN) subscriptions cannot purchase marketplace models. Set this variable
  # to add model deployments once a billing-enabled subscription is in use.
  default = []
}

variable "key_vault_admin_object_ids" {
  description = <<EOT
Object IDs of AAD principals to grant Key Vault Administrator on the KV.
Typically your own user object ID plus any operator service principals.
The deploying principal needs this to create the RSA key.
EOT
  type    = list(string)
  default = []
}

variable "anthropic_model_provider_data" {
  description = "Organization data required by Anthropic MaaS model deployments. Override to match your organisation."
  type = object({
    organization_name = string
    industry          = string
    country_code      = string
  })
  default = {
    organization_name = "Rubicon"
    industry          = "Technology"
    country_code      = "NL"
  }
}

variable "ai_foundry_role_assignments" {
  description = <<EOT
Data-plane role assignments on the AIServices account. Use this to grant
"Cognitive Services User" (or a broader role like "Azure AI Developer") to
your own user / a service principal so you can call inference APIs with an
AAD token instead of the static account key.

`role` defaults to "Cognitive Services User" — the minimum required to call
the Anthropic-compatible /v1/messages endpoint.

`principal_type` is optional but recommended (User / Group / ServicePrincipal)
to dodge the PrincipalNotFound race on brand-new SPNs.
EOT
  type = list(object({
    principal_id   = string
    role           = optional(string, "Cognitive Services User")
    principal_type = optional(string)
  }))
  default = []
}
