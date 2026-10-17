mock_provider "azurerm" {}

variables {
  resolved_assignments = {
    assignment_ok = {
      assignment = { id = "/subscriptions/11111111-1111-1111-1111-111111111111/providers/Microsoft.Authorization/policyAssignments/example" }
      intent     = { scope = { type = "subscription", id = "/subscriptions/11111111-1111-1111-1111-111111111111" } }
      resolved = {
        policy_definition_id    = "/providers/Microsoft.Authorization/policyDefinitions/example"
        members                 = []
        member_reference_ids    = []
        remediation_eligibility = "eligible"
        remediation_reason      = "Eligible for independent optional-field validation."
        required_roles          = [{ grant_scope = "/subscriptions/11111111-1111-1111-1111-111111111111" }]
      }
    }
  }
}

run "reject_blank_location_filter_independently" {
  command = plan
  variables {
    requests = { invalid = {
      mode                 = "execute", assignment_key = "assignment_ok", scope_type = "subscription"
      scope_id             = "/subscriptions/11111111-1111-1111-1111-111111111111"
      policy_assignment_id = "/subscriptions/11111111-1111-1111-1111-111111111111/providers/Microsoft.Authorization/policyAssignments/example"
      role_scope           = "/subscriptions/11111111-1111-1111-1111-111111111111"
      approval_reference   = "CAB-OPTIONAL-LOCATION", resource_count = 5
      location_filters     = [" "]
    } }
  }
  expect_failures = [var.requests]
}

run "reject_fractional_parallel_deployments_independently" {
  command = plan
  variables {
    requests = { invalid = {
      mode                 = "execute", assignment_key = "assignment_ok", scope_type = "subscription"
      scope_id             = "/subscriptions/11111111-1111-1111-1111-111111111111"
      policy_assignment_id = "/subscriptions/11111111-1111-1111-1111-111111111111/providers/Microsoft.Authorization/policyAssignments/example"
      role_scope           = "/subscriptions/11111111-1111-1111-1111-111111111111"
      approval_reference   = "CAB-OPTIONAL-PARALLEL", resource_count = 5
      parallel_deployments = 1.5
    } }
  }
  expect_failures = [var.requests]
}

run "reject_parallel_deployments_above_provider_limit_independently" {
  command = plan
  variables {
    requests = { invalid = {
      mode                 = "execute", assignment_key = "assignment_ok", scope_type = "subscription"
      scope_id             = "/subscriptions/11111111-1111-1111-1111-111111111111"
      policy_assignment_id = "/subscriptions/11111111-1111-1111-1111-111111111111/providers/Microsoft.Authorization/policyAssignments/example"
      role_scope           = "/subscriptions/11111111-1111-1111-1111-111111111111"
      approval_reference   = "CAB-OPTIONAL-PARALLEL-BOUND", resource_count = 5
      parallel_deployments = 31
    } }
  }
  expect_failures = [var.requests]
}

run "reject_resource_count_above_provider_limit_independently" {
  command = plan
  variables {
    requests = { invalid = {
      mode                 = "execute", assignment_key = "assignment_ok", scope_type = "subscription"
      scope_id             = "/subscriptions/11111111-1111-1111-1111-111111111111"
      policy_assignment_id = "/subscriptions/11111111-1111-1111-1111-111111111111/providers/Microsoft.Authorization/policyAssignments/example"
      role_scope           = "/subscriptions/11111111-1111-1111-1111-111111111111"
      approval_reference   = "CAB-OPTIONAL-COUNT-BOUND", resource_count = 50001
    } }
  }
  expect_failures = [var.requests]
}

run "reject_out_of_range_failure_percentage_independently" {
  command = plan
  variables {
    requests = { invalid = {
      mode                 = "execute", assignment_key = "assignment_ok", scope_type = "subscription"
      scope_id             = "/subscriptions/11111111-1111-1111-1111-111111111111"
      policy_assignment_id = "/subscriptions/11111111-1111-1111-1111-111111111111/providers/Microsoft.Authorization/policyAssignments/example"
      role_scope           = "/subscriptions/11111111-1111-1111-1111-111111111111"
      approval_reference   = "CAB-OPTIONAL-FAILURE", resource_count = 5
      failure_percentage   = 1.1
    } }
  }
  expect_failures = [var.requests]
}

run "reject_blank_role_scope_independently" {
  command = plan
  variables {
    requests = { invalid = {
      mode                 = "execute", assignment_key = "assignment_ok", scope_type = "subscription"
      scope_id             = "/subscriptions/11111111-1111-1111-1111-111111111111"
      policy_assignment_id = "/subscriptions/11111111-1111-1111-1111-111111111111/providers/Microsoft.Authorization/policyAssignments/example"
      role_scope           = " "
      approval_reference   = "CAB-OPTIONAL-ROLE", resource_count = 5
    } }
  }
  expect_failures = [var.requests]
}

run "reject_blank_approval_reference_independently" {
  command = plan
  variables {
    requests = { invalid = {
      mode                 = "execute", assignment_key = "assignment_ok", scope_type = "subscription"
      scope_id             = "/subscriptions/11111111-1111-1111-1111-111111111111"
      policy_assignment_id = "/subscriptions/11111111-1111-1111-1111-111111111111/providers/Microsoft.Authorization/policyAssignments/example"
      role_scope           = "/subscriptions/11111111-1111-1111-1111-111111111111"
      approval_reference   = " ", resource_count = 5
    } }
  }
  expect_failures = [var.requests]
}

run "reject_unsupported_discovery_mode_independently" {
  command = plan
  variables {
    requests = { invalid = {
      mode                    = "execute", assignment_key = "assignment_ok", scope_type = "subscription"
      scope_id                = "/subscriptions/11111111-1111-1111-1111-111111111111"
      policy_assignment_id    = "/subscriptions/11111111-1111-1111-1111-111111111111/providers/Microsoft.Authorization/policyAssignments/example"
      role_scope              = "/subscriptions/11111111-1111-1111-1111-111111111111"
      approval_reference      = "CAB-OPTIONAL-DISCOVERY", resource_count = 5
      resource_discovery_mode = "UnboundedDiscovery"
    } }
  }
  expect_failures = [var.requests]
}

run "reject_non_string_evidence_marker_independently" {
  command = plan
  variables {
    requests = { invalid = {
      mode                 = "execute", assignment_key = "assignment_ok", scope_type = "subscription"
      scope_id             = "/subscriptions/11111111-1111-1111-1111-111111111111"
      policy_assignment_id = "/subscriptions/11111111-1111-1111-1111-111111111111/providers/Microsoft.Authorization/policyAssignments/example"
      role_scope           = "/subscriptions/11111111-1111-1111-1111-111111111111"
      approval_reference   = "CAB-OPTIONAL-EVIDENCE", resource_count = 5
      evidence_status      = 7
    } }
  }
  expect_failures = [var.requests]
}

run "reject_blank_expected_evidence_independently" {
  command = plan
  variables {
    requests = { invalid = {
      mode                     = "execute", assignment_key = "assignment_ok", scope_type = "subscription"
      scope_id                 = "/subscriptions/11111111-1111-1111-1111-111111111111"
      policy_assignment_id     = "/subscriptions/11111111-1111-1111-1111-111111111111/providers/Microsoft.Authorization/policyAssignments/example"
      role_scope               = "/subscriptions/11111111-1111-1111-1111-111111111111"
      approval_reference       = "CAB-OPTIONAL-EXPECTED", resource_count = 5
      expected_evidence_status = " "
    } }
  }
  expect_failures = [var.requests]
}
