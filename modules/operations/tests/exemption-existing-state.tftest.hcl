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
  exemptions = {
    managed = {
      request_mode         = "create"
      assignment_id        = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/sub-assignment"
      scope                = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000000" }
      owner                = "platform-team"
      reason               = "Baseline approved exception"
      approval_reference   = "APR-STATE-001"
      category             = "Mitigated"
      compensating_control = "Weekly governance review"
      expires_on           = "2027-01-31T00:00:00Z"
    }
  }
}

run "create_managed_exemption_state" {
  command   = apply
  state_key = "exemption-lifecycle"

  assert {
    condition = (
      length(output.created_exemption_ids) == 1 &&
      output.created_exemption_ids["managed"] != null
    )
    error_message = "The lifecycle fixture must persist one explicitly requested exemption identity."
  }
}

run "update_existing_exemption_in_place" {
  command   = plan
  state_key = "exemption-lifecycle"
  variables {
    exemptions = {
      managed = {
        request_mode         = "update"
        assignment_id        = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/sub-assignment"
        scope                = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000000" }
        owner                = "platform-team"
        reason               = "Updated governance exception"
        approval_reference   = "APR-STATE-002"
        category             = "Waiver"
        compensating_control = "Daily governance review"
        expires_on           = "2027-02-28T00:00:00Z"
      }
    }
  }

  assert {
    condition = (
      azurerm_subscription_policy_exemption.this["managed"].id == run.create_managed_exemption_state.created_exemption_ids["managed"] &&
      azurerm_subscription_policy_exemption.this["managed"].expires_on == "2027-02-28T00:00:00Z" &&
      jsondecode(azurerm_subscription_policy_exemption.this["managed"].metadata).approval_reference == "APR-STATE-002"
    )
    error_message = "Update must target the persisted exemption identity and carry the revised governance and expiry values."
  }
}

run "renew_existing_exemption" {
  command   = plan
  state_key = "exemption-lifecycle"
  variables {
    exemptions = {
      managed = {
        request_mode         = "renew"
        assignment_id        = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/sub-assignment"
        scope                = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000000" }
        owner                = "platform-team"
        reason               = "Renewed governance exception"
        ticket_reference     = "CHG-STATE-RENEW"
        category             = "Mitigated"
        compensating_control = "Daily governance review"
        expires_on           = "2027-03-31T00:00:00Z"
      }
    }
  }

  assert {
    condition = (
      azurerm_subscription_policy_exemption.this["managed"].id == run.create_managed_exemption_state.created_exemption_ids["managed"] &&
      azurerm_subscription_policy_exemption.this["managed"].expires_on == "2027-03-31T00:00:00Z" &&
      jsondecode(azurerm_subscription_policy_exemption.this["managed"].metadata).ticket_reference == "CHG-STATE-RENEW"
    )
    error_message = "Renewal must retain the existing exemption identity and project its new expiry and ticket attribution."
  }
}

run "explicit_expire_requests_existing_state_removal" {
  command   = plan
  state_key = "exemption-lifecycle"
  variables {
    exemptions = {
      managed = {
        request_mode         = "expire"
        assignment_id        = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/sub-assignment"
        scope                = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000000" }
        owner                = "platform-team"
        reason               = "Explicit expiry and cleanup"
        ticket_reference     = "CHG-STATE-EXPIRE"
        category             = "Waiver"
        compensating_control = "Return to policy enforcement"
        expires_on           = "2027-01-31T00:00:00Z"
      }
    }
  }

  assert {
    condition = (
      run.create_managed_exemption_state.created_exemption_ids["managed"] != null &&
      length(output.created_exemption_ids) == 0 &&
      output.expired_exemptions["managed"].lifecycle_status == "expired"
    )
    error_message = "Explicit expire intent must preserve expiry status while removing the previously managed exemption from desired resources."
  }
}

run "disabled_intent_removes_existing_exemption" {
  command   = plan
  state_key = "exemption-lifecycle"
  variables {
    exemptions = {
      managed = {
        request_mode         = "disabled"
        assignment_id        = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/sub-assignment"
        scope                = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000000" }
        owner                = "platform-team"
        reason               = "Explicitly disabled"
        ticket_reference     = "CHG-STATE-DISABLE"
        category             = "Waiver"
        compensating_control = "No active exemption"
        expires_on           = "2027-01-31T00:00:00Z"
      }
    }
  }

  assert {
    condition = (
      run.create_managed_exemption_state.created_exemption_ids["managed"] != null &&
      length(output.created_exemption_ids) == 0 &&
      output.blocked_exemptions["managed"].lifecycle_status == "disabled"
    )
    error_message = "Disabled intent must be visible and remove the prior exemption from desired resources."
  }
}

run "request_removal_removes_existing_exemption" {
  command   = plan
  state_key = "exemption-lifecycle"
  variables {
    exemptions = {}
  }

  assert {
    condition = (
      run.create_managed_exemption_state.created_exemption_ids["managed"] != null &&
      length(output.created_exemption_ids) == 0 &&
      length(output.requested_exemptions) == 0
    )
    error_message = "Removing the explicit request must make the existing exemption a visible desired-state deletion."
  }
}
