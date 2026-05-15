variable "name" {
  description = "Name of the AIServices account (Cognitive Services account, kind=AIServices)."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "project_name" {
  description = "Name of the AI Foundry project under the account."
  type        = string
}

variable "cmk_identity_id" {
  description = "Resource ID of the user-assigned managed identity used for CMK."
  type        = string
}

variable "cmk_identity_client_id" {
  description = "Client (application) ID of the CMK UAMI. The customer_managed_key block needs the client_id, not the principal_id."
  type        = string
}

variable "cmk_key_id" {
  description = "Versioned ID of the CMK key (azurerm_key_vault_key.id). The Cognitive Services API requires a versioned key URI."
  type        = string
}

variable "tags" {
  description = "Tags."
  type        = map(string)
  default     = {}
}
