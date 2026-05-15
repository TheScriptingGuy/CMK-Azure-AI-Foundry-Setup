variable "name" {
  description = "Name of the user-assigned managed identity."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group to create the identity in."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "tags" {
  description = "Tags."
  type        = map(string)
  default     = {}
}
