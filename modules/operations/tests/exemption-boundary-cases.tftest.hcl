mock_provider "azurerm" {}

variables {
  evaluation_time = "2026-09-15T00:00:00Z"
  resolved_assignments = {
    subscription = {
      assignment = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/sub-assignment" }
      intent     = { scope = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000000" } }
      resolved   = { members = [], member_reference_ids = [] }
    }
  }
}

run "no_exemption_requests_create_no_resources" {
  command = plan
  variables {
    exemptions = {}
  }
  assert {
    condition = (
      length(output.requested_exemptions) == 0 &&
      length(output.created_exemption_ids) == 0 &&
      length(azurerm_subscription_policy_exemption.this) == 0
    )
    error_message = "An assignment alone must never create an exemption without explicit request intent."
  }
}

run "reject_scope_outside_resolved_assignment" {
  command = plan
  variables {
    exemptions = { unrelated_scope = {
      request_mode         = "create"
      assignment_id        = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/sub-assignment"
      scope                = { type = "subscription", id = "/subscriptions/11111111-1111-1111-1111-111111111111" }
      owner                = "platform-team", reason = "Scope must be under assignment"
      approval_reference   = "APR-SCOPE", category = "Mitigated"
      compensating_control = "Manual review", expires_on = "2027-01-31T00:00:00Z"
    } }
  }
  expect_failures = [terraform_data.exemption_contract_guard]
}

run "reject_malformed_scope_id" {
  command = plan
  variables {
    exemptions = { malformed_scope = {
      request_mode         = "create"
      assignment_id        = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/sub-assignment"
      scope                = { type = "subscription", id = "not-an-arm-scope" }
      owner                = "platform-team", reason = "Malformed scope fails closed"
      approval_reference   = "APR-BAD-SCOPE", category = "Mitigated"
      compensating_control = "Manual review", expires_on = "2027-01-31T00:00:00Z"
    } }
  }
  expect_failures = [terraform_data.exemption_contract_guard]
}

run "reject_resource_scope_without_a_resource_name" {
  command = plan
  # accepts_contained_scopes_in_both_families accepts a named resource under a
  # subscription assignment, so the missing resource name is the only defect.
  variables {
    exemptions = { bare_resource_type = {
      request_mode         = "create"
      assignment_id        = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/sub-assignment"
      scope                = { type = "resource", id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/apps/providers/Microsoft.Storage/storageAccounts" }
      owner                = "platform-team", reason = "A resource scope names the resource"
      approval_reference   = "APR-BARE-TYPE", category = "Mitigated"
      compensating_control = "Manual review", expires_on = "2027-01-31T00:00:00Z"
    } }
  }
  expect_failures = [terraform_data.exemption_contract_guard]
}

run "reject_unsupported_selectors" {
  command = plan
  variables {
    exemptions = { selected = {
      request_mode         = "create"
      assignment_id        = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/sub-assignment"
      scope                = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000000" }
      owner                = "platform-team", reason = "Selector support must fail closed"
      approval_reference   = "APR-SELECTOR", category = "Mitigated"
      compensating_control = "Manual review", expires_on = "2027-01-31T00:00:00Z"
      selectors            = [{ kind = "resourceLocation", in = ["westeurope"] }]
    } }
  }
  expect_failures = [terraform_data.exemption_contract_guard]
}

run "reject_unknown_member_inventory_for_targeting" {
  command = plan
  variables {
    resolved_assignments = {
      subscription = {
        assignment = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/sub-assignment" }
        intent     = { scope = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000000" } }
        resolved   = { members = null, member_reference_ids = null }
      }
    }
    exemptions = { unknown_members = {
      request_mode                    = "create"
      assignment_id                   = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/sub-assignment"
      scope                           = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000000" }
      owner                           = "platform-team", reason = "Unknown inventory cannot allow broad targeting"
      approval_reference              = "APR-UNKNOWN-MEMBERS", category = "Mitigated"
      compensating_control            = "Manual review", expires_on = "2027-01-31T00:00:00Z"
      policy_definition_reference_ids = ["member-not-known"]
    } }
  }
  expect_failures = [terraform_data.exemption_contract_guard]
}

run "reject_duplicate_member_targeting" {
  command = plan
  variables {
    resolved_assignments = {
      subscription = {
        assignment = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/sub-assignment" }
        intent     = { scope = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000000" } }
        resolved   = { members = [{ reference_id = "member-a" }], member_reference_ids = ["member-a"] }
      }
    }
    exemptions = { duplicate_members = {
      request_mode                    = "create"
      assignment_id                   = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/sub-assignment"
      scope                           = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000000" }
      owner                           = "platform-team", reason = "Duplicate member selectors are malformed"
      approval_reference              = "APR-DUPLICATE-MEMBERS", category = "Mitigated"
      compensating_control            = "Manual review", expires_on = "2027-01-31T00:00:00Z"
      policy_definition_reference_ids = ["member-a", "member-a"]
    } }
  }
  expect_failures = [terraform_data.exemption_contract_guard]
}
