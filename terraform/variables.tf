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
  description = "Catalog of models available for deployment. OpenAI-format models work on VS Enterprise subscriptions; Anthropic models require a subscription with a payment instrument."
  type = map(object({
    publisher     = string
    offer         = string
    sku           = string
    model_name    = string
    model_version = string
    model_format  = string
  }))
  default = {
    # Microsoft-hosted models — standard Azure billing, no marketplace purchase needed.
    # MAI-DS-R1 = Microsoft AI DeepSeek R1 (Microsoft-published, works on VS Enterprise).
    "mai-ds-r1" = {
      publisher     = "Microsoft"
      offer         = "MAI-DS-R1"
      sku           = "GlobalStandard"
      model_name    = "MAI-DS-R1"
      model_version = "1"
      model_format  = "Microsoft"
    }
    "gpt-5.5" = {
      publisher     = "Microsoft"
      offer         = "gpt-5.5"
      sku           = "GlobalStandard"
      model_name    = "gpt-5.5"
      model_version = "2026-04-24"
      model_format  = "OpenAI"
    }
    # Anthropic models — require Azure Marketplace purchase (payment instrument needed).
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
  default = [
    {
      model_key       = "mai-ds-r1"
      deployment_name = "deepseek-r1"
      capacity        = 1
    }
  ]
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
  description = "Organization data required by Anthropic MaaS model deployments. Leave null for OpenAI models."
  type = object({
    organization_name = string
    industry          = string
    country_code      = string
  })
  default = null
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
