output "assignment_bindings" {
  description = "Identity bindings keyed by assignment key. The assignment state reads this as its identity_bindings input."
  value       = module.identity_rbac.assignment_bindings
}

output "identity_rbac" {
  description = "Non-sensitive identity and role-grant records for review."
  value       = module.identity_rbac.identity_rbac
}
