output "resource_group_name" {
  description = "Resource group holding the remote state account."
  value       = azurerm_resource_group.tfstate.name
}

output "storage_account_name" {
  description = "Storage account holding the tfstate container."
  value       = azurerm_storage_account.tfstate.name
}

output "container_name" {
  description = "Blob container that holds tfstate blobs."
  value       = azurerm_storage_container.tfstate.name
}

output "backend_config" {
  description = "Paste this into ../backend.tf (or pass via -backend-config) to wire the main config to this backend."
  value       = <<EOT
terraform {
  backend "azurerm" {
    resource_group_name  = "${azurerm_resource_group.tfstate.name}"
    storage_account_name = "${azurerm_storage_account.tfstate.name}"
    container_name       = "${azurerm_storage_container.tfstate.name}"
    key                  = "cmk-azure-ai-foundry.tfstate"
    use_azuread_auth     = true
  }
}
EOT
}
