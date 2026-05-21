locals {
  # Deterministic suffix: first 8 hex chars of the subscription ID (hyphens removed).
  # Same subscription + name_prefix always produces the same storage account name.
  suffix               = substr(replace(var.subscription_id, "-", ""), 0, 8)
  resource_group_name  = "rg-${var.name_prefix}-tfstate-${local.suffix}"
  storage_account_name = substr("st${var.name_prefix}tf${local.suffix}", 0, 24)
  container_name       = "tfstate"
}

resource "azurerm_resource_group" "tfstate" {
  name     = local.resource_group_name
  location = var.location
  tags     = var.tags
}

resource "azurerm_storage_account" "tfstate" {
  name                            = local.storage_account_name
  resource_group_name             = azurerm_resource_group.tfstate.name
  location                        = azurerm_resource_group.tfstate.location
  account_tier                    = "Standard"
  account_replication_type        = "ZRS"
  account_kind                    = "StorageV2"
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = true
  public_network_access_enabled   = true

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 30
    }

    container_delete_retention_policy {
      days = 30
    }
  }

  tags = var.tags
}

resource "azurerm_storage_container" "tfstate" {
  name                  = local.container_name
  storage_account_id    = azurerm_storage_account.tfstate.id
  container_access_type = "private"
}
