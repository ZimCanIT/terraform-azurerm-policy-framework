output "resolved_assignments" {
  description = "Resolved assignment records with the created assignment IDs merged in. The operations state reads this as its resolved_assignments input."
  value       = module.assignments.resolved_assignments
}

output "assignment_names" {
  description = "Deterministic assignment names keyed by assignment key, for review."
  value       = module.assignments.assignment_names
}
