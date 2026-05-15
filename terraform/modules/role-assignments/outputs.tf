output "role_assignment_ids" {
  description = "Map of \"<principal_id>:<role>\" -> azurerm_role_assignment.id."
  value       = { for k, ra in azurerm_role_assignment.this : k => ra.id }
}
