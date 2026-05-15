variable "subscription_id" {
  description = "Azure subscription ID that will hold the remote state account."
  type        = string
}

variable "location" {
  description = "Azure region for the state resource group and storage account."
  type        = string
  default     = "swedencentral"
}

variable "name_prefix" {
  description = "Prefix used to name the state RG and storage account. Lowercase alphanumeric, 3-11 chars."
  type        = string
  default     = "cmkfoundry"

  validation {
    condition     = can(regex("^[a-z0-9]{3,11}$", var.name_prefix))
    error_message = "name_prefix must be 3-11 lowercase alphanumeric characters."
  }
}

variable "tags" {
  description = "Tags applied to all bootstrap resources."
  type        = map(string)
  default = {
    purpose   = "terraform-remote-state"
    component = "cmk-azure-ai-foundry-setup"
  }
}
