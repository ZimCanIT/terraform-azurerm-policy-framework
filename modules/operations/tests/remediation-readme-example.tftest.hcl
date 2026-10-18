mock_provider "azurerm" {}

variables {
  resolved_assignments = {
    assignment_example = {
      assignment = {
        id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/example"
      }
      intent = {
        scope = {
          type = "subscription"
          id   = "/subscriptions/00000000-0000-0000-0000-000000000000"
        }
      }
      resolved = {
        policy_definition_id    = "/providers/Microsoft.Authorization/policyDefinitions/example"
        member_reference_ids    = []
        members                 = []
        remediation_eligibility = "eligible"
        remediation_reason      = "The resolved direct policy definition is eligible for remediation."
        required_roles          = [{ grant_scope = "/subscriptions/00000000-0000-0000-0000-000000000000" }]
      }
    }
  }

  requests = {
    remediate_example = {
      mode               = "execute"
      assignment_key     = "assignment_example"
      scope_type         = "subscription"
      scope_id           = "/subscriptions/00000000-0000-0000-0000-000000000000"
      role_scope         = "/subscriptions/00000000-0000-0000-0000-000000000000"
      approval_reference = "CAB-12345"
      resource_count     = 50
    }
  }
}

run "public_readme_example_plans_with_canonical_direct_target" {
  command = plan

  assert {
    condition = (
      length(azurerm_subscription_policy_remediation.this) == 1 &&
      length(output.created_operations) == 1 &&
      output.requested_operations["remediate_example"].policy_definition_id == "/providers/Microsoft.Authorization/policyDefinitions/example" &&
      output.requested_operations["remediate_example"].remediation_reason == "The resolved direct policy definition is eligible for remediation." &&
      output.requested_operations["remediate_example"].policy_assignment_id == "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/example"
    )
    error_message = "The documented public example must satisfy the canonical direct-target contract, take its assignment ID from the resolved record and plan only its explicit remediation request."
  }
}
