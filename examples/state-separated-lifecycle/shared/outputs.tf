output "location" {
  description = "Azure region for the target and the assignment identity."
  value       = var.location
}

output "target" {
  description = "Names and resource group ID of the governed target, derived from run_id and the subscription."
  value = {
    resource_group_name  = local.resource_group_name
    resource_group_id    = local.resource_group_id
    storage_account_name = local.storage_account_name
  }
}

output "role_definition_id" {
  description = "Subscription-prefixed Tag Contributor role definition ID shared by the policy content and the assignment intent."
  value       = local.role_definition_id
}

output "assignments" {
  description = "Assignment intents consumed by the resolver in the role-grant and assignment states."
  value       = local.assignments
}
