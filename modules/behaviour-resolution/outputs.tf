output "assignments" {
  description = "Canonical resolved assignment records keyed by stable assignment key."
  value       = local.resolved_assignments
}

output "resolution_summary" {
  description = "Non-sensitive summary of the resolved behaviour boundary."
  value       = local.resolution_summary
}

output "definition_ids" {
  description = "Canonical definition IDs keyed by stable catalogue key."
  value = {
    for key, definition in local.definition_entries : key => definition.id
  }
}

output "initiative_ids" {
  description = "Canonical initiative IDs keyed by stable catalogue key."
  value = {
    for key, initiative in local.initiative_entries : key => initiative.id
  }
}
