mock_provider "azurerm" {
  override_during = plan

  mock_resource "azurerm_subscription_policy_assignment" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/mock" }
  }

  mock_resource "azurerm_user_assigned_identity" {
    defaults = {
      id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/policy-identities/providers/Microsoft.ManagedIdentity/userAssignedIdentities/mock"
      principal_id = "00000000-0000-0000-0000-000000000001"
      client_id    = "00000000-0000-0000-0000-000000000002"
    }
  }

  mock_resource "azurerm_role_assignment" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleAssignments/00000000-0000-0000-0000-000000000003"
    }
  }

  mock_resource "azurerm_subscription_policy_remediation" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.PolicyInsights/remediations/mock" }
  }

  mock_resource "azurerm_subscription_policy_exemption" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyExemptions/mock" }
  }
}

run "preserves_effect_and_version_states_through_contract" {
  command = plan

  assert {
    condition     = output.resolver_assignments["platform_locations"].resolved.requested_effect == null && output.resolver_assignments["platform_locations"].resolved.effective_effect == "Audit" && output.resolver_assignments["platform_locations"].resolved.selected_version == null
    error_message = "The behaviour-resolution contract must preserve valid effect resolution and absent version intent."
  }

  assert {
    condition     = output.resolver_assignments["initiative_locations"].resolved.member_effect == "Audit" && output.resolver_assignments["initiative_locations"].resolved.requested_effect == null
    error_message = "The initiative member effect must remain available to the resolver output."
  }

  assert {
    condition = (
      [for member in output.resolver_assignments["initiative_locations"].resolved.members : member.reference_id] == ["allowed_locations", "modify_member", "deploy_member", "disabled_member"] &&
      [for member in output.resolver_assignments["initiative_locations"].resolved.members : member.effective_effect] == ["Audit", "Modify", "DeployIfNotExists", "Disabled"] &&
      output.resolver_assignments["initiative_locations"].resolved.identity.required == true &&
      length(output.resolver_assignments["initiative_locations"].resolved.required_roles) == 2
    )
    error_message = "An initiative assignment must retain every member decision and aggregate identity and role requirements across mixed Audit, Modify, DeployIfNotExists and Disabled members."
  }

  assert {
    condition = (
      output.resolver_assignments["initiative_locations"].resolved.parameter_schema.environment.type == "String" &&
      output.resolver_assignments["initiative_locations"].resolved.parameter_schema.environment.defaultValue == "production" &&
      output.resolver_assignments["initiative_locations"].intent.parameters.environment.value == "test" &&
      output.assignments["initiative_locations"].resolved.parameter_schema.environment.allowedValues == ["production", "test"]
    )
    error_message = "Initiative-set parameter schema and caller intent values must remain distinct through resolution and assignment consumption."
  }

  assert {
    condition = (
      output.resolver_assignments["initiative_locations"].resolved.members[1].remediation_eligibility == "eligible" &&
      output.resolver_assignments["initiative_locations"].resolved.members[2].remediation_eligibility == "eligible" &&
      output.resolver_assignments["initiative_locations"].resolved.members[3].remediation_eligibility == "not_eligible" &&
      output.identity_rbac["initiative_locations"].identity_required == true &&
      length(output.identity_rbac["initiative_locations"].role_grants) == 2 &&
      output.assignments["initiative_locations"].identity_binding.assignment_key == "initiative_locations" &&
      output.assignments["initiative_locations"].identity_binding.identity_strategy == "user_assigned"
    )
    error_message = "Member-specific remediation decisions and assignment-wide identity/RBAC consumers must agree on the complete initiative set."
  }

  assert {
    condition = (
      output.remediations["test_remediation"].policy_assignment_id == "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/remediation_assignment" &&
      !contains(output.remediations["test_remediation"].blocked_reasons, "assignment_id_unknown") &&
      !contains(output.remediations["test_remediation"].blocked_reasons, "assignment_id_mismatch")
    )
    error_message = "A remediation request that omits policy_assignment_id must take the ID from the assignment lifecycle binding of its resolver record."
  }

  assert {
    condition = (
      output.exemptions.approved["initiative_member_exemption"].approved == true &&
      tolist(output.exemptions.approved["initiative_member_exemption"].policy_definition_reference_ids) == tolist(["modify_member"]) &&
      output.exemptions.approved["initiative_member_exemption"].assignment_id == "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/initiative_locations"
    )
    error_message = "The exemption consumer must accept an explicitly selected reference from the initiative's complete resolved member inventory."
  }
}
