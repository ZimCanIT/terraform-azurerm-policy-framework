mock_provider "azurerm" {
  override_during = plan

  mock_resource "azurerm_user_assigned_identity" {
    defaults = {
      id           = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/identity-rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/mock"
      principal_id = "11111111-2222-3333-4444-555555555555"
    }
  }
}

# assignment_bindings is the only wiring between this module and the assignments
# module, so these runs pin which assignments appear and the exact binding shape.

run "bindings_exist_only_for_assignments_that_require_an_identity" {
  command = plan

  variables {
    assignments = {
      needs_identity = {
        intent = {
          scope = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000001" }
        }
        resolved = {
          effective_effect = "DeployIfNotExists"
          list_fields = {
            role_definition_ids = ["/subscriptions/00000000-0000-0000-0000-000000000001/providers/Microsoft.Authorization/roleDefinitions/00000000-0000-0000-0000-000000000000"]
          }
          identity = {
            required            = true
            strategy            = "user_assigned"
            name_basis          = "needs-identity"
            location            = "westeurope"
            resource_group_name = "identity-rg"
            rationale           = "The resolved deployment operation requires a managed identity."
          }
          required_roles = [{
            role_definition_id = "/subscriptions/00000000-0000-0000-0000-000000000001/providers/Microsoft.Authorization/roleDefinitions/00000000-0000-0000-0000-000000000000"
            purpose            = "deploy resources"
            grant_scope        = "/subscriptions/00000000-0000-0000-0000-000000000001"
          }]
        }
      }
      audit = {
        intent = {
          scope = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000001" }
        }
        resolved = {
          effective_effect = "Audit"
          identity         = { required = false, strategy = "none" }
          list_fields      = { role_definition_ids = [] }
          required_roles   = []
        }
      }
    }
  }

  assert {
    condition     = length(output.assignment_bindings) == 1 && contains(keys(output.assignment_bindings), "needs_identity")
    error_message = "Only the assignment that requires an identity may appear in assignment_bindings."
  }

  assert {
    condition     = output.assignment_bindings["needs_identity"] == output.identity_rbac["needs_identity"].assignment_binding
    error_message = "assignment_bindings must carry each per-assignment binding unchanged."
  }

  assert {
    condition = (
      output.assignment_bindings["needs_identity"].assignment_key == "needs_identity" &&
      output.assignment_bindings["needs_identity"].identity_strategy == "user_assigned" &&
      output.assignment_bindings["needs_identity"].id == output.identity_rbac["needs_identity"].identity_id &&
      output.assignment_bindings["needs_identity"].principal_id == output.identity_rbac["needs_identity"].principal_id &&
      length(setsubtract(toset(keys(output.assignment_bindings["needs_identity"])), toset(["assignment_key", "id", "identity_id", "principal_id", "identity_strategy"]))) == 0
    )
    error_message = "A binding must hold only the fields the assignments identity_bindings input accepts, keyed by its own assignment key."
  }
}

run "no_bindings_when_no_assignment_requires_an_identity" {
  command = plan

  variables {
    assignments = {
      audit = {
        intent = {
          scope = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000001" }
        }
        resolved = {
          effective_effect = "Audit"
          identity         = { required = false, strategy = "none" }
          list_fields      = { role_definition_ids = [] }
          required_roles   = []
        }
      }
    }
  }

  assert {
    condition     = length(output.assignment_bindings) == 0
    error_message = "Verified identity absence must leave assignment_bindings empty rather than carry a null entry."
  }
}
