mock_provider "azurerm" {}

# Scope containment is one rule shared by both operation families. These runs
# cover the accepted nestings and a sibling resource group whose name begins with
# the assignment resource group name.

run "accepts_contained_scopes_in_both_families" {
  command = plan

  variables {
    resolved_assignments = {
      subscription = {
        assignment = {
          id = "/subscriptions/11111111-1111-1111-1111-111111111111/providers/Microsoft.Authorization/policyAssignments/sub-policy"
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
          remediation_reason      = "Eligible for the containment test."
          required_roles = [{
            grant_scope = "/subscriptions/11111111-1111-1111-1111-111111111111"
          }]
        }
      }
      resource_group = {
        assignment = {
          id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/apps/providers/Microsoft.Authorization/policyAssignments/rg-policy"
        }
        intent = {
          scope = {
            type = "resource_group"
            id   = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/apps"
          }
        }
        resolved = {
          policy_definition_id    = "/providers/Microsoft.Authorization/policyDefinitions/example"
          members                 = []
          member_reference_ids    = []
          remediation_eligibility = "eligible"
          remediation_reason      = "Eligible for the containment test."
          required_roles = [{
            grant_scope = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/apps"
          }]
        }
      }
    }
    requests = {
      sub_to_rg = {
        mode                 = "execute"
        assignment_key       = "subscription"
        scope_type           = "resource_group"
        scope_id             = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/apps"
        policy_assignment_id = "/subscriptions/11111111-1111-1111-1111-111111111111/providers/Microsoft.Authorization/policyAssignments/sub-policy"
        role_scope           = "/subscriptions/11111111-1111-1111-1111-111111111111"
        approval_reference   = "CAB-CONTAIN"
        resource_count       = 5
      }
      sub_to_resource = {
        mode                 = "execute"
        assignment_key       = "subscription"
        scope_type           = "resource"
        scope_id             = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/apps/providers/Microsoft.Compute/virtualMachines/vm1"
        policy_assignment_id = "/subscriptions/11111111-1111-1111-1111-111111111111/providers/Microsoft.Authorization/policyAssignments/sub-policy"
        role_scope           = "/subscriptions/11111111-1111-1111-1111-111111111111"
        approval_reference   = "CAB-CONTAIN"
        resource_count       = 5
      }
      rg_to_resource = {
        mode                 = "execute"
        assignment_key       = "resource_group"
        scope_type           = "resource"
        scope_id             = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/apps/providers/Microsoft.Compute/virtualMachines/vm1"
        policy_assignment_id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/apps/providers/Microsoft.Authorization/policyAssignments/rg-policy"
        role_scope           = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/apps"
        approval_reference   = "CAB-CONTAIN"
        resource_count       = 5
      }
    }
    exemptions = {
      sub_to_rg = {
        request_mode  = "create"
        assignment_id = "/subscriptions/11111111-1111-1111-1111-111111111111/providers/Microsoft.Authorization/policyAssignments/sub-policy"
        scope = {
          type = "resource_group"
          id   = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/apps"
        }
        owner                = "platform-team"
        reason               = "Containment test"
        approval_reference   = "APR-CONTAIN"
        category             = "Mitigated"
        compensating_control = "Manual review"
        expires_on           = "2027-01-31T00:00:00Z"
      }
      sub_to_resource = {
        request_mode  = "create"
        assignment_id = "/subscriptions/11111111-1111-1111-1111-111111111111/providers/Microsoft.Authorization/policyAssignments/sub-policy"
        scope = {
          type = "resource"
          id   = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/apps/providers/Microsoft.Compute/virtualMachines/vm1"
        }
        owner                = "platform-team"
        reason               = "Containment test"
        approval_reference   = "APR-CONTAIN"
        category             = "Mitigated"
        compensating_control = "Manual review"
        expires_on           = "2027-01-31T00:00:00Z"
      }
      rg_to_resource = {
        request_mode  = "create"
        assignment_id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/apps/providers/Microsoft.Authorization/policyAssignments/rg-policy"
        scope = {
          type = "resource"
          id   = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/apps/providers/Microsoft.Compute/virtualMachines/vm1"
        }
        owner                = "platform-team"
        reason               = "Containment test"
        approval_reference   = "APR-CONTAIN"
        category             = "Mitigated"
        compensating_control = "Manual review"
        expires_on           = "2027-01-31T00:00:00Z"
      }
    }
    evaluation_time = "2026-10-17T00:00:00Z"
  }

  assert {
    condition     = length(output.created_operations) == 3 && length(output.blocked_operations) == 0
    error_message = "Resource-group and resource scopes inside a subscription assignment, and a resource scope inside a resource-group assignment, must be accepted by remediation requests."
  }

  assert {
    condition     = length(output.created_exemption_ids) == 3
    error_message = "The same contained scopes must be accepted by exemption requests."
  }
}

run "reject_remediation_scope_sharing_a_resource_group_name_prefix" {
  command = plan

  variables {
    resolved_assignments = {
      subscription = {
        assignment = {
          id = "/subscriptions/11111111-1111-1111-1111-111111111111/providers/Microsoft.Authorization/policyAssignments/sub-policy"
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
          remediation_reason      = "Eligible for the containment test."
          required_roles = [{
            grant_scope = "/subscriptions/11111111-1111-1111-1111-111111111111"
          }]
        }
      }
      resource_group = {
        assignment = {
          id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/apps/providers/Microsoft.Authorization/policyAssignments/rg-policy"
        }
        intent = {
          scope = {
            type = "resource_group"
            id   = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/apps"
          }
        }
        resolved = {
          policy_definition_id    = "/providers/Microsoft.Authorization/policyDefinitions/example"
          members                 = []
          member_reference_ids    = []
          remediation_eligibility = "eligible"
          remediation_reason      = "Eligible for the containment test."
          required_roles = [{
            grant_scope = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/apps"
          }]
        }
      }
    }
    requests = {
      rg_to_sibling_resource = {
        mode                 = "execute"
        assignment_key       = "resource_group"
        scope_type           = "resource"
        scope_id             = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/apps-extra/providers/Microsoft.Compute/virtualMachines/vm1"
        policy_assignment_id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/apps/providers/Microsoft.Authorization/policyAssignments/rg-policy"
        role_scope           = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/apps"
        approval_reference   = "CAB-CONTAIN"
        resource_count       = 5
      }
    }
    exemptions      = {}
    evaluation_time = "2026-10-17T00:00:00Z"
  }

  expect_failures = [terraform_data.remediation_contract_guard]
}

run "reject_exemption_scope_sharing_a_resource_group_name_prefix" {
  command = plan

  variables {
    resolved_assignments = {
      subscription = {
        assignment = {
          id = "/subscriptions/11111111-1111-1111-1111-111111111111/providers/Microsoft.Authorization/policyAssignments/sub-policy"
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
          remediation_reason      = "Eligible for the containment test."
          required_roles = [{
            grant_scope = "/subscriptions/11111111-1111-1111-1111-111111111111"
          }]
        }
      }
      resource_group = {
        assignment = {
          id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/apps/providers/Microsoft.Authorization/policyAssignments/rg-policy"
        }
        intent = {
          scope = {
            type = "resource_group"
            id   = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/apps"
          }
        }
        resolved = {
          policy_definition_id    = "/providers/Microsoft.Authorization/policyDefinitions/example"
          members                 = []
          member_reference_ids    = []
          remediation_eligibility = "eligible"
          remediation_reason      = "Eligible for the containment test."
          required_roles = [{
            grant_scope = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/apps"
          }]
        }
      }
    }
    requests = {}
    exemptions = {
      rg_to_sibling_resource = {
        request_mode  = "create"
        assignment_id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/apps/providers/Microsoft.Authorization/policyAssignments/rg-policy"
        scope = {
          type = "resource"
          id   = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/apps-extra/providers/Microsoft.Compute/virtualMachines/vm1"
        }
        owner                = "platform-team"
        reason               = "Containment test"
        approval_reference   = "APR-CONTAIN"
        category             = "Mitigated"
        compensating_control = "Manual review"
        expires_on           = "2027-01-31T00:00:00Z"
      }
    }
    evaluation_time = "2026-10-17T00:00:00Z"
  }

  expect_failures = [terraform_data.exemption_contract_guard]
}
