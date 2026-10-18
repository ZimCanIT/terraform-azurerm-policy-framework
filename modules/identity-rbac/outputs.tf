output "identity_rbac" {
  description = "Non-sensitive identity and role-grant records keyed by stable assignment key."
  value       = local.outputs
}

output "replacement_impact" {
  description = "Identity and grant replacement-impact records keyed by stable assignment key."
  value = {
    for key, record in local.outputs : key => record.replacement_impact
  }
}

output "assignment_bindings" {
  description = "Assignment identity bindings keyed by stable assignment key, for the assignments that require an identity. The shape is the identity_bindings input of the assignments module, so the two modules connect without reshaping."
  value = {
    for key, record in local.outputs : key => record.assignment_binding
    if record.assignment_binding != null
  }
}
