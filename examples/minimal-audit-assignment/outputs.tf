output "resolved_assignment_review" {
  description = "Resolved audit assignment review keyed by assignment key, showing the resolved Azure target, effective behaviour and deployed assignment identity."
  value = {
    for key, record in module.framework.resolved_assignments : key => {
      scope_type           = try(record.intent.scope.type, null)
      scope_id             = try(record.intent.scope.id, null)
      policy_definition_id = try(record.resolved.policy_definition_id, null)
      effective_effect     = try(record.resolved.effective_effect, null)
      selected_version     = try(record.resolved.selected_version, null)
      source_version       = try(record.resolved.source_version, null)
      version_binding      = try(record.intent.version_binding, null)
      governance_owner     = try(record.intent.governance.owner, null)
      enforcement_mode     = try(record.intent.enforcement_mode, null)
      identity_strategy    = try(record.resolved.identity.strategy, null)
      assignment_id        = try(record.assignment.id, null)
      assignment_name      = try(record.assignment.name, null)
    }
  }
}

output "plan_summary" {
  description = "Scope counts and rollout summary derived from the resolved assignments."
  value       = module.framework.plan_summary
}
