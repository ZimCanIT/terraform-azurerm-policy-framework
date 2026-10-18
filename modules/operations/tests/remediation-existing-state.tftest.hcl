mock_provider "azurerm" {}

variables {
  resolved_assignments = {
    assignment_ok = {
      assignment = {
        id = "/subscriptions/11111111-1111-1111-1111-111111111111/providers/Microsoft.Authorization/policyAssignments/example"
      }
      intent = {
        scope = {
          type = "subscription"
          id   = "/subscriptions/11111111-1111-1111-1111-111111111111"
        }
      }
      resolved = {
        policy_definition_id    = "/providers/Microsoft.Authorization/policyDefinitions/example"
        members                 = []
        member_reference_ids    = []
        remediation_eligibility = "eligible"
        remediation_reason      = "Modify or DeployIfNotExists is known and role candidates are supplied."
        required_roles          = [{ grant_scope = "/subscriptions/11111111-1111-1111-1111-111111111111" }]
      }
    }
  }

  requests = {
    execute_ok = {
      mode                 = "execute"
      assignment_key       = "assignment_ok"
      scope_type           = "subscription"
      scope_id             = "/subscriptions/11111111-1111-1111-1111-111111111111"
      policy_assignment_id = "/subscriptions/11111111-1111-1111-1111-111111111111/providers/Microsoft.Authorization/policyAssignments/example"
      role_scope           = "/subscriptions/11111111-1111-1111-1111-111111111111"
      approval_reference   = "CAB-12345"
      resource_count       = 50
    }
  }
}

run "create_execute_state" {
  command   = apply
  state_key = "blocked-state"
  assert {
    condition     = length(output.created_operations) == 1
    error_message = "The managed fixture must contain one explicit operation."
  }
}

run "unknown_decision_blocks_existing_state" {
  command   = plan
  state_key = "blocked-state"
  variables {
    resolved_assignments = {
      assignment_ok = {
        assignment = { id = "/subscriptions/11111111-1111-1111-1111-111111111111/providers/Microsoft.Authorization/policyAssignments/example" }
        intent     = { scope = { type = "subscription", id = "/subscriptions/11111111-1111-1111-1111-111111111111" } }
        resolved = {
          policy_definition_id    = "/providers/Microsoft.Authorization/policyDefinitions/example"
          members                 = []
          member_reference_ids    = []
          remediation_eligibility = null
          remediation_reason      = "Stateful failure probe."
          required_roles          = [{ grant_scope = "/subscriptions/11111111-1111-1111-1111-111111111111" }]
        }
      }
    }
  }
  expect_failures = [terraform_data.remediation_contract_guard]
}

run "ineligible_decision_blocks_existing_state" {
  command   = plan
  state_key = "blocked-state"
  variables {
    resolved_assignments = {
      assignment_ok = {
        assignment = { id = "/subscriptions/11111111-1111-1111-1111-111111111111/providers/Microsoft.Authorization/policyAssignments/example" }
        intent     = { scope = { type = "subscription", id = "/subscriptions/11111111-1111-1111-1111-111111111111" } }
        resolved = {
          policy_definition_id    = "/providers/Microsoft.Authorization/policyDefinitions/example"
          members                 = []
          member_reference_ids    = []
          remediation_eligibility = "not_eligible"
          remediation_reason      = "Stateful failure probe."
          required_roles          = [{ grant_scope = "/subscriptions/11111111-1111-1111-1111-111111111111" }]
        }
      }
    }
  }
  expect_failures = [terraform_data.remediation_contract_guard]
}

run "failed_plans_retain_managed_operation" {
  command   = plan
  state_key = "blocked-state"
  assert {
    condition     = azurerm_subscription_policy_remediation.this["execute_ok"].id == run.create_execute_state.created_operations["execute_ok"].id
    error_message = "Failed contract plans must preserve the already-managed operation identity."
  }
}
