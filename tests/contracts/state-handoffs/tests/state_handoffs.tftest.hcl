# The mock values are fixed so the direct and separated pipelines read the same
# computed attributes. Every attribute the modules read from a resource has a
# default here; a missing default would make the pipelines differ by chance.
mock_provider "azurerm" {
  override_during = plan

  mock_resource "azurerm_policy_definition" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyDefinitions/mock" }
  }

  mock_resource "azurerm_policy_set_definition" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policySetDefinitions/mock" }
  }

  mock_resource "azurerm_user_assigned_identity" {
    defaults = {
      id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-zctfp-contract/providers/Microsoft.ManagedIdentity/userAssignedIdentities/mock"
      principal_id = "00000000-0000-0000-0000-000000000001"
      client_id    = "00000000-0000-0000-0000-000000000002"
    }
  }

  mock_resource "azurerm_role_assignment" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleAssignments/00000000-0000-0000-0000-000000000003" }
  }

  mock_resource "azurerm_subscription_policy_assignment" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/mock-subscription" }
  }

  mock_resource "azurerm_resource_group_policy_assignment" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-zctfp-contract/providers/Microsoft.Authorization/policyAssignments/mock-resource-group" }
  }

  mock_resource "azurerm_resource_group_policy_remediation" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-zctfp-contract/providers/Microsoft.PolicyInsights/remediations/mock" }
  }

  mock_resource "azurerm_subscription_policy_exemption" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyExemptions/mock-subscription" }
  }

  mock_resource "azurerm_resource_group_policy_exemption" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-zctfp-contract/providers/Microsoft.Authorization/policyExemptions/mock-resource-group" }
  }
}

# C1. Jsonencode equality is used throughout because a decoded list is a tuple
# and Terraform equality compares types as well as values.
run "content_hand_off_keeps_unknown_and_verified_absence" {
  command = plan

  assert {
    condition     = jsonencode(output.handoffs.c1) == jsonencode(output.content)
    error_message = "The content hand-off must carry the definitions and initiatives envelopes unchanged through a JSON boundary."
  }

  assert {
    condition = (
      output.content.definitions["unknown-effects"].supported_effects == null &&
      output.handoffs.c1.definitions["unknown-effects"].supported_effects == null &&
      output.content.definitions["builtin-missing-capability"].role_definition_ids == null &&
      output.handoffs.c1.definitions["builtin-missing-capability"].role_definition_ids == null &&
      output.content.definitions["builtin-missing-capability"].parameters == null &&
      output.handoffs.c1.definitions["builtin-missing-capability"].parameters == null
    )
    error_message = "An unknown capability must stay null through the hand-off and must not become an empty collection."
  }

  assert {
    condition = (
      length(output.handoffs.c1.definitions["verified-empty-effects"].supported_effects) == 0 &&
      output.handoffs.c1.definitions["verified-empty-effects"].supported_effects != null &&
      length(output.handoffs.c1.definitions["builtin-verified-empty"].role_definition_ids) == 0 &&
      length(output.handoffs.c1.definitions["builtin-verified-empty"].parameters) == 0
    )
    error_message = "A verified absence must stay an empty collection through the hand-off and must not become null."
  }

  assert {
    condition = (
      output.handoffs.c1.definitions["rich-custom"].parameters.retryCount.defaultValue == 3 &&
      output.handoffs.c1.definitions["rich-custom"].parameters.enforce.defaultValue == true &&
      output.handoffs.c1.definitions["rich-custom"].selectors[0].in[0] == "eastus" &&
      output.handoffs.c1.definitions["rich-custom"].governance.owner == "platform-team"
    )
    error_message = "Numbers, booleans, lists of objects and governance objects must survive the hand-off."
  }

  assert {
    condition = (
      output.handoffs.c1.initiatives["tag-governance"].policy_definition_references[0].reference_id == "add-costcentre-tag-member" &&
      output.handoffs.c1.initiatives["tag-governance"].governance.requirement_keys[0] == "req-tag-governance"
    )
    error_message = "Initiative member references and governance must survive the hand-off."
  }
}

run "resolution_is_identical_after_the_content_hand_off" {
  command = plan

  assert {
    condition     = jsonencode(output.states.resolution) == jsonencode(output.direct.resolution)
    error_message = "The resolver must produce identical records from the serialised content hand-off and from the direct module outputs."
  }

  assert {
    condition = (
      output.states.resolution.assignments["audit-subscription"].resolved.effective_effect == "Audit" &&
      output.states.resolution.assignments["modify-tag-rg"].resolved.effective_effect == "Modify" &&
      output.states.resolution.assignments["modify-tag-rg"].resolved.identity.required == true &&
      output.states.resolution.assignments["audit-subscription"].resolved.identity.required == false
    )
    error_message = "The compared resolution must be non-trivial: one audit assignment without identity and one Modify assignment that requires one."
  }
}

run "resolution_recomputed_in_two_states_is_identical" {
  command = plan

  assert {
    condition     = jsonencode(output.states.resolution) == jsonencode(output.states.resolution_for_assignment)
    error_message = "Two resolver instances given the same hand-off and intents must produce identical records, because the role-grant and assignment states each recompute them."
  }
}

run "binding_hand_off_is_identical" {
  command = plan

  assert {
    condition     = jsonencode(output.handoffs.c2) == jsonencode(output.direct.identity.assignment_bindings)
    error_message = "The role-grant to assignment hand-off must be identical after a JSON boundary."
  }

  assert {
    condition = (
      length(output.handoffs.c2) == 1 &&
      contains(keys(output.handoffs.c2), "modify-tag-rg") &&
      output.handoffs.c2["modify-tag-rg"].identity_strategy == "user_assigned" &&
      output.handoffs.c2["modify-tag-rg"].identity_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-zctfp-contract/providers/Microsoft.ManagedIdentity/userAssignedIdentities/mock"
    )
    error_message = "Only the assignment that needs an identity may carry a binding, and the binding must carry the created identity ID."
  }

  assert {
    condition     = jsonencode(output.states.identity) == jsonencode(output.direct.identity) && jsonencode(output.states.assignments) == jsonencode(output.direct.assignments)
    error_message = "The identity-rbac and assignments modules must produce identical outputs when the binding crosses a JSON boundary."
  }
}

run "lifecycle_binding_hand_off_is_identical" {
  command = plan

  assert {
    condition     = jsonencode(output.handoffs.c3) == jsonencode(output.direct.assignments.resolved_assignments)
    error_message = "The assignment to operations hand-off must be identical after a JSON boundary."
  }

  assert {
    condition = (
      output.handoffs.c3["audit-subscription"].assignment.id == "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/mock-subscription" &&
      output.handoffs.c3["modify-tag-rg"].assignment.id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-zctfp-contract/providers/Microsoft.Authorization/policyAssignments/mock-resource-group"
    )
    error_message = "Each record must carry the ID of the assignment resource its scope family created."
  }

  assert {
    condition     = jsonencode(output.states.operations) == jsonencode(output.direct.operations)
    error_message = "The operations module must produce identical outputs from the serialised lifecycle hand-off."
  }

  assert {
    condition = (
      output.states.operations.requested_operations["remediate-tag-rg"].policy_assignment_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-zctfp-contract/providers/Microsoft.Authorization/policyAssignments/mock-resource-group" &&
      output.states.operations.requested_operations["remediate-tag-rg"].remediation_eligibility == "eligible" &&
      contains(keys(output.states.operations.created_operations), "remediate-tag-rg")
    )
    error_message = "A request that omits policy_assignment_id must take it from the serialised lifecycle binding and stay eligible."
  }

  assert {
    condition = (
      contains(keys(output.states.operations.active_exemptions), "exempt-audit-subscription") &&
      contains(keys(output.states.operations.active_exemptions), "exempt-tag-member") &&
      length(output.states.operations.blocked_exemptions) == 0 &&
      length(output.states.operations.rejected_exemptions) == 0
    )
    error_message = "Exemptions that name the serialised assignment IDs must verify against the hand-off."
  }
}
