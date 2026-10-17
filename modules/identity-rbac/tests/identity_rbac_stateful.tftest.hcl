mock_provider "azurerm" {}

run "identity_replacement_initial_state" {
  command   = apply
  state_key = "identity-replacement"

  variables {
    assignments = {
      stateful = {
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
            name_basis          = "stateful-initial"
            location            = "westeurope"
            resource_group_name = "identity-rg"
          }
          list_fields = {
            role_definition_ids = ["/providers/Microsoft.Authorization/roleDefinitions/11111111-1111-1111-1111-111111111111"]
          }
          required_roles = [{
            role_definition_id = "/providers/Microsoft.Authorization/roleDefinitions/11111111-1111-1111-1111-111111111111"
            purpose            = "stateful role"
            grant_scope        = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/role-scope-a"
          }]
        }
      }
    }
  }

  assert {
    condition     = output.identity_rbac["stateful"].identity_id != null && length(output.identity_rbac["stateful"].role_grants) == 1
    error_message = "The initial test state must contain one mocked identity and one role grant."
  }
}

run "identity_name_change_plans_new_identity_name" {
  command   = plan
  state_key = "identity-replacement"

  variables {
    assignments = {
      stateful = {
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
            name_basis          = "stateful-renamed"
            location            = "westeurope"
            resource_group_name = "identity-rg"
          }
          list_fields = {
            role_definition_ids = ["/providers/Microsoft.Authorization/roleDefinitions/11111111-1111-1111-1111-111111111111"]
          }
          required_roles = [{
            role_definition_id = "/providers/Microsoft.Authorization/roleDefinitions/11111111-1111-1111-1111-111111111111"
            purpose            = "stateful role"
            grant_scope        = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/role-scope-a"
          }]
        }
      }
    }
  }

  assert {
    condition     = output.identity_rbac["stateful"].identity_name != run.identity_replacement_initial_state.identity_rbac["stateful"].identity_name
    error_message = "Changing identity name_basis must produce a distinct deterministic identity name."
  }

  assert {
    condition     = output.identity_rbac["stateful"].replacement_impact.grant_addresses == run.identity_replacement_initial_state.identity_rbac["stateful"].replacement_impact.grant_addresses
    error_message = "Changing only the identity name must leave stable role-grant addresses unchanged."
  }
}

run "grant_scope_change_plans_new_grant_address" {
  command   = plan
  state_key = "identity-replacement"

  variables {
    assignments = {
      stateful = {
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
            name_basis          = "stateful-initial"
            location            = "westeurope"
            resource_group_name = "identity-rg"
          }
          list_fields = {
            role_definition_ids = ["/providers/Microsoft.Authorization/roleDefinitions/11111111-1111-1111-1111-111111111111"]
          }
          required_roles = [{
            role_definition_id = "/providers/Microsoft.Authorization/roleDefinitions/11111111-1111-1111-1111-111111111111"
            purpose            = "stateful role"
            grant_scope        = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/role-scope-b"
          }]
        }
      }
    }
  }

  assert {
    condition     = output.identity_rbac["stateful"].replacement_impact.grant_addresses != run.identity_replacement_initial_state.identity_rbac["stateful"].replacement_impact.grant_addresses
    error_message = "Changing the explicit grant scope must replace its stable grant address."
  }
}

run "strategy_change_to_none_plans_resource_removal" {
  command   = plan
  state_key = "identity-replacement"

  variables {
    assignments = {
      stateful = {
        intent = {
          scope = {
            type = "subscription"
            id   = "/subscriptions/00000000-0000-0000-0000-000000000001"
          }
        }
        resolved = {
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
    condition     = output.identity_rbac["stateful"].identity_required == false && output.identity_rbac["stateful"].identity_id == null && output.identity_rbac["stateful"].role_grants == []
    error_message = "Changing from user_assigned to none must plan removal of the identity and identity-only grants."
  }
}

run "purpose_change_preserves_grant_address" {
  command   = plan
  state_key = "identity-replacement"

  variables {
    assignments = {
      stateful = {
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
            name_basis          = "stateful-initial"
            location            = "westeurope"
            resource_group_name = "identity-rg"
          }
          list_fields = {
            role_definition_ids = ["/providers/Microsoft.Authorization/roleDefinitions/11111111-1111-1111-1111-111111111111"]
          }
          required_roles = [{
            role_definition_id = "/providers/Microsoft.Authorization/roleDefinitions/11111111-1111-1111-1111-111111111111"
            purpose            = "updated descriptive purpose"
            grant_scope        = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/role-scope-a"
          }]
        }
      }
    }
  }

  assert {
    condition     = output.identity_rbac["stateful"].role_grants[0].purpose == "updated descriptive purpose"
    error_message = "Purpose changes must appear in review output."
  }

  assert {
    condition     = output.identity_rbac["stateful"].replacement_impact.grant_addresses == run.identity_replacement_initial_state.identity_rbac["stateful"].replacement_impact.grant_addresses
    error_message = "Changing only descriptive purpose must not change the Terraform grant address."
  }
}
