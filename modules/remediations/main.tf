# Raw request shapes and value bounds are checked at the variable boundary.
# This guard blocks derived eligibility and context failures before a
# previously managed request can leave the resource set and be planned for
# destruction. It carries no input so it never plans a change on its own.
resource "terraform_data" "contract_guard" {
  lifecycle {
    precondition {
      condition     = length(local.blocked_request_keys) == 0
      error_message = "Remediation execute or discovery requests failed their contract rules: ${join("; ", local.blocked_request_diagnostics)}. Correct the request before planning a state transition."
    }
  }
}

# Four AzureRM resource types, one per scope. Explicit discovery, disabled
# intent or removal from requests remains a desired-state change that callers
# review and clean up deliberately.
resource "azurerm_management_group_policy_remediation" "this" {
  for_each   = local.by_scope["management_group"]
  depends_on = [terraform_data.contract_guard]

  name                           = each.key
  management_group_id            = each.value.scope_id
  policy_assignment_id           = each.value.policy_assignment_id
  policy_definition_reference_id = each.value.policy_definition_reference_id
  location_filters               = each.value.location_filters
  failure_percentage             = each.value.failure_percentage
  parallel_deployments           = each.value.parallel_deployments
  resource_count                 = each.value.resource_count
}

resource "azurerm_subscription_policy_remediation" "this" {
  for_each   = local.by_scope["subscription"]
  depends_on = [terraform_data.contract_guard]

  name                           = each.key
  subscription_id                = each.value.scope_id
  policy_assignment_id           = each.value.policy_assignment_id
  policy_definition_reference_id = each.value.policy_definition_reference_id
  location_filters               = each.value.location_filters
  resource_discovery_mode        = each.value.resource_discovery_mode
  failure_percentage             = each.value.failure_percentage
  parallel_deployments           = each.value.parallel_deployments
  resource_count                 = each.value.resource_count
}

resource "azurerm_resource_group_policy_remediation" "this" {
  for_each   = local.by_scope["resource_group"]
  depends_on = [terraform_data.contract_guard]

  name                           = each.key
  resource_group_id              = each.value.scope_id
  policy_assignment_id           = each.value.policy_assignment_id
  policy_definition_reference_id = each.value.policy_definition_reference_id
  location_filters               = each.value.location_filters
  resource_discovery_mode        = each.value.resource_discovery_mode
  failure_percentage             = each.value.failure_percentage
  parallel_deployments           = each.value.parallel_deployments
  resource_count                 = each.value.resource_count
}

resource "azurerm_resource_policy_remediation" "this" {
  for_each   = local.by_scope["resource"]
  depends_on = [terraform_data.contract_guard]

  name                           = each.key
  resource_id                    = each.value.scope_id
  policy_assignment_id           = each.value.policy_assignment_id
  policy_definition_reference_id = each.value.policy_definition_reference_id
  location_filters               = each.value.location_filters
  resource_discovery_mode        = each.value.resource_discovery_mode
  failure_percentage             = each.value.failure_percentage
  parallel_deployments           = each.value.parallel_deployments
  resource_count                 = each.value.resource_count
}
