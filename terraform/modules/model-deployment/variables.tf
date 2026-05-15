variable "account_id" {
  description = "Resource ID of the parent AIServices account."
  type        = string
}

variable "account_name" {
  description = "Name of the parent AIServices account (used to build the inference URL)."
  type        = string
}

variable "account_endpoint" {
  description = "Inference endpoint of the AIServices account (e.g. https://<name>.services.ai.azure.com/)."
  type        = string
}

variable "deployment_name" {
  description = "Name of the deployment (free-form, used in URLs and as the model alias)."
  type        = string
}

variable "capacity" {
  description = "Throughput capacity for the deployment (PTU or token-rate units depending on SKU)."
  type        = number
  default     = 1
}

variable "model" {
  description = "Catalog entry for the model to deploy."
  type = object({
    publisher     = string
    offer         = string
    sku           = string
    model_name    = string
    model_version = string
    model_format  = string
  })
}

variable "primary_key" {
  description = "Primary access key of the parent AIServices account."
  type        = string
  sensitive   = true
}

variable "model_provider_data" {
  description = "Organization data required by Anthropic MaaS deployments (industry, organizationName, countryCode)."
  type = object({
    organization_name = string
    industry          = string
    country_code      = string
  })
}

variable "tags" {
  description = "Tags."
  type        = map(string)
  default     = {}
}
