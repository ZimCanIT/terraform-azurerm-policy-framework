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

# The assignments module attaches an identity that the role-grant state already
# created. These runs pin that behaviour with identity-required assignments and
# bindings shaped like the identity-rbac assignment_bindings output. The module
# declares no identity or role-assignment resource (the repository gate checks
# this), so a plan here contains policy assignments and guards only.

variables {
  assignments = {
    subscription_modify = {
      intent = {
        target = { reference_id = "modify-tags", policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c" }
        scope  = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000001" }
      }
      resolved = {
        policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c"
        parameter_values     = {}
        identity             = { required = true, strategy = "user_assigned", name_basis = "subscription_modify", location = "westeurope", resource_group_name = "rg-identities" }
        required_roles       = [{ role_definition_id = "/providers/Microsoft.Authorization/roleDefinitions/4a9ae827-6dc8-4573-8ac7-8239d42aa03f", purpose = "Tag Contributor" }]
        list_fields          = {}
      }
    }
    resource_group_deploy = {
      intent = {
        target = { reference_id = "deploy-diagnostics", policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c" }
        scope  = { type = "resource_group", id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/example" }
      }
      resolved = {
        policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c"
        parameter_values     = {}
        identity             = { required = true, strategy = "user_assigned", name_basis = "resource_group_deploy", location = "westeurope", resource_group_name = "rg-identities" }
        required_roles       = [{ role_definition_id = "/providers/Microsoft.Authorization/roleDefinitions/92aaf0da-9dab-42b6-94a3-d43ce8d16293", purpose = "Log Analytics Contributor" }]
        list_fields          = {}
      }
    }
    audit_only = {
      intent = {
        target = { reference_id = "audit-locations", policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c" }
        scope  = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000001" }
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

  identity_bindings = {
    subscription_modify = {
      assignment_key    = "subscription_modify"
      id                = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-identities/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-subscription-modify"
      identity_id       = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-identities/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-subscription-modify"
      principal_id      = "11111111-1111-1111-1111-111111111111"
      identity_strategy = "user_assigned"
    }
    resource_group_deploy = {
      assignment_key    = "resource_group_deploy"
      id                = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-identities/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-resource-group-deploy"
      identity_id       = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-identities/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-resource-group-deploy"
      principal_id      = "22222222-2222-2222-2222-222222222222"
      identity_strategy = "user_assigned"
    }
  }
}

run "attaches_the_supplied_identity_to_identity_requiring_assignments" {
  command = plan

  assert {
    condition = (
      azurerm_subscription_policy_assignment.this["subscription_modify"].identity[0].type == "UserAssigned" &&
      one(azurerm_subscription_policy_assignment.this["subscription_modify"].identity[0].identity_ids) == var.identity_bindings["subscription_modify"].id &&
      azurerm_resource_group_policy_assignment.this["resource_group_deploy"].identity[0].type == "UserAssigned" &&
      one(azurerm_resource_group_policy_assignment.this["resource_group_deploy"].identity[0].identity_ids) == var.identity_bindings["resource_group_deploy"].id
    )
    error_message = "Each identity-requiring assignment must carry a user-assigned identity block naming exactly the identity its binding supplies."
  }

  assert {
    condition = (
      azurerm_subscription_policy_assignment.this["subscription_modify"].location == "westeurope" &&
      azurerm_resource_group_policy_assignment.this["resource_group_deploy"].location == "westeurope"
    )
    error_message = "An assignment with an identity must take the location the resolver decided for that identity."
  }

  assert {
    condition = (
      length(azurerm_subscription_policy_assignment.this["audit_only"].identity) == 0 &&
      azurerm_subscription_policy_assignment.this["audit_only"].location == null
    )
    error_message = "An assignment whose resolver decision needs no identity must carry no identity block and no location."
  }

  assert {
    condition     = toset(keys(output.subscription_policy_assignment_ids)) == toset(["subscription_modify", "audit_only"]) && toset(keys(output.resource_group_policy_assignment_ids)) == toset(["resource_group_deploy"])
    error_message = "The plan must create one policy assignment per record. No identity or role grant belongs to this module."
  }
}

run "rejects_an_identity_requiring_assignment_without_a_binding" {
  command = plan

  variables {
    identity_bindings = {}
  }

  expect_failures = [terraform_data.contract_guard]
}

run "rejects_a_binding_for_an_assignment_that_needs_no_identity" {
  command = plan

  variables {
    identity_bindings = {
      subscription_modify = {
        assignment_key    = "subscription_modify"
        id                = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-identities/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-subscription-modify"
        identity_id       = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-identities/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-subscription-modify"
        principal_id      = "11111111-1111-1111-1111-111111111111"
        identity_strategy = "user_assigned"
      }
      resource_group_deploy = {
        assignment_key    = "resource_group_deploy"
        id                = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-identities/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-resource-group-deploy"
        identity_id       = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-identities/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-resource-group-deploy"
        principal_id      = "22222222-2222-2222-2222-222222222222"
        identity_strategy = "user_assigned"
      }
      audit_only = {
        assignment_key    = "audit_only"
        id                = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-identities/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-audit-only"
        identity_id       = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-identities/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-audit-only"
        principal_id      = "33333333-3333-3333-3333-333333333333"
        identity_strategy = "user_assigned"
      }
    }
  }

  expect_failures = [terraform_data.contract_guard]
}

run "rejects_a_binding_keyed_to_another_assignment" {
  command = plan

  variables {
    identity_bindings = {
      subscription_modify = {
        assignment_key    = "resource_group_deploy"
        id                = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-identities/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-resource-group-deploy"
        identity_id       = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-identities/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-resource-group-deploy"
        principal_id      = "22222222-2222-2222-2222-222222222222"
        identity_strategy = "user_assigned"
      }
    }
  }

  expect_failures = [var.identity_bindings]
}

run "rejects_a_user_assigned_binding_without_a_principal" {
  command = plan

  variables {
    identity_bindings = {
      subscription_modify = {
        assignment_key    = "subscription_modify"
        id                = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-identities/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-subscription-modify"
        identity_id       = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-identities/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-subscription-modify"
        principal_id      = null
        identity_strategy = "user_assigned"
      }
    }
  }

  expect_failures = [var.identity_bindings]
}
