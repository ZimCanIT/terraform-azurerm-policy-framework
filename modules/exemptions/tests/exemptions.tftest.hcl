mock_provider "azurerm" {}

run "strict_governance_strings_pass" {
  command = plan

  variables {
    evaluation_time = "2026-09-15T00:00:00Z"

    assignments = {
      subscription = {
        assignment = {
          id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/sub-assignment"
        }
        intent = {
          scope = {
            type = "subscription"
            id   = "/subscriptions/00000000-0000-0000-0000-000000000000"
          }
        }
        resolved = {
          members              = [{ reference_id = "member-a" }, { reference_id = "member-b" }]
          member_reference_ids = ["member-a", "member-b"]
        }
      }
    }

    exemptions = {
      supplied = {
        request_mode  = "create"
        assignment_id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/sub-assignment"
        scope = {
          type = "subscription"
          id   = "/subscriptions/00000000-0000-0000-0000-000000000000"
        }
        owner                           = "platform-team"
        reason                          = "Approved migration exception"
        approval_reference              = "APR-001"
        category                        = "Mitigated"
        compensating_control            = "Weekly governance review"
        expires_on                      = "2027-01-31T00:00:00Z"
        display_name                    = "Platform migration exemption"
        description                     = "Single-line description with inner spacing allowed"
        policy_definition_reference_ids = ["member-a"]
      }
    }
  }

  assert {
    condition     = output.requested_exemptions["supplied"].display_name == "Platform migration exemption" && output.requested_exemptions["supplied"].description == "Single-line description with inner spacing allowed"
    error_message = "Strict governance strings that pass must be preserved unchanged in the request output."
  }

  assert {
    condition     = output.approved_exemptions["supplied"].approved == true && output.active_exemptions["supplied"].active == true
    error_message = "A request whose governance strings pass the strict rule must be approved and active."
  }

  assert {
    condition     = length(output.created_exemption_ids) == 1
    error_message = "A request whose governance strings pass must create exactly one exemption resource."
  }

  assert {
    condition = (
      azurerm_subscription_policy_exemption.this["supplied"].policy_assignment_id == var.exemptions["supplied"].assignment_id &&
      azurerm_subscription_policy_exemption.this["supplied"].exemption_category == "Mitigated" &&
      tolist(azurerm_subscription_policy_exemption.this["supplied"].policy_definition_reference_ids) == tolist(["member-a"]) &&
      jsondecode(azurerm_subscription_policy_exemption.this["supplied"].metadata).approval_reference == "APR-001" &&
      jsondecode(azurerm_subscription_policy_exemption.this["supplied"].metadata).compensating_control == "Weekly governance review"
    )
    error_message = "The provider payload must retain assignment targeting, category and governed approval metadata."
  }
}

run "absent_versus_empty_distinction" {
  command = plan

  variables {
    evaluation_time = "2026-09-15T00:00:00Z"

    assignments = {
      subscription = {
        assignment = {
          id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/sub-assignment"
        }
        intent = {
          scope = {
            type = "subscription"
            id   = "/subscriptions/00000000-0000-0000-0000-000000000000"
          }
        }
        resolved = {
          members              = [{ reference_id = "member-a" }, { reference_id = "member-b" }]
          member_reference_ids = ["member-a", "member-b"]
        }
      }
    }

    exemptions = {
      absent = {
        request_mode  = "renew"
        assignment_id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/sub-assignment"
        scope = {
          type = "subscription"
          id   = "/subscriptions/00000000-0000-0000-0000-000000000000"
        }
        owner                = "platform-team"
        reason               = "Renewal without optional strings"
        ticket_reference     = "CHG-0001"
        category             = "Waiver"
        compensating_control = "Manual sign-off"
        expires_on           = "2027-02-28T00:00:00Z"
      }

      empty = {
        request_mode  = "update"
        assignment_id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/sub-assignment"
        scope = {
          type = "subscription"
          id   = "/subscriptions/00000000-0000-0000-0000-000000000000"
        }
        owner                           = "platform-team"
        reason                          = "Update with verified absent targeting"
        approval_reference              = "APR-002"
        category                        = "Waiver"
        compensating_control            = "Manual sign-off"
        expires_on                      = "2027-03-31T00:00:00Z"
        policy_definition_reference_ids = []
        display_name                    = "Whole assignment update"
      }
    }
  }

  assert {
    condition     = jsonencode(output.requested_exemptions["absent"].policy_definition_reference_ids) == "null" && output.requested_exemptions["absent"].display_name == null && output.requested_exemptions["absent"].description == null
    error_message = "Absent targeting and absent optional strings must stay null."
  }

  assert {
    condition     = jsonencode(output.requested_exemptions["empty"].policy_definition_reference_ids) == "[]" && output.requested_exemptions["empty"].display_name == "Whole assignment update"
    error_message = "Explicit empty targeting must stay an empty list while supplied strings are preserved."
  }

  assert {
    condition     = length(output.created_exemption_ids) == 2
    error_message = "Absent and empty targeting must both create their requested exemption resources."
  }
}

run "reject_inner_newline_description" {
  command = plan

  variables {
    evaluation_time = "2026-09-15T00:00:00Z"

    assignments = {
      subscription = {
        assignment = {
          id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/sub-assignment"
        }
        intent = {
          scope = {
            type = "subscription"
            id   = "/subscriptions/00000000-0000-0000-0000-000000000000"
          }
        }
        resolved = {
          members              = [{ reference_id = "member-a" }, { reference_id = "member-b" }]
          member_reference_ids = ["member-a", "member-b"]
        }
      }
    }

    exemptions = {
      bad_description = {
        request_mode  = "create"
        assignment_id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/sub-assignment"
        scope = {
          type = "subscription"
          id   = "/subscriptions/00000000-0000-0000-0000-000000000000"
        }
        owner                = "platform-team"
        reason               = "Approved migration exception"
        approval_reference   = "APR-001"
        category             = "Mitigated"
        compensating_control = "Weekly governance review"
        expires_on           = "2027-01-31T00:00:00Z"
        description          = "line one\nline two"
      }
    }
  }

  expect_failures = [terraform_data.contract_guard]
}

run "reject_leading_space_category" {
  command = plan

  variables {
    evaluation_time = "2026-09-15T00:00:00Z"

    assignments = {
      subscription = {
        assignment = {
          id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/sub-assignment"
        }
        intent = {
          scope = {
            type = "subscription"
            id   = "/subscriptions/00000000-0000-0000-0000-000000000000"
          }
        }
        resolved = {
          members              = [{ reference_id = "member-a" }, { reference_id = "member-b" }]
          member_reference_ids = ["member-a", "member-b"]
        }
      }
    }

    exemptions = {
      bad_category = {
        request_mode  = "create"
        assignment_id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/sub-assignment"
        scope = {
          type = "subscription"
          id   = "/subscriptions/00000000-0000-0000-0000-000000000000"
        }
        owner                = "platform-team"
        reason               = "Approved migration exception"
        approval_reference   = "APR-001"
        category             = " Mitigated"
        compensating_control = "Weekly governance review"
        expires_on           = "2027-01-31T00:00:00Z"
      }
    }
  }

  expect_failures = [terraform_data.contract_guard]
}

run "reject_empty_description" {
  command = plan

  variables {
    evaluation_time = "2026-09-15T00:00:00Z"

    assignments = {
      subscription = {
        assignment = {
          id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/sub-assignment"
        }
        intent = {
          scope = {
            type = "subscription"
            id   = "/subscriptions/00000000-0000-0000-0000-000000000000"
          }
        }
        resolved = {
          members              = [{ reference_id = "member-a" }, { reference_id = "member-b" }]
          member_reference_ids = ["member-a", "member-b"]
        }
      }
    }

    exemptions = {
      blank_description = {
        request_mode  = "create"
        assignment_id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/sub-assignment"
        scope = {
          type = "subscription"
          id   = "/subscriptions/00000000-0000-0000-0000-000000000000"
        }
        owner                = "platform-team"
        reason               = "Approved migration exception"
        approval_reference   = "APR-001"
        category             = "Mitigated"
        compensating_control = "Weekly governance review"
        expires_on           = "2027-01-31T00:00:00Z"
        description          = ""
      }
    }
  }

  expect_failures = [terraform_data.contract_guard]
}

run "lifecycle_modes_and_elapsed_expiry" {
  command = plan

  variables {
    evaluation_time = "2026-09-15T00:00:00Z"
    assignments = {
      subscription = {
        assignment = {
          id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/sub-assignment"
        }
        intent = {
          scope = {
            type = "subscription"
            id   = "/subscriptions/00000000-0000-0000-0000-000000000000"
          }
        }
        resolved = {
          members              = [{ reference_id = "member-a" }, { reference_id = "member-b" }]
          member_reference_ids = ["member-a", "member-b"]
        }
      }
    }
    exemptions = {
      create = {
        request_mode         = "create"
        assignment_id        = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/sub-assignment"
        scope                = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000000" }
        owner                = "platform-team"
        reason               = "Approved create"
        approval_reference   = "APR-CREATE"
        category             = "Mitigated"
        compensating_control = "Weekly review"
        expires_on           = "2027-01-31T00:00:00Z"
      }
      update = {
        request_mode         = "update"
        assignment_id        = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/sub-assignment"
        scope                = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000000" }
        owner                = "platform-team"
        reason               = "Approved update"
        approval_reference   = "APR-UPDATE"
        category             = "Waiver"
        compensating_control = "Monthly review"
        expires_on           = "2027-02-28T00:00:00Z"
      }
      renew = {
        request_mode         = "renew"
        assignment_id        = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/sub-assignment"
        scope                = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000000" }
        owner                = "platform-team"
        reason               = "Approved renewal"
        ticket_reference     = "CHG-RENEW"
        category             = "Mitigated"
        compensating_control = "Monthly review"
        expires_on           = "2027-03-31T00:00:00Z"
      }
      expired = {
        request_mode         = "expire"
        assignment_id        = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/sub-assignment"
        scope                = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000000" }
        owner                = "platform-team"
        reason               = "Explicit expiry"
        ticket_reference     = "CHG-EXPIRED"
        category             = "Waiver"
        compensating_control = "Standard enforcement"
        expires_on           = "2026-09-14T23:59:59Z"
      }
      disabled = {
        request_mode         = "disabled"
        assignment_id        = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/sub-assignment"
        scope                = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000000" }
        owner                = "platform-team"
        reason               = "Disabled request"
        ticket_reference     = "CHG-DISABLED"
        category             = "Waiver"
        compensating_control = "No active exception"
        expires_on           = "2027-04-30T00:00:00Z"
      }
      blocked = {
        request_mode         = "blocked"
        assignment_id        = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/sub-assignment"
        scope                = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000000" }
        owner                = "platform-team"
        reason               = "Blocked pending review"
        ticket_reference     = "CHG-BLOCKED"
        category             = "Waiver"
        compensating_control = "Manual review"
        expires_on           = "2027-04-30T00:00:00Z"
      }
      rejected = {
        request_mode         = "reject"
        assignment_id        = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/sub-assignment"
        scope                = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000000" }
        owner                = "platform-team"
        reason               = "Rejected request"
        ticket_reference     = "CHG-REJECTED"
        category             = "Waiver"
        compensating_control = "Standard enforcement"
        expires_on           = "2027-04-30T00:00:00Z"
      }
    }
  }

  assert {
    condition = (
      length(output.created_exemption_ids) == 3 &&
      length(output.active_exemptions) == 3 &&
      contains(keys(output.expired_exemptions), "expired") &&
      contains(keys(output.blocked_exemptions), "disabled") &&
      contains(keys(output.blocked_exemptions), "blocked") &&
      contains(keys(output.rejected_exemptions), "rejected")
    )
    error_message = "Only approved, unexpired create, update and renew requests may create exemption resources; expiry and other lifecycle states remain visible."
  }

  assert {
    condition = (
      output.active_exemptions["create"].azure_status == "created_by_module" &&
      output.active_exemptions["create"].expires_on == "2027-01-31T00:00:00Z" &&
      output.expired_exemptions["expired"].azure_status == "not_created" &&
      !contains(keys(output.created_exemption_ids), "disabled") &&
      !contains(keys(output.created_exemption_ids), "blocked") &&
      !contains(keys(output.created_exemption_ids), "rejected")
    )
    error_message = "Exemption outputs must separate lifecycle intent from Azure status, preserve expiry metadata, and never create resources for disabled, blocked or rejected requests."
  }
}

run "reject_elapsed_renewal_without_removal_plan" {
  command = plan

  variables {
    evaluation_time = "2026-09-15T00:00:00Z"
    assignments = {
      subscription = {
        assignment = {
          id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/sub-assignment"
        }
        intent = {
          scope = {
            type = "subscription"
            id   = "/subscriptions/00000000-0000-0000-0000-000000000000"
          }
        }
        resolved = { members = [], member_reference_ids = [] }
      }
    }
    exemptions = {
      elapsed = {
        request_mode         = "renew"
        assignment_id        = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/sub-assignment"
        scope                = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000000" }
        owner                = "platform-team"
        reason               = "Renewal after expiry"
        approval_reference   = "APR-ELAPSED"
        category             = "Mitigated"
        compensating_control = "Manual review"
        expires_on           = "2026-09-14T23:59:59Z"
      }
    }
  }

  expect_failures = [terraform_data.contract_guard]
}

run "all_scope_resource_payloads" {
  command = plan

  variables {
    evaluation_time = "2026-09-15T00:00:00Z"
    assignments = {
      management_group = {
        assignment = { id = "/providers/Microsoft.Management/managementGroups/platform/providers/Microsoft.Authorization/policyAssignments/mg-policy" }
        intent     = { scope = { type = "management_group", id = "/providers/Microsoft.Management/managementGroups/platform" } }
        resolved   = { members = [], member_reference_ids = [] }
      }
      subscription = {
        assignment = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/sub-policy" }
        intent     = { scope = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000000" } }
        resolved   = { members = [], member_reference_ids = [] }
      }
      resource_group = {
        assignment = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/apps/providers/Microsoft.Authorization/policyAssignments/rg-policy" }
        intent     = { scope = { type = "resource_group", id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/apps" } }
        resolved   = { members = [], member_reference_ids = [] }
      }
      resource = {
        assignment = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/apps/providers/Microsoft.Compute/virtualMachines/vm1/providers/Microsoft.Authorization/policyAssignments/resource-policy" }
        intent     = { scope = { type = "resource", id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/apps/providers/Microsoft.Compute/virtualMachines/vm1" } }
        resolved   = { members = [{ reference_id = "audit-member" }, { reference_id = "modify-member" }], member_reference_ids = ["audit-member", "modify-member"] }
      }
    }
    exemptions = {
      management_group = {
        request_mode         = "create"
        assignment_id        = "/providers/Microsoft.Management/managementGroups/platform/providers/Microsoft.Authorization/policyAssignments/mg-policy"
        scope                = { type = "management_group", id = "/providers/Microsoft.Management/managementGroups/platform" }
        owner                = "platform-team"
        reason               = "Management group exception"
        approval_reference   = "APR-MG"
        category             = "Mitigated"
        compensating_control = "Monthly review"
        expires_on           = "2027-01-31T00:00:00Z"
      }
      subscription = {
        request_mode         = "create"
        assignment_id        = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/sub-policy"
        scope                = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000000" }
        owner                = "platform-team"
        reason               = "Subscription exception"
        approval_reference   = "APR-SUB"
        category             = "Waiver"
        compensating_control = "Weekly review"
        expires_on           = "2027-01-31T00:00:00Z"
      }
      resource_group = {
        request_mode         = "renew"
        assignment_id        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/apps/providers/Microsoft.Authorization/policyAssignments/rg-policy"
        scope                = { type = "resource_group", id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/apps" }
        owner                = "platform-team"
        reason               = "Resource group renewal"
        ticket_reference     = "CHG-RG"
        category             = "Mitigated"
        compensating_control = "Daily review"
        expires_on           = "2027-02-28T00:00:00Z"
      }
      resource = {
        request_mode                    = "update"
        assignment_id                   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/apps/providers/Microsoft.Compute/virtualMachines/vm1/providers/Microsoft.Authorization/policyAssignments/resource-policy"
        scope                           = { type = "resource", id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/apps/providers/Microsoft.Compute/virtualMachines/vm1" }
        owner                           = "platform-team"
        reason                          = "Resource update"
        ticket_reference                = "CHG-RESOURCE"
        category                        = "Waiver"
        compensating_control            = "Quarterly review"
        expires_on                      = "2027-03-31T00:00:00Z"
        policy_definition_reference_ids = ["modify-member"]
      }
    }
  }

  assert {
    condition = (
      azurerm_management_group_policy_exemption.this["management_group"].management_group_id == var.exemptions["management_group"].scope.id &&
      azurerm_subscription_policy_exemption.this["subscription"].subscription_id == var.exemptions["subscription"].scope.id &&
      azurerm_resource_group_policy_exemption.this["resource_group"].resource_group_id == var.exemptions["resource_group"].scope.id &&
      azurerm_resource_policy_exemption.this["resource"].resource_id == var.exemptions["resource"].scope.id &&
      tolist(azurerm_resource_policy_exemption.this["resource"].policy_definition_reference_ids) == tolist(["modify-member"]) &&
      length(output.created_exemption_ids) == 4
    )
    error_message = "All four exemption resource branches must receive their typed scope, and member targeting must match the complete assignment inventory."
  }
}

run "reject_unknown_or_unrelated_member_targeting" {
  command = plan

  variables {
    evaluation_time = "2026-09-15T00:00:00Z"
    assignments = {
      subscription = {
        assignment = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/sub-assignment" }
        intent     = { scope = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000000" } }
        resolved   = { members = [{ reference_id = "member-a" }, { reference_id = "member-b" }], member_reference_ids = ["member-a", "member-b"] }
      }
    }
    exemptions = {
      unrelated_member = {
        request_mode                    = "create"
        assignment_id                   = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/sub-assignment"
        scope                           = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000000" }
        owner                           = "platform-team"
        reason                          = "Must not broaden member targeting"
        approval_reference              = "APR-MEMBER"
        category                        = "Mitigated"
        compensating_control            = "Manual review"
        expires_on                      = "2027-01-31T00:00:00Z"
        policy_definition_reference_ids = ["unrelated-member"]
      }
    }
  }

  expect_failures = [terraform_data.contract_guard]
}

run "reject_malformed_member_reference_collection" {
  command = plan

  variables {
    evaluation_time = "2026-09-15T00:00:00Z"
    assignments = {
      subscription = {
        assignment = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/sub-assignment" }
        intent     = { scope = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000000" } }
        resolved   = { members = [{ reference_id = "member-a" }], member_reference_ids = ["member-a"] }
      }
    }
    exemptions = {
      malformed = {
        request_mode                    = "create"
        assignment_id                   = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/sub-assignment"
        scope                           = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000000" }
        owner                           = "platform-team"
        reason                          = "Malformed targeting must fail closed"
        approval_reference              = "APR-MALFORMED"
        category                        = "Mitigated"
        compensating_control            = "Manual review"
        expires_on                      = "2027-01-31T00:00:00Z"
        policy_definition_reference_ids = "member-a"
      }
    }
  }

  expect_failures = [terraform_data.contract_guard]
}

run "block_unknown_assignment_membership" {
  command = plan

  variables {
    evaluation_time = "2026-09-15T00:00:00Z"
    exemptions = {
      unknown_assignment = {
        request_mode         = "create"
        assignment_id        = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/missing"
        scope                = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000000" }
        owner                = "platform-team"
        reason               = "The assignment is not in the resolved inventory"
        approval_reference   = "APR-UNKNOWN"
        category             = "Mitigated"
        compensating_control = "Manual review"
        expires_on           = "2027-01-31T00:00:00Z"
      }
    }
  }

  expect_failures = [terraform_data.contract_guard]
}
