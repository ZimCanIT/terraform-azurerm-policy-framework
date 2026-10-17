mock_provider "azurerm" {
  override_during = plan

  mock_resource "azurerm_management_group_policy_assignment" {
    defaults = {
      id = "/providers/Microsoft.Management/managementGroups/example/providers/Microsoft.Authorization/policyAssignments/mock-mg"
    }
  }

  mock_resource "azurerm_subscription_policy_assignment" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000001/providers/Microsoft.Authorization/policyAssignments/mock-sub"
    }
  }

  mock_resource "azurerm_resource_group_policy_assignment" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/example/providers/Microsoft.Authorization/policyAssignments/mock-rg"
    }
  }

  mock_resource "azurerm_resource_policy_assignment" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/example/providers/Microsoft.Storage/storageAccounts/example/providers/Microsoft.Authorization/policyAssignments/mock-resource"
    }
  }
}

# resolved_assignments is the only wiring from this module to the operations
# module. These runs pin the binding it adds and the fields it must not touch.

run "hands_back_records_with_the_created_assignment_binding" {
  command = plan

  variables {
    assignments = {
      with_binding = {
        intent = {
          target = { reference_id = "sub-ref", policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c" }
          scope  = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000001" }
        }
        resolved = {
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c"
          parameter_values     = {}
          identity             = { required = false, strategy = "none" }
          required_roles       = []
          list_fields          = {}
        }
        assignment = { id = null, name = null }
      }
      without_binding = {
        intent = {
          target = { reference_id = "rg-ref", policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c" }
          scope  = { type = "resource_group", id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/example" }
        }
        resolved = {
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c"
          parameter_values     = {}
          identity             = { required = false, strategy = "none" }
          required_roles       = []
          list_fields          = {}
        }
      }
    }
  }

  assert {
    condition     = toset(keys(output.resolved_assignments)) == toset(keys(var.assignments))
    error_message = "Every received record must come back under its own assignment key."
  }

  assert {
    condition = (
      output.resolved_assignments["with_binding"].assignment.id == "/subscriptions/00000000-0000-0000-0000-000000000001/providers/Microsoft.Authorization/policyAssignments/mock-sub" &&
      output.resolved_assignments["without_binding"].assignment.id == "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/example/providers/Microsoft.Authorization/policyAssignments/mock-rg"
    )
    error_message = "The binding must carry the Azure ID of the assignment this module created, whether or not the received record already had a binding."
  }

  assert {
    condition = alltrue([
      for key, record in output.resolved_assignments :
      record.assignment.name == output.assignment_names[key] && record.assignment == output.assignments[key].assignment
    ])
    error_message = "The binding name must be the deterministic assignment name, and the binding must equal the one in the assignments output."
  }

  assert {
    condition = alltrue([
      for key, record in output.resolved_assignments :
      record.intent == var.assignments[key].intent && record.resolved == var.assignments[key].resolved
    ])
    error_message = "Only the assignment binding may change. The intent and the resolver decisions must come back unchanged."
  }
}
