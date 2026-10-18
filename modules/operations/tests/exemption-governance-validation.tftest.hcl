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

run "missing_owner_blocks_creation" {
  command = plan
  variables {
    exemptions = { invalid = {
      request_mode  = "create"
      assignment_id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/sub-assignment"
      scope         = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000000" }
      reason        = "Missing owner must block create", approval_reference = "APR-MISSING-OWNER"
      category      = "Mitigated", compensating_control = "Manual review"
      expires_on    = "2027-01-31T00:00:00Z"
    } }
  }
  expect_failures = [terraform_data.exemption_contract_guard]
}

run "missing_reason_blocks_creation" {
  command = plan
  variables {
    exemptions = { invalid = {
      request_mode  = "create"
      assignment_id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/sub-assignment"
      scope         = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000000" }
      owner         = "platform-team", approval_reference = "APR-MISSING-REASON"
      category      = "Mitigated", compensating_control = "Manual review"
      expires_on    = "2027-01-31T00:00:00Z"
    } }
  }
  expect_failures = [terraform_data.exemption_contract_guard]
}

run "missing_approval_or_ticket_blocks_creation" {
  command = plan
  variables {
    exemptions = { invalid = {
      request_mode  = "create"
      assignment_id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/sub-assignment"
      scope         = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000000" }
      owner         = "platform-team", reason = "No approval evidence supplied"
      category      = "Mitigated", compensating_control = "Manual review"
      expires_on    = "2027-01-31T00:00:00Z"
    } }
  }
  expect_failures = [terraform_data.exemption_contract_guard]
}

run "missing_compensating_control_blocks_creation" {
  command = plan
  variables {
    exemptions = { invalid = {
      request_mode       = "create"
      assignment_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/sub-assignment"
      scope              = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000000" }
      owner              = "platform-team", reason = "Missing control must block create"
      approval_reference = "APR-MISSING-CONTROL", category = "Mitigated"
      expires_on         = "2027-01-31T00:00:00Z"
    } }
  }
  expect_failures = [terraform_data.exemption_contract_guard]
}

run "blank_governance_values_block_independently" {
  command = plan
  variables {
    exemptions = {
      blank_owner = {
        request_mode  = "create"
        assignment_id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/sub-assignment"
        scope         = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000000" }
        owner         = " ", reason = "Valid reason", approval_reference = "APR-OWNER"
        category      = "Mitigated", compensating_control = "Manual review", expires_on = "2027-01-31T00:00:00Z"
      }
      blank_reason = {
        request_mode  = "create"
        assignment_id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/sub-assignment"
        scope         = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000000" }
        owner         = "platform-team", reason = " ", approval_reference = "APR-REASON"
        category      = "Mitigated", compensating_control = "Manual review", expires_on = "2027-01-31T00:00:00Z"
      }
      blank_approval = {
        request_mode  = "create"
        assignment_id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/sub-assignment"
        scope         = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000000" }
        owner         = "platform-team", reason = "Valid reason", approval_reference = " "
        category      = "Mitigated", compensating_control = "Manual review", expires_on = "2027-01-31T00:00:00Z"
      }
      blank_control = {
        request_mode  = "create"
        assignment_id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/sub-assignment"
        scope         = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000000" }
        owner         = "platform-team", reason = "Valid reason", approval_reference = "APR-CONTROL"
        category      = "Mitigated", compensating_control = " ", expires_on = "2027-01-31T00:00:00Z"
      }
    }
  }
  expect_failures = [terraform_data.exemption_contract_guard]
}

run "missing_and_malformed_expiry_block_active_requests" {
  command = plan
  variables {
    exemptions = {
      missing_expiry = {
        request_mode  = "create"
        assignment_id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/sub-assignment"
        scope         = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000000" }
        owner         = "platform-team", reason = "Missing expiry", approval_reference = "APR-MISSING-EXPIRY"
        category      = "Mitigated", compensating_control = "Manual review", expires_on = null
      }
      malformed_expiry = {
        request_mode  = "renew"
        assignment_id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/sub-assignment"
        scope         = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000000" }
        owner         = "platform-team", reason = "Malformed expiry", approval_reference = "APR-BAD-EXPIRY"
        category      = "Mitigated", compensating_control = "Manual review", expires_on = "not-rfc3339"
      }
    }
  }
  expect_failures = [terraform_data.exemption_contract_guard]
}
