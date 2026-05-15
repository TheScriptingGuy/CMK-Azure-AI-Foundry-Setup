resource "azurerm_role_assignment" "this" {
  for_each = {
    for ra in var.role_assignments :
    "${ra.principal_id}:${ra.role}" => ra
  }

  scope                = var.scope
  role_definition_name = each.value.role
  principal_id         = each.value.principal_id
  principal_type       = each.value.principal_type
}
