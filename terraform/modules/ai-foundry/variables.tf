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

variable "cmk_key_vault_uri" {
  description = "Vault URI of the Key Vault (e.g. https://<name>.vault.azure.net/)."
  type        = string
}

variable "cmk_key_name" {
  description = "Name of the CMK key in the vault."
  type        = string
}

variable "tags" {
  description = "Tags."
  type        = map(string)
  default     = {}
}
