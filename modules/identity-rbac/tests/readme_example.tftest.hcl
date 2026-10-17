mock_provider "azurerm" {}

# Keep these inputs identical to the public README example.
run "readme_identity_example" {
  command = plan

  variables {
    assignments = {
      deploy_storage = {
        intent = {
          scope = {
            type = "resource_group"
            id   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example-rg"
          }
        }
        resolved = {
          effective_effect = "DeployIfNotExists"
          list_fields = {
            role_definition_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/00000000-0000-0000-0000-000000000000"]
          }
          identity = {
            required            = true
            strategy            = "user_assigned"
            name_basis          = "storage-deploy"
            location            = "westeurope"
            resource_group_name = "identity-rg"
            rationale           = "The resolved deployment operation requires a managed identity."
          }
          required_roles = [{
            role_definition_id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/00000000-0000-0000-0000-000000000000"
            purpose            = "deploy resources"
            grant_scope        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example-rg"
          }]
        }
      }
    }
  }

  assert {
    condition = (
      length(azurerm_user_assigned_identity.this) == 1 &&
      azurerm_user_assigned_identity.this["deploy_storage"].location == "westeurope" &&
      azurerm_user_assigned_identity.this["deploy_storage"].resource_group_name == "identity-rg"
    )
    error_message = "The README example must plan one identity in the documented location and resource group."
  }

  assert {
    condition = length(azurerm_role_assignment.this) == 1 && alltrue([
      for grant in azurerm_role_assignment.this :
      grant.scope == var.assignments.deploy_storage.intent.scope.id &&
      grant.role_definition_id == var.assignments.deploy_storage.resolved.list_fields.role_definition_ids[0]
    ])
    error_message = "The README example must plan only its declared role at the documented grant scope."
  }

  assert {
    condition = (
      output.identity_rbac["deploy_storage"].identity_required &&
      length(output.identity_rbac["deploy_storage"].role_grants) == 1 &&
      output.identity_rbac["deploy_storage"].role_grants[0].purpose == "deploy resources"
    )
    error_message = "The README example must preserve the required identity and grant purpose in public outputs."
  }
}
