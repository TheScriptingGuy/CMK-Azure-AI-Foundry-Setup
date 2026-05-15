resource "azurerm_resource_group" "this" {
  name     = local.resource_group_name
  location = var.location
  tags     = var.tags
}

module "identity" {
  source = "./modules/identity"

  name                = local.identity_name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = var.tags
}

module "keyvault" {
  source = "./modules/keyvault"

  name                      = local.key_vault_name
  resource_group_name       = azurerm_resource_group.this.name
  location                  = azurerm_resource_group.this.location
  tenant_id                 = var.tenant_id
  cmk_key_name              = local.cmk_key_name
  cmk_identity_principal_id = module.identity.principal_id
  admin_object_ids          = var.key_vault_admin_object_ids
  tags                      = var.tags
}

module "ai_foundry" {
  source = "./modules/ai-foundry"

  name                   = local.account_name
  resource_group_name    = azurerm_resource_group.this.name
  location               = azurerm_resource_group.this.location
  project_name           = var.project_name
  cmk_identity_id        = module.identity.id
  cmk_identity_client_id = module.identity.client_id
  cmk_key_id             = module.keyvault.key_id
  tags                   = var.tags

  # The KV role assignment for the UAMI must exist before the account creates,
  # or the customer_managed_key wiring will fail. Module-level depends_on ensures
  # every resource inside keyvault (including the role assignment) is settled first.
  depends_on = [module.keyvault]
}

module "model_deployment" {
  source = "./modules/model-deployment"

  for_each = { for d in var.deployments : d.deployment_name => d }

  account_id       = module.ai_foundry.account_id
  account_name     = module.ai_foundry.account_name
  account_endpoint = module.ai_foundry.account_endpoint
  primary_key      = module.ai_foundry.account_primary_key
  deployment_name  = each.value.deployment_name
  capacity         = each.value.capacity
  model            = var.model_catalog[each.value.model_key]
  tags             = var.tags
}

module "ai_foundry_role_assignments" {
  source = "./modules/role-assignments"

  scope = module.ai_foundry.account_id
  role_assignments = [
    for ra in var.ai_foundry_role_assignments : {
      principal_id   = ra.principal_id
      role           = ra.role
      principal_type = ra.principal_type
    }
  ]
}
