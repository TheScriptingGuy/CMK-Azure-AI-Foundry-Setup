variable "name" {
  description = "Key Vault name. Must be globally unique, 3-24 chars."
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

variable "tenant_id" {
  description = "AAD tenant ID of the vault."
  type        = string
}

variable "cmk_key_name" {
  description = "Name of the RSA key used as the CMK."
  type        = string
}

variable "cmk_identity_principal_id" {
  description = "Principal ID of the user-assigned managed identity that will encrypt/decrypt with the key."
  type        = string
}

variable "admin_object_ids" {
  description = "Object IDs to grant Key Vault Administrator (needed to create the key)."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags."
  type        = map(string)
  default     = {}
}
