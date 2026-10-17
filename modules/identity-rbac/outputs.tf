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
