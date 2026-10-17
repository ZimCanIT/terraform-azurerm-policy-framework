resource "azurerm_user_assigned_identity" "this" {
  for_each = local.identity_entries

  location            = each.value.identity_location
  name                = each.value.identity_name
  resource_group_name = each.value.identity_resource_group_name

  lifecycle {
    precondition {
      condition     = each.value.identity_required && each.value.identity_name != null
      error_message = "Identity resource for assignment ${each.key} requires a resolved user_assigned identity decision."
    }
  }
}

resource "azurerm_role_assignment" "this" {
  for_each = local.role_grant_entries

  name                             = each.value.role_assignment_name
  scope                            = each.value.grant_scope
  role_definition_id               = each.value.role_definition_id
  principal_id                     = azurerm_user_assigned_identity.this[each.value.assignment_key].principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true

  lifecycle {
    precondition {
      # Fail closed: a blank or unparsable grant scope is never widened to the assignment scope.
      condition     = each.value.grant_scope_valid
      error_message = "grant_scope_valid: role grant ${each.key} for assignment ${each.value.assignment_key} must carry a non-blank management group, subscription, resource group or resource grant scope."
    }

    precondition {
      condition     = each.value.role_definition_valid
      error_message = "role_definition_valid: role grant ${each.key} for assignment ${each.value.assignment_key} must carry a full tenant-level or subscription-level role-definition resource ID ending in a role GUID, not ${each.value.role_definition_id}."
    }

    precondition {
      condition     = each.value.broad_role_excluded
      error_message = "broad_role_excluded: role grant ${each.key} for assignment ${each.value.assignment_key} must not grant Contributor or Owner in any role-definition ID form, not ${each.value.role_definition_id}."
    }

    precondition {
      condition     = each.value.purpose_supplied
      error_message = "purpose_supplied: role grant ${each.key} for assignment ${each.value.assignment_key} requires a non-blank resolved purpose."
    }

    precondition {
      condition     = each.value.role_declared
      error_message = "role_declared: role grant ${each.key} for assignment ${each.value.assignment_key} uses ${each.value.role_definition_id}, which is absent from the resolved candidate role list."
    }
  }
}
