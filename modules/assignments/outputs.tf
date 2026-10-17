output "assignments" {
  description = "Canonical assignment outputs keyed by stable assignment key."
  value       = local.assignment_outputs
}

output "assignment_names" {
  description = "Deterministic Azure Policy assignment names keyed by stable assignment key."
  value       = local.assignment_names
}

output "management_group_policy_assignment_ids" {
  description = "Management group policy assignment IDs keyed by stable assignment key."
  value = {
    for key, assignment in azurerm_management_group_policy_assignment.this :
    key => assignment.id
  }
}

output "subscription_policy_assignment_ids" {
  description = "Subscription policy assignment IDs keyed by stable assignment key."
  value = {
    for key, assignment in azurerm_subscription_policy_assignment.this :
    key => assignment.id
  }
}

output "resource_group_policy_assignment_ids" {
  description = "Resource group policy assignment IDs keyed by stable assignment key."
  value = {
    for key, assignment in azurerm_resource_group_policy_assignment.this :
    key => assignment.id
  }
}

output "resource_policy_assignment_ids" {
  description = "Resource policy assignment IDs keyed by stable assignment key."
  value = {
    for key, assignment in azurerm_resource_policy_assignment.this :
    key => assignment.id
  }
}

output "replacement_review" {
  description = "Replacement-sensitive assignment fields keyed by stable assignment key."
  value       = local.replacement_review
}
