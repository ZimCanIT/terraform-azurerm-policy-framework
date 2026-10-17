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
        remediation_reason      = "Eligible for provider-free discovery evidence."
        required_roles          = [{ grant_scope = "/subscriptions/11111111-1111-1111-1111-111111111111" }]
      }
    }
  }
}

run "no_explicit_requests_create_no_remediations" {
  command = plan
  variables {
    requests = {}
  }
  assert {
    condition = (
      length(output.requested_operations) == 0 &&
      length(output.created_operations) == 0 &&
      length(azurerm_subscription_policy_remediation.this) == 0
    )
    error_message = "Resolved assignment eligibility alone must not create a remediation without explicit request intent."
  }
}

run "matching_nonmatching_and_empty_filters" {
  command = plan

  variables {
    requests = {
      matching = {
        mode                 = "discovery", assignment_key = "assignment_ok", scope_type = "subscription"
        scope_id             = "/subscriptions/11111111-1111-1111-1111-111111111111"
        policy_assignment_id = "/subscriptions/11111111-1111-1111-1111-111111111111/providers/Microsoft.Authorization/policyAssignments/example"
        approval_reference   = "CAB-DISCOVERY-MATCH", role_scope = "/subscriptions/11111111-1111-1111-1111-111111111111"
        resource_count       = 2, location_filters = ["westeurope"]
      }
      nonmatching = {
        mode                 = "discovery", assignment_key = "assignment_ok", scope_type = "subscription"
        scope_id             = "/subscriptions/11111111-1111-1111-1111-111111111111"
        policy_assignment_id = "/subscriptions/11111111-1111-1111-1111-111111111111/providers/Microsoft.Authorization/policyAssignments/example"
        approval_reference   = "CAB-DISCOVERY-NOMATCH", role_scope = "/subscriptions/11111111-1111-1111-1111-111111111111"
        resource_count       = 2, location_filters = ["uksouth"]
      }
      empty = {
        mode                 = "discovery", assignment_key = "assignment_ok", scope_type = "subscription"
        scope_id             = "/subscriptions/11111111-1111-1111-1111-111111111111"
        policy_assignment_id = "/subscriptions/11111111-1111-1111-1111-111111111111/providers/Microsoft.Authorization/policyAssignments/example"
        approval_reference   = "CAB-DISCOVERY-EMPTY", role_scope = "/subscriptions/11111111-1111-1111-1111-111111111111"
        resource_count       = 2, location_filters = []
      }
    }
    discovery_evidence = {
      matching = { targets = [
        { resource_id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/a/providers/Microsoft.Compute/virtualMachines/west", location = "westeurope" },
        { resource_id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/a/providers/Microsoft.Compute/virtualMachines/east", location = "eastus" }
      ] }
      nonmatching = { targets = [{ resource_id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/a/providers/Microsoft.Compute/virtualMachines/west", location = "westeurope" }] }
      empty       = { targets = [{ resource_id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/a/providers/Microsoft.Compute/virtualMachines/west", location = "westeurope" }] }
    }
  }

  assert {
    condition = (
      output.discovered_operations["matching"].discovered_count == 1 &&
      output.discovered_operations["matching"].discovered_targets[0].location == "westeurope" &&
      output.discovered_operations["nonmatching"].discovered_count == 0 &&
      output.discovered_operations["empty"].discovered_count == 0 &&
      length(output.created_operations) == 0
    )
    error_message = "Location filters must return matching evidence only, preserve non-matching and explicit-empty outcomes, and create no Azure remediation."
  }
}

run "discovery_limit_rejects_filtered_overflow" {
  command = plan

  variables {
    requests = {
      over_limit = {
        mode                 = "discovery", assignment_key = "assignment_ok", scope_type = "subscription"
        scope_id             = "/subscriptions/11111111-1111-1111-1111-111111111111"
        policy_assignment_id = "/subscriptions/11111111-1111-1111-1111-111111111111/providers/Microsoft.Authorization/policyAssignments/example"
        approval_reference   = "CAB-DISCOVERY-LIMIT", role_scope = "/subscriptions/11111111-1111-1111-1111-111111111111"
        resource_count       = 1, location_filters = ["westeurope"]
      }
    }
    discovery_evidence = {
      over_limit = { targets = [
        { resource_id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/a/providers/Microsoft.Compute/virtualMachines/one", location = "westeurope" },
        { resource_id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/a/providers/Microsoft.Compute/virtualMachines/two", location = "westeurope" }
      ] }
    }
  }

  expect_failures = [terraform_data.contract_guard]
}

run "discovery_requires_known_evidence" {
  command = plan

  variables {
    requests = {
      unknown_evidence = {
        mode                 = "discovery", assignment_key = "assignment_ok", scope_type = "subscription"
        scope_id             = "/subscriptions/11111111-1111-1111-1111-111111111111"
        policy_assignment_id = "/subscriptions/11111111-1111-1111-1111-111111111111/providers/Microsoft.Authorization/policyAssignments/example"
        approval_reference   = "CAB-DISCOVERY-UNKNOWN", role_scope = "/subscriptions/11111111-1111-1111-1111-111111111111"
        resource_count       = 2
      }
    }
  }

  expect_failures = [terraform_data.contract_guard]
}
