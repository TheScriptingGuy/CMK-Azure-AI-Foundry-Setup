variable "scope" {
  description = "Resource ID to scope every role assignment to (e.g. the AIServices account ID)."
  type        = string
}

variable "role_assignments" {
  description = <<EOT
List of role assignments to create at `scope`.

Each entry grants `role` to `principal_id`. `principal_type` is optional but
recommended (User / Group / ServicePrincipal) — setting it avoids the
"PrincipalNotFound" replication race that hits brand-new service principals.
EOT
  type = list(object({
    principal_id   = string
    role           = string
    principal_type = optional(string)
  }))
  default = []
}
