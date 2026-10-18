# Self-reported evidence: these suites are agent-run and must be independently
# reproduced by the project owner before publication claims.

mock_provider "azurerm" {}

run "execute_pass" {
  command = plan

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

  assert {
    condition     = length(output.created_operations) == 1 && length(output.blocked_operations) == 0
    error_message = "A fully evidenced execute request must create exactly one remediation resource and block nothing."
  }

  assert {
    condition     = output.requested_operations["execute_ok"].remediation_eligibility == "eligible" && output.requested_operations["execute_ok"].remediation_reason != ""
    error_message = "Requested operations must expose the resolved remediation eligibility and producer reason."
  }

  assert {
    condition     = output.created_operations["execute_ok"].remediation_reason == "Modify or DeployIfNotExists is known and role candidates are supplied."
    error_message = "Created operations must carry the producer remediation reason through the boundary."
  }

  assert {
    condition = (
      azurerm_subscription_policy_remediation.this["execute_ok"].subscription_id == "/subscriptions/11111111-1111-1111-1111-111111111111" &&
      azurerm_subscription_policy_remediation.this["execute_ok"].policy_assignment_id == var.requests["execute_ok"].policy_assignment_id &&
      azurerm_subscription_policy_remediation.this["execute_ok"].resource_count == 50 &&
      azurerm_subscription_policy_remediation.this["execute_ok"].location_filters == null
    )
    error_message = "The subscription remediation resource must receive the requested assignment, scope, limit and absent filters without coercion."
  }
}

run "reject_ineligible_with_reason" {
  command = plan

  variables {
    resolved_assignments = {
      assignment_bad = {
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
          remediation_eligibility = "blocked"
          remediation_reason      = "The effective effect requires an identity but no role definitions were supplied."
          required_roles          = []
        }
      }
    }

    requests = {
      execute_bad = {
        mode                 = "execute"
        assignment_key       = "assignment_bad"
        scope_type           = "subscription"
        scope_id             = "/subscriptions/11111111-1111-1111-1111-111111111111"
        policy_assignment_id = "/subscriptions/11111111-1111-1111-1111-111111111111/providers/Microsoft.Authorization/policyAssignments/example"
        role_scope           = "/subscriptions/11111111-1111-1111-1111-111111111111"
        approval_reference   = "CAB-12345"
        resource_count       = 50
      }
    }
  }

  expect_failures = [terraform_data.remediation_contract_guard]
}

run "reject_blank_eligibility" {
  command = plan

  variables {
    resolved_assignments = {
      assignment_blank = {
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
          remediation_eligibility = ""
          remediation_reason      = ""
          required_roles          = [{ grant_scope = "/subscriptions/11111111-1111-1111-1111-111111111111" }]
        }
      }
    }

    requests = {
      execute_blank = {
        mode                 = "execute"
        assignment_key       = "assignment_blank"
        scope_type           = "subscription"
        scope_id             = "/subscriptions/11111111-1111-1111-1111-111111111111"
        policy_assignment_id = "/subscriptions/11111111-1111-1111-1111-111111111111/providers/Microsoft.Authorization/policyAssignments/example"
        role_scope           = "/subscriptions/11111111-1111-1111-1111-111111111111"
        approval_reference   = "CAB-12345"
        resource_count       = 50
      }
    }
  }

  expect_failures = [var.resolved_assignments]
}

run "reject_resource_scope_mismatch" {
  command = plan

  variables {
    resolved_assignments = {
      assignment_other_sub = {
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
          remediation_reason      = ""
          required_roles          = [{ grant_scope = "/subscriptions/11111111-1111-1111-1111-111111111111" }]
        }
      }
    }

    requests = {
      execute_resource = {
        mode                 = "execute"
        assignment_key       = "assignment_other_sub"
        scope_type           = "resource"
        scope_id             = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/other/providers/Microsoft.Compute/virtualMachines/vm1"
        policy_assignment_id = "/subscriptions/11111111-1111-1111-1111-111111111111/providers/Microsoft.Authorization/policyAssignments/example"
        role_scope           = "/subscriptions/11111111-1111-1111-1111-111111111111"
        approval_reference   = "CAB-12345"
        resource_count       = 50
      }
    }
  }

  expect_failures = [terraform_data.remediation_contract_guard]
}

run "accept_resource_scope_contained" {
  command = plan

  variables {
    resolved_assignments = {
      assignment_sub = {
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
          remediation_reason      = ""
          required_roles          = [{ grant_scope = "/subscriptions/11111111-1111-1111-1111-111111111111" }]
        }
      }
    }

    requests = {
      execute_resource = {
        mode                 = "execute"
        assignment_key       = "assignment_sub"
        scope_type           = "resource"
        scope_id             = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/example/providers/Microsoft.Compute/virtualMachines/vm1"
        policy_assignment_id = "/subscriptions/11111111-1111-1111-1111-111111111111/providers/Microsoft.Authorization/policyAssignments/example"
        role_scope           = "/subscriptions/11111111-1111-1111-1111-111111111111"
        approval_reference   = "CAB-12345"
        resource_count       = 50
      }
    }
  }

  assert {
    condition     = length(output.created_operations) == 1 && output.requested_operations["execute_resource"].status == "created"
    error_message = "A resource-scoped remediation contained within the resolved assignment scope must create its resource."
  }

  assert {
    condition = (
      azurerm_resource_policy_remediation.this["execute_resource"].resource_id == var.requests["execute_resource"].scope_id &&
      azurerm_resource_policy_remediation.this["execute_resource"].policy_assignment_id == var.requests["execute_resource"].policy_assignment_id
    )
    error_message = "The resource-scope branch must project the requested resource ID and assignment ID to AzureRM."
  }
}

run "reject_blank_policy_definition_id" {
  command = plan

  variables {
    resolved_assignments = {
      assignment_nodef = {
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
          policy_definition_id    = ""
          members                 = []
          member_reference_ids    = []
          remediation_eligibility = "eligible"
          remediation_reason      = ""
          required_roles          = [{ grant_scope = "/subscriptions/11111111-1111-1111-1111-111111111111" }]
        }
      }
    }

    requests = {
      execute_nodef = {
        mode                 = "execute"
        assignment_key       = "assignment_nodef"
        scope_type           = "subscription"
        scope_id             = "/subscriptions/11111111-1111-1111-1111-111111111111"
        policy_assignment_id = "/subscriptions/11111111-1111-1111-1111-111111111111/providers/Microsoft.Authorization/policyAssignments/example"
        role_scope           = "/subscriptions/11111111-1111-1111-1111-111111111111"
        approval_reference   = "CAB-12345"
        resource_count       = 50
      }
    }
  }

  expect_failures = [terraform_data.remediation_contract_guard]
}

run "reject_absent_required_fields" {
  command = plan

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
          remediation_reason      = ""
          required_roles          = [{ grant_scope = "/subscriptions/11111111-1111-1111-1111-111111111111" }]
        }
      }
    }

    # policy_assignment_id is optional and derived from the resolved assignment,
    # so the absent required field here is scope_id.
    requests = {
      execute_missing = {
        mode           = "execute"
        assignment_key = "assignment_ok"
        scope_type     = "subscription"
      }
    }
  }

  expect_failures = [var.requests]
}

run "rejects_null_requests" {
  command = plan

  variables {
    requests = null
  }

  expect_failures = [var.requests]
}

run "rejects_scalar_requests" {
  command = plan

  variables {
    requests = "not-a-request-map"
  }

  expect_failures = [var.requests]
}

run "rejects_blank_request_key" {
  command = plan

  variables {
    requests = {
      " " = {
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

  expect_failures = [var.requests]
}

run "rejects_unknown_request_field" {
  command = plan

  variables {
    requests = {
      execute_badfield = {
        mode                 = "execute"
        assignment_key       = "assignment_ok"
        scope_type           = "subscription"
        scope_id             = "/subscriptions/11111111-1111-1111-1111-111111111111"
        policy_assignment_id = "/subscriptions/11111111-1111-1111-1111-111111111111/providers/Microsoft.Authorization/policyAssignments/example"
        role_scope           = "/subscriptions/11111111-1111-1111-1111-111111111111"
        approval_reference   = "CAB-12345"
        resource_count       = 50
        unexpected_field     = "not-in-the-remediations-contract"
      }
    }
  }

  expect_failures = [var.requests]
}

run "reject_malformed_resource_count" {
  command = plan

  variables {
    requests = {
      execute_badcount = {
        mode                 = "execute"
        assignment_key       = "assignment_ok"
        scope_type           = "subscription"
        scope_id             = "/subscriptions/11111111-1111-1111-1111-111111111111"
        policy_assignment_id = "/subscriptions/11111111-1111-1111-1111-111111111111/providers/Microsoft.Authorization/policyAssignments/example"
        role_scope           = "/subscriptions/11111111-1111-1111-1111-111111111111"
        approval_reference   = "CAB-12345"
        resource_count       = "50"
      }
    }
  }

  expect_failures = [var.requests]
}

run "reject_blank_expected_evidence_status" {
  command = plan

  variables {
    requests = {
      execute_badevidence = {
        mode                     = "execute"
        assignment_key           = "assignment_ok"
        scope_type               = "subscription"
        scope_id                 = "/subscriptions/11111111-1111-1111-1111-111111111111"
        policy_assignment_id     = "/subscriptions/11111111-1111-1111-1111-111111111111/providers/Microsoft.Authorization/policyAssignments/example"
        role_scope               = "/subscriptions/11111111-1111-1111-1111-111111111111"
        approval_reference       = "CAB-12345"
        resource_count           = 50
        expected_evidence_status = ""
      }
    }
  }

  expect_failures = [var.requests]
}

run "reject_malformed_discovery_evidence" {
  command = plan

  variables {
    discovery_evidence = {
      malformed_request = {
        targets = "not-a-list"
      }
    }
  }

  expect_failures = [var.discovery_evidence]
}

run "initiative_request_targets_verified_member" {
  command = plan

  variables {
    resolved_assignments = {
      assignment_set = {
        assignment = {
          id = "/subscriptions/11111111-1111-1111-1111-111111111111/providers/Microsoft.Authorization/policyAssignments/set-assignment"
        }
        intent = {
          scope = {
            type = "subscription"
            id   = "/subscriptions/11111111-1111-1111-1111-111111111111"
          }
        }
        resolved = {
          policy_definition_id = "/subscriptions/11111111-1111-1111-1111-111111111111/providers/Microsoft.Authorization/policySetDefinitions/platform-set"
          members = [
            {
              reference_id            = "audit-member"
              policy_definition_id    = "/providers/Microsoft.Authorization/policyDefinitions/audit"
              remediation_eligibility = "not_eligible"
              remediation_reason      = "Audit member does not create remediation tasks."
              required_roles          = []
            },
            {
              reference_id            = "modify-member"
              policy_definition_id    = "/providers/Microsoft.Authorization/policyDefinitions/modify"
              remediation_eligibility = "eligible"
              remediation_reason      = "Selected Modify member has a known definition and role."
              required_roles          = [{ grant_scope = "/subscriptions/11111111-1111-1111-1111-111111111111" }]
            }
          ]
          member_reference_ids    = ["audit-member", "modify-member"]
          remediation_eligibility = "eligible"
          remediation_reason      = "One explicitly selected initiative member is eligible."
          required_roles          = [{ grant_scope = "/subscriptions/11111111-1111-1111-1111-111111111111" }]
        }
      }
    }
    requests = {
      execute_member = {
        mode                           = "execute"
        assignment_key                 = "assignment_set"
        member_reference_id            = "modify-member"
        policy_definition_reference_id = "modify-member"
        scope_type                     = "subscription"
        scope_id                       = "/subscriptions/11111111-1111-1111-1111-111111111111"
        policy_assignment_id           = "/subscriptions/11111111-1111-1111-1111-111111111111/providers/Microsoft.Authorization/policyAssignments/set-assignment"
        role_scope                     = "/subscriptions/11111111-1111-1111-1111-111111111111"
        approval_reference             = "CAB-SET-01"
        resource_count                 = 25
      }
    }
  }

  assert {
    condition = (
      output.requested_operations["execute_member"].status == "created" &&
      output.requested_operations["execute_member"].member_reference_ids == ["audit-member", "modify-member"] &&
      output.requested_operations["execute_member"].policy_definition_id == "/providers/Microsoft.Authorization/policyDefinitions/modify" &&
      output.requested_operations["execute_member"].required_roles[0].grant_scope == "/subscriptions/11111111-1111-1111-1111-111111111111" &&
      azurerm_subscription_policy_remediation.this["execute_member"].policy_definition_reference_id == "modify-member"
    )
    error_message = "An initiative operation must explicitly target one verified member while retaining the complete resolved member inventory."
  }
}

run "reject_audit_member_when_modify_member_is_eligible" {
  command = plan

  variables {
    resolved_assignments = {
      assignment_set = {
        assignment = {
          id = "/subscriptions/11111111-1111-1111-1111-111111111111/providers/Microsoft.Authorization/policyAssignments/set-assignment"
        }
        intent = {
          scope = {
            type = "subscription"
            id   = "/subscriptions/11111111-1111-1111-1111-111111111111"
          }
        }
        resolved = {
          policy_definition_id = "/subscriptions/11111111-1111-1111-1111-111111111111/providers/Microsoft.Authorization/policySetDefinitions/platform-set"
          members = [
            {
              reference_id            = "audit-member"
              policy_definition_id    = "/providers/Microsoft.Authorization/policyDefinitions/audit"
              remediation_eligibility = "not_eligible"
              remediation_reason      = "Audit member does not create remediation tasks."
              required_roles          = []
            },
            {
              reference_id            = "modify-member"
              policy_definition_id    = "/providers/Microsoft.Authorization/policyDefinitions/modify"
              remediation_eligibility = "eligible"
              remediation_reason      = "Selected Modify member has a known definition and role."
              required_roles          = [{ grant_scope = "/subscriptions/11111111-1111-1111-1111-111111111111" }]
            }
          ]
          member_reference_ids    = ["audit-member", "modify-member"]
          remediation_eligibility = "eligible"
          remediation_reason      = "The initiative union is eligible because Modify is present, but this selected Audit member is not remediable."
          required_roles          = [{ grant_scope = "/subscriptions/11111111-1111-1111-1111-111111111111" }]
        }
      }
    }
    requests = {
      execute_member = {
        mode                           = "execute"
        assignment_key                 = "assignment_set"
        member_reference_id            = "audit-member"
        policy_definition_reference_id = "audit-member"
        scope_type                     = "subscription"
        scope_id                       = "/subscriptions/11111111-1111-1111-1111-111111111111"
        policy_assignment_id           = "/subscriptions/11111111-1111-1111-1111-111111111111/providers/Microsoft.Authorization/policyAssignments/set-assignment"
        role_scope                     = "/subscriptions/11111111-1111-1111-1111-111111111111"
        approval_reference             = "CAB-SET-02"
        resource_count                 = 25
      }
    }
  }

  expect_failures = [terraform_data.remediation_contract_guard]
}

run "scope_specific_management_group_and_resource_group_payloads" {
  command = plan

  variables {
    resolved_assignments = {
      mg_assignment = {
        assignment = {
          id = "/providers/Microsoft.Management/managementGroups/platform/providers/Microsoft.Authorization/policyAssignments/mg-policy"
        }
        intent = { scope = { type = "management_group", id = "/providers/Microsoft.Management/managementGroups/platform" } }
        resolved = {
          policy_definition_id    = "/providers/Microsoft.Authorization/policyDefinitions/example"
          members                 = []
          member_reference_ids    = []
          remediation_eligibility = "eligible"
          remediation_reason      = "Management-group policy is eligible."
          required_roles          = [{ grant_scope = "/providers/Microsoft.Management/managementGroups/platform" }]
        }
      }
      rg_assignment = {
        assignment = {
          id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/apps/providers/Microsoft.Authorization/policyAssignments/rg-policy"
        }
        intent = { scope = { type = "resource_group", id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/apps" } }
        resolved = {
          policy_definition_id    = "/providers/Microsoft.Authorization/policyDefinitions/example"
          members                 = []
          member_reference_ids    = []
          remediation_eligibility = "eligible"
          remediation_reason      = "Resource-group policy is eligible."
          required_roles          = [{ grant_scope = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/apps" }]
        }
      }
    }
    requests = {
      execute_mg = {
        mode                 = "execute"
        assignment_key       = "mg_assignment"
        scope_type           = "management_group"
        scope_id             = "/providers/Microsoft.Management/managementGroups/platform"
        policy_assignment_id = "/providers/Microsoft.Management/managementGroups/platform/providers/Microsoft.Authorization/policyAssignments/mg-policy"
        role_scope           = "/providers/Microsoft.Management/managementGroups/platform"
        approval_reference   = "CAB-MG-01"
        resource_count       = 20
      }
      execute_rg = {
        mode                 = "execute"
        assignment_key       = "rg_assignment"
        scope_type           = "resource_group"
        scope_id             = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/apps"
        policy_assignment_id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/apps/providers/Microsoft.Authorization/policyAssignments/rg-policy"
        role_scope           = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/apps"
        approval_reference   = "CAB-RG-01"
        resource_count       = 30
        location_filters     = ["westeurope"]
      }
    }
  }

  assert {
    condition = (
      azurerm_management_group_policy_remediation.this["execute_mg"].management_group_id == var.requests["execute_mg"].scope_id &&
      azurerm_management_group_policy_remediation.this["execute_mg"].resource_count == 20 &&
      azurerm_resource_group_policy_remediation.this["execute_rg"].resource_group_id == var.requests["execute_rg"].scope_id &&
      azurerm_resource_group_policy_remediation.this["execute_rg"].resource_count == 30 &&
      tolist(azurerm_resource_group_policy_remediation.this["execute_rg"].location_filters) == tolist(["westeurope"])
    )
    error_message = "The management-group and resource-group resource branches must receive their supported typed scope and bounded controls."
  }
}

run "discovery_and_disabled_do_not_create_resources" {
  command = plan

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
          remediation_reason      = "Eligible for caller-supplied discovery."
          required_roles          = [{ grant_scope = "/subscriptions/11111111-1111-1111-1111-111111111111" }]
        }
      }
    }
    requests = {
      discover = {
        mode                 = "discovery"
        assignment_key       = "assignment_ok"
        scope_type           = "subscription"
        scope_id             = "/subscriptions/11111111-1111-1111-1111-111111111111"
        policy_assignment_id = "/subscriptions/11111111-1111-1111-1111-111111111111/providers/Microsoft.Authorization/policyAssignments/example"
        approval_reference   = "CAB-DISCOVERY-01"
        role_scope           = "/subscriptions/11111111-1111-1111-1111-111111111111"
        resource_count       = 2
        location_filters     = ["westeurope"]
      }
      disabled = {
        mode                 = "disabled"
        assignment_key       = "assignment_ok"
        scope_type           = "subscription"
        scope_id             = "/subscriptions/11111111-1111-1111-1111-111111111111"
        policy_assignment_id = "/subscriptions/11111111-1111-1111-1111-111111111111/providers/Microsoft.Authorization/policyAssignments/example"
        resource_count       = 2
      }
    }
    discovery_evidence = {
      discover = {
        targets = [
          { resource_id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/a/providers/Microsoft.Compute/virtualMachines/one", location = "westeurope" },
          { resource_id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/a/providers/Microsoft.Compute/virtualMachines/two", location = "eastus" }
        ]
      }
    }
  }

  assert {
    condition = (
      length(output.created_operations) == 0 &&
      length(output.discovered_operations) == 1 &&
      output.discovered_operations["discover"].discovered_count == 1 &&
      length(output.skipped_operations) == 1
    )
    error_message = "Discovery may return only filtered caller evidence and discovery or disabled intent must not create Azure remediation resources."
  }
}

run "approval_and_member_role_scope_gate_execution" {
  command = plan

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
          remediation_reason      = "Eligible with a subscription-scoped role."
          required_roles          = [{ grant_scope = "/subscriptions/11111111-1111-1111-1111-111111111111" }]
        }
      }
    }
    requests = {
      no_approval = {
        mode                 = "execute"
        assignment_key       = "assignment_ok"
        scope_type           = "subscription"
        scope_id             = "/subscriptions/11111111-1111-1111-1111-111111111111"
        policy_assignment_id = "/subscriptions/11111111-1111-1111-1111-111111111111/providers/Microsoft.Authorization/policyAssignments/example"
        role_scope           = "/subscriptions/11111111-1111-1111-1111-111111111111"
        resource_count       = 10
      }
      wrong_role_scope = {
        mode                 = "execute"
        assignment_key       = "assignment_ok"
        scope_type           = "subscription"
        scope_id             = "/subscriptions/11111111-1111-1111-1111-111111111111"
        policy_assignment_id = "/subscriptions/11111111-1111-1111-1111-111111111111/providers/Microsoft.Authorization/policyAssignments/example"
        role_scope           = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/other"
        approval_reference   = "CAB-WRONG-SCOPE"
        resource_count       = 10
      }
      disabled = {
        mode                 = "disabled"
        assignment_key       = "assignment_ok"
        scope_type           = "subscription"
        scope_id             = "/subscriptions/11111111-1111-1111-1111-111111111111"
        policy_assignment_id = "/subscriptions/11111111-1111-1111-1111-111111111111/providers/Microsoft.Authorization/policyAssignments/example"
      }
    }
  }

  expect_failures = [terraform_data.remediation_contract_guard]
}
