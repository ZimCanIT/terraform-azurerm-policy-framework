mock_provider "azurerm" {}


run "aggregated_mixed_initiative_roles_flow_to_grants" {
  command = plan

  variables {
    assignments = {
      mixed_initiative = {
        intent = {
          scope = {
            type = "subscription"
            id   = "/subscriptions/00000000-0000-0000-0000-000000000001"
          }
        }
        resolved = {
          effective_effect = "Modify"
          members = [
            {
              reference_id      = "audit-member"
              effective_effect  = "Audit"
              identity_required = false
              required_roles    = []
              list_fields = {
                role_definition_ids = []
              }
            },
            {
              reference_id      = "modify-member"
              effective_effect  = "Modify"
              identity_required = true
              required_roles = [
                {
                  role_definition_id = "/subscriptions/00000000-0000-0000-0000-000000000001/providers/Microsoft.Authorization/roleDefinitions/11111111-1111-1111-1111-111111111111"
                  purpose            = "modify member deployment"
                  grant_scope        = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/target"
                },
                {
                  role_definition_id = "/subscriptions/00000000-0000-0000-0000-000000000001/providers/Microsoft.Authorization/roleDefinitions/22222222-2222-2222-2222-222222222222"
                  purpose            = "modify member tagging"
                  grant_scope        = "/subscriptions/00000000-0000-0000-0000-000000000001"
                },
              ]
              list_fields = {
                role_definition_ids = [
                  "/subscriptions/00000000-0000-0000-0000-000000000001/providers/Microsoft.Authorization/roleDefinitions/11111111-1111-1111-1111-111111111111",
                  "/subscriptions/00000000-0000-0000-0000-000000000001/providers/Microsoft.Authorization/roleDefinitions/22222222-2222-2222-2222-222222222222",
                ]
              }
            },
          ]
          identity = {
            required            = true
            strategy            = "user_assigned"
            name_basis          = "mixed-initiative"
            location            = "westeurope"
            resource_group_name = "identity-rg"
            rationale           = "Union of active initiative member identity requirements."
          }
          list_fields = {
            role_definition_ids = [
              "/subscriptions/00000000-0000-0000-0000-000000000001/providers/Microsoft.Authorization/roleDefinitions/11111111-1111-1111-1111-111111111111",
              "/subscriptions/00000000-0000-0000-0000-000000000001/providers/Microsoft.Authorization/roleDefinitions/22222222-2222-2222-2222-222222222222",
            ]
          }
          required_roles = [
            {
              role_definition_id = "/subscriptions/00000000-0000-0000-0000-000000000001/providers/Microsoft.Authorization/roleDefinitions/11111111-1111-1111-1111-111111111111"
              purpose            = "modify member deployment"
              grant_scope        = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/target"
            },
            {
              role_definition_id = "/subscriptions/00000000-0000-0000-0000-000000000001/providers/Microsoft.Authorization/roleDefinitions/22222222-2222-2222-2222-222222222222"
              purpose            = "modify member tagging"
              grant_scope        = "/subscriptions/00000000-0000-0000-0000-000000000001"
            },
          ]
        }
      }
    }
  }

  assert {
    condition     = length(output.identity_rbac["mixed_initiative"].role_grants) == 2
    error_message = "Identity-RBAC must emit every role in the resolver's union of initiative member requirements."
  }

  assert {
    condition     = toset([for grant in output.identity_rbac["mixed_initiative"].role_grants : grant.role_definition_id]) == toset([for role in var.assignments["mixed_initiative"].resolved.required_roles : role.role_definition_id])
    error_message = "All aggregated initiative role definitions must pass through without omission or substitution."
  }

  assert {
    condition     = output.identity_rbac["mixed_initiative"].role_grants[0].purpose == "modify member deployment" && output.identity_rbac["mixed_initiative"].role_grants[0].grant_scope == "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/target"
    error_message = "Aggregated role purposes and explicit narrower grant scopes must be preserved."
  }

  assert {
    condition     = output.identity_rbac["mixed_initiative"].identity_required && output.identity_rbac["mixed_initiative"].identity_name != null && length(output.identity_rbac["mixed_initiative"].identity_name) == 24
    error_message = "A required whole-initiative identity must retain the deterministic name derived from the assignment key."
  }

  assert {
    condition     = output.identity_rbac["mixed_initiative"].members == var.assignments["mixed_initiative"].resolved.members
    error_message = "Identity-RBAC must retain the resolver's per-member effect, eligibility and role provenance without selecting a single initiative member."
  }
}

run "identity_free_assignment_suppresses_resources" {
  command = plan

  variables {
    assignments = {
      audit = {
        intent = {
          scope = {
            type = "subscription"
            id   = "/subscriptions/00000000-0000-0000-0000-000000000001"
          }
        }
        resolved = {
          effective_effect = "Audit"
          identity = {
            required = false
            strategy = "none"
          }
          list_fields = {
            role_definition_ids = []
          }
          required_roles = []
        }
      }
    }
  }

  assert {
    condition     = output.identity_rbac["audit"].identity_name == null && output.identity_rbac["audit"].assignment_binding == null && output.identity_rbac["audit"].role_grants == []
    error_message = "Verified identity absence must suppress identity bindings and role grants."
  }
}

run "four_grant_scopes_include_distinct_assignment_scope" {
  command = plan

  variables {
    assignments = {
      scoped_identity = {
        intent = {
          scope = {
            type = "resource_group"
            id   = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/assignment-rg"
          }
        }
        resolved = {
          identity = {
            required            = true
            strategy            = "user_assigned"
            name_basis          = "scoped-identity"
            location            = "westeurope"
            resource_group_name = "identity-rg"
          }
          list_fields = {
            role_definition_ids = [
              "/providers/Microsoft.Authorization/roleDefinitions/11111111-1111-1111-1111-111111111111",
              "/subscriptions/00000000-0000-0000-0000-000000000001/providers/Microsoft.Authorization/roleDefinitions/22222222-2222-2222-2222-222222222222",
              "/subscriptions/00000000-0000-0000-0000-000000000001/providers/Microsoft.Authorization/roleDefinitions/33333333-3333-3333-3333-333333333333",
              "/subscriptions/00000000-0000-0000-0000-000000000001/providers/Microsoft.Authorization/roleDefinitions/44444444-4444-4444-4444-444444444444",
            ]
          }
          required_roles = [
            {
              role_definition_id = "/providers/Microsoft.Authorization/roleDefinitions/11111111-1111-1111-1111-111111111111"
              purpose            = "management-group governance"
              grant_scope        = "/providers/Microsoft.Management/managementGroups/platform"
            },
            {
              role_definition_id = "/subscriptions/00000000-0000-0000-0000-000000000001/providers/Microsoft.Authorization/roleDefinitions/22222222-2222-2222-2222-222222222222"
              purpose            = "subscription baseline"
              grant_scope        = "/subscriptions/00000000-0000-0000-0000-000000000001"
            },
            {
              role_definition_id = "/subscriptions/00000000-0000-0000-0000-000000000001/providers/Microsoft.Authorization/roleDefinitions/33333333-3333-3333-3333-333333333333"
              purpose            = "resource-group deployment"
              grant_scope        = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/target-rg"
            },
            {
              role_definition_id = "/subscriptions/00000000-0000-0000-0000-000000000001/providers/Microsoft.Authorization/roleDefinitions/44444444-4444-4444-4444-444444444444"
              purpose            = "single resource configuration"
              grant_scope        = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/target-rg/providers/Microsoft.Storage/storageAccounts/target"
            },
          ]
        }
      }
    }
  }

  assert {
    condition = toset([for grant in output.identity_rbac["scoped_identity"].role_grants : grant.grant_scope]) == toset([
      "/providers/Microsoft.Management/managementGroups/platform",
      "/subscriptions/00000000-0000-0000-0000-000000000001",
      "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/target-rg",
      "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/target-rg/providers/Microsoft.Storage/storageAccounts/target",
    ])
    error_message = "Identity-RBAC must preserve management-group, subscription, resource-group and named-resource grant scopes."
  }

  assert {
    condition     = alltrue([for grant in output.identity_rbac["scoped_identity"].role_grants : grant.grant_scope != var.assignments["scoped_identity"].intent.scope.id])
    error_message = "The explicit grant scopes may differ from the assignment resource-group scope and must not be widened or replaced."
  }
}

run "source_file_shaped_assignment_is_rejected" {
  command         = plan
  expect_failures = [var.assignments]

  variables {
    assignments = {
      source_shaped = {
        source_file = "policies/storage/audit.json"
        resolved    = {}
      }
    }
  }
}

run "unresolved_assignment_is_rejected" {
  command         = plan
  expect_failures = [var.assignments]

  variables {
    assignments = {
      unresolved = {
        intent = {
          scope = {
            type = "subscription"
            id   = "/subscriptions/00000000-0000-0000-0000-000000000001"
          }
        }
        resolved = {
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/not-resolved"
        }
      }
    }
  }
}

run "deployifnotexists_without_roles_is_rejected" {
  command         = plan
  expect_failures = [var.assignments]

  variables {
    assignments = {
      deploy_without_roles = {
        intent = {
          scope = {
            type = "subscription"
            id   = "/subscriptions/00000000-0000-0000-0000-000000000001"
          }
        }
        resolved = {
          effective_effect = "DeployIfNotExists"
          identity = {
            required            = true
            strategy            = "user_assigned"
            name_basis          = "deploy-without-roles"
            location            = "westeurope"
            resource_group_name = "identity-rg"
          }
          list_fields = {
            role_definition_ids = []
          }
          required_roles = []
        }
      }
    }
  }
}

run "unknown_role_requirement_does_not_become_no_identity" {
  command         = plan
  expect_failures = [var.assignments]

  variables {
    assignments = {
      unknown_roles = {
        intent = {
          scope = {
            type = "subscription"
            id   = "/subscriptions/00000000-0000-0000-0000-000000000001"
          }
        }
        resolved = {
          identity = {
            required            = true
            strategy            = "user_assigned"
            name_basis          = "unknown-roles"
            location            = "westeurope"
            resource_group_name = "identity-rg"
          }
          list_fields = {
            role_definition_ids = null
          }
          required_roles = null
        }
      }
    }
  }
}

# Container boundary diagnostics: null and scalar inputs must fail at the variable boundary with the contract message.
run "null_container" {
  command = plan
  variables { assignments = null }
  expect_failures = [var.assignments]
}

run "string_container" {
  command = plan
  variables { assignments = "invalid" }
  expect_failures = [var.assignments]
}

run "number_container" {
  command = plan
  variables { assignments = 42 }
  expect_failures = [var.assignments]
}

run "bool_container" {
  command = plan
  variables { assignments = true }
  expect_failures = [var.assignments]
}

run "list_container" {
  command = plan
  variables { assignments = [null] }
  expect_failures = [var.assignments]
}

run "null_record" {
  command = plan
  variables { assignments = { broken = null } }
  expect_failures = [var.assignments]
}

run "empty_record" {
  command = plan
  variables { assignments = { broken = {} } }
  expect_failures = [var.assignments]
}

run "null_intent" {
  command = plan
  variables { assignments = { broken = { intent = null, resolved = null } } }
  expect_failures = [var.assignments]
}

# Grant-level negatives (moved from the former identity-rbac contract root):
# structural rejections fail the assignments variable validation, grant-level
# rejections fail the named preconditions on the deterministic grant instance.
# Unknown and empty role inventories are covered by the runs above.

run "identity_rbac_rejects_malformed_identity_decision" {
  command = plan

  variables {
    assignments = {
      modify = {
        intent = {
          scope = {
            type = "management_group"
            id   = "/providers/Microsoft.Management/managementGroups/example"
          }
        }
        resolved = {
          effective_effect = "Modify"
          identity = {
            required            = true
            strategy            = "system_assigned"
            name_basis          = "modify"
            location            = "westeurope"
            resource_group_name = "identity-rg"
          }
          list_fields = {
            role_definition_ids = ["/providers/Microsoft.Authorization/roleDefinitions/00000000-0000-0000-0000-000000000000"]
          }
          required_roles = [{
            role_definition_id = "/providers/Microsoft.Authorization/roleDefinitions/00000000-0000-0000-0000-000000000000"
            purpose            = "modify policy target"
            grant_scope        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/target"
          }]
        }
      }
    }
  }

  expect_failures = [var.assignments]
}

run "identity_rbac_rejects_malformed_scope" {
  command = plan

  variables {
    assignments = {
      modify = {
        intent = {
          scope = {
            type = "management_group"
            id   = "not-an-azure-scope"
          }
        }
        resolved = {
          effective_effect = "Modify"
          identity = {
            required            = true
            strategy            = "user_assigned"
            name_basis          = "modify"
            location            = "westeurope"
            resource_group_name = "identity-rg"
          }
          list_fields = {
            role_definition_ids = ["/providers/Microsoft.Authorization/roleDefinitions/00000000-0000-0000-0000-000000000000"]
          }
          required_roles = [{
            role_definition_id = "/providers/Microsoft.Authorization/roleDefinitions/00000000-0000-0000-0000-000000000000"
            purpose            = "modify policy target"
            grant_scope        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/target"
          }]
        }
      }
    }
  }

  expect_failures = [var.assignments]
}

run "identity_rbac_rejects_blank_grant_scope" {
  command = plan

  variables {
    assignments = {
      modify = {
        intent = {
          scope = {
            type = "management_group"
            id   = "/providers/Microsoft.Management/managementGroups/example"
          }
        }
        resolved = {
          effective_effect = "Modify"
          identity = {
            required            = true
            strategy            = "user_assigned"
            name_basis          = "modify"
            location            = "westeurope"
            resource_group_name = "identity-rg"
          }
          list_fields = {
            role_definition_ids = ["/providers/Microsoft.Authorization/roleDefinitions/00000000-0000-0000-0000-000000000000"]
          }
          required_roles = [{
            role_definition_id = "/providers/Microsoft.Authorization/roleDefinitions/00000000-0000-0000-0000-000000000000"
            purpose            = "modify policy target"
            grant_scope        = ""
          }]
        }
      }
    }
  }

  expect_failures = [azurerm_role_assignment.this["modify|ab70a30a360542a10a208070d73992fba7e73e7d"]]
}

run "identity_rbac_rejects_unnamed_resource_grant_scope" {
  command = plan

  variables {
    assignments = {
      modify = {
        intent = {
          scope = {
            type = "management_group"
            id   = "/providers/Microsoft.Management/managementGroups/example"
          }
        }
        resolved = {
          effective_effect = "Modify"
          identity = {
            required            = true
            strategy            = "user_assigned"
            name_basis          = "modify"
            location            = "westeurope"
            resource_group_name = "identity-rg"
          }
          list_fields = {
            role_definition_ids = ["/providers/Microsoft.Authorization/roleDefinitions/00000000-0000-0000-0000-000000000000"]
          }
          required_roles = [{
            role_definition_id = "/providers/Microsoft.Authorization/roleDefinitions/00000000-0000-0000-0000-000000000000"
            purpose            = "modify policy target"
            grant_scope        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/target/providers/Microsoft.Storage/storageAccounts"
          }]
        }
      }
    }
  }

  expect_failures = [azurerm_role_assignment.this["modify|9f66277813d2f8d08b8bb0daa1764c4c29fcbc60"]]
}

run "identity_rbac_rejects_absent_grant_scope_field" {
  command = plan

  variables {
    assignments = {
      modify = {
        intent = {
          scope = {
            type = "management_group"
            id   = "/providers/Microsoft.Management/managementGroups/example"
          }
        }
        resolved = {
          effective_effect = "Modify"
          identity = {
            required            = true
            strategy            = "user_assigned"
            name_basis          = "modify"
            location            = "westeurope"
            resource_group_name = "identity-rg"
          }
          list_fields = {
            role_definition_ids = ["/providers/Microsoft.Authorization/roleDefinitions/00000000-0000-0000-0000-000000000000"]
          }
          required_roles = [{
            role_definition_id = "/providers/Microsoft.Authorization/roleDefinitions/00000000-0000-0000-0000-000000000000"
            purpose            = "modify policy target"
          }]
        }
      }
    }
  }

  expect_failures = [azurerm_role_assignment.this["modify|ab70a30a360542a10a208070d73992fba7e73e7d"]]
}

run "identity_rbac_rejects_invalid_role_guid" {
  command = plan

  variables {
    assignments = {
      modify = {
        intent = {
          scope = {
            type = "management_group"
            id   = "/providers/Microsoft.Management/managementGroups/example"
          }
        }
        resolved = {
          effective_effect = "Modify"
          identity = {
            required            = true
            strategy            = "user_assigned"
            name_basis          = "modify"
            location            = "westeurope"
            resource_group_name = "identity-rg"
          }
          list_fields = {
            role_definition_ids = ["/providers/Microsoft.Authorization/roleDefinitions/00000000-0000-0000-0000-000000000000"]
          }
          required_roles = [{
            role_definition_id = "/providers/Microsoft.Authorization/roleDefinitions/not-a-guid"
            purpose            = "modify policy target"
            grant_scope        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/target"
          }]
        }
      }
    }
  }

  expect_failures = [azurerm_role_assignment.this["modify|7539e90d41e6aa7f5aaf9e1e476161fc6c7a17f5"]]
}

run "identity_rbac_rejects_missing_purpose" {
  command = plan

  variables {
    assignments = {
      modify = {
        intent = {
          scope = {
            type = "management_group"
            id   = "/providers/Microsoft.Management/managementGroups/example"
          }
        }
        resolved = {
          effective_effect = "Modify"
          identity = {
            required            = true
            strategy            = "user_assigned"
            name_basis          = "modify"
            location            = "westeurope"
            resource_group_name = "identity-rg"
          }
          list_fields = {
            role_definition_ids = ["/providers/Microsoft.Authorization/roleDefinitions/00000000-0000-0000-0000-000000000000"]
          }
          required_roles = [{
            role_definition_id = "/providers/Microsoft.Authorization/roleDefinitions/00000000-0000-0000-0000-000000000000"
            purpose            = ""
            grant_scope        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/target"
          }]
        }
      }
    }
  }

  expect_failures = [azurerm_role_assignment.this["modify|596cdc746807eacc3391026edbb3ed3a8925a90b"]]
}

run "identity_rbac_rejects_undeclared_role" {
  command = plan

  variables {
    assignments = {
      modify = {
        intent = {
          scope = {
            type = "management_group"
            id   = "/providers/Microsoft.Management/managementGroups/example"
          }
        }
        resolved = {
          effective_effect = "Modify"
          identity = {
            required            = true
            strategy            = "user_assigned"
            name_basis          = "modify"
            location            = "westeurope"
            resource_group_name = "identity-rg"
          }
          list_fields = {
            role_definition_ids = ["/providers/Microsoft.Authorization/roleDefinitions/00000000-0000-0000-0000-000000000000"]
          }
          required_roles = [{
            role_definition_id = "/providers/Microsoft.Authorization/roleDefinitions/22222222-2222-2222-2222-222222222222"
            purpose            = "modify policy target"
            grant_scope        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/target"
          }]
        }
      }
    }
  }

  expect_failures = [azurerm_role_assignment.this["modify|5f633f00448a26ab8341c4877f3e143163ec6e1e"]]
}

run "identity_rbac_rejects_contributor_tenant_form" {
  command = plan

  variables {
    assignments = {
      modify = {
        intent = {
          scope = {
            type = "management_group"
            id   = "/providers/Microsoft.Management/managementGroups/example"
          }
        }
        resolved = {
          effective_effect = "Modify"
          identity = {
            required            = true
            strategy            = "user_assigned"
            name_basis          = "modify"
            location            = "westeurope"
            resource_group_name = "identity-rg"
          }
          list_fields = {
            role_definition_ids = ["/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"]
          }
          required_roles = [{
            role_definition_id = "/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"
            purpose            = "modify policy target"
            grant_scope        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/target"
          }]
        }
      }
    }
  }

  expect_failures = [azurerm_role_assignment.this["modify|80b07495805dcfac8fc3b2d016f3626cc56f01b0"]]
}

run "identity_rbac_rejects_contributor_subscription_prefixed_form" {
  command = plan

  variables {
    assignments = {
      modify = {
        intent = {
          scope = {
            type = "management_group"
            id   = "/providers/Microsoft.Management/managementGroups/example"
          }
        }
        resolved = {
          effective_effect = "Modify"
          identity = {
            required            = true
            strategy            = "user_assigned"
            name_basis          = "modify"
            location            = "westeurope"
            resource_group_name = "identity-rg"
          }
          list_fields = {
            role_definition_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"]
          }
          required_roles = [{
            role_definition_id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"
            purpose            = "modify policy target"
            grant_scope        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/target"
          }]
        }
      }
    }
  }

  expect_failures = [azurerm_role_assignment.this["modify|034cd2609c0fcf3077ecce229109a2d3e4c4dd6c"]]
}
