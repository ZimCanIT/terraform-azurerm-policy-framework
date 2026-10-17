# Validation guard only: no input, so it never plans a change when the request
# set changes. The resolved assignment inventory itself is validated at the
# resolved_assignments variable, so only request-level rules are checked here.
resource "terraform_data" "exemption_contract_guard" {
  lifecycle {
    precondition {
      condition     = length(local.invalid_request_mode_keys) == 0
      error_message = "Exemption request_mode is invalid; use create, update, renew, expire, reject, blocked or disabled."
    }

    precondition {
      condition     = length(local.missing_governance_keys) == 0
      error_message = "Exemption requests must provide owner, reason, category, compensating_control and approval or ticket evidence; missing requests: ${join(", ", local.missing_governance_keys)}."
    }

    precondition {
      condition     = length(local.strict_governance_failures) == 0
      error_message = "Exemption governance strings must be non-blank, single-line and free of surrounding whitespace; failing requests and fields: ${join("; ", [for key, fields in local.strict_governance_failures : "${key}: ${join(", ", fields)}"])}."
    }

    precondition {
      condition     = length(local.invalid_expiry_keys) == 0
      error_message = "Exemption expires_on must be a valid RFC3339 timestamp."
    }

    precondition {
      condition     = length(local.invalid_active_expiry_keys) == 0
      error_message = "Create, update and renew requests require a future expires_on value; elapsed request keys: ${join(", ", local.invalid_active_expiry_keys)}. Use expire for explicit removal."
    }

    precondition {
      condition     = length(local.invalid_category_keys) == 0
      error_message = "Exemption category must be Waiver or Mitigated."
    }

    precondition {
      condition     = length(local.invalid_scope_type_keys) == 0
      error_message = "Exemption scope.type must be management_group, subscription, resource_group or resource."
    }

    precondition {
      condition     = length(local.invalid_scope_id_keys) == 0
      error_message = "Exemption scope.id must match the declared scope.type."
    }

    precondition {
      condition     = length(local.invalid_assignment_reference_keys) == 0
      error_message = "Exemption assignment_id must reference a policy assignment present in the resolved assignment inventory."
    }

    precondition {
      condition     = length(local.invalid_assignment_scope_keys) == 0
      error_message = "Exemption scope must be contained by the referenced assignment scope."
    }

    precondition {
      condition     = length(local.invalid_member_reference_keys) == 0
      error_message = "Exemption member references must belong to the referenced assignment."
    }

    precondition {
      condition     = length(local.invalid_reference_list_keys) == 0
      error_message = "policy_definition_reference_ids must be a unique list of non-blank single-line strings without surrounding whitespace when supplied; failing requests: ${join(", ", local.invalid_reference_list_keys)}."
    }

    precondition {
      condition     = length(local.invalid_selector_keys) == 0 && length(local.invalid_target_selectors_keys) == 0
      error_message = "selectors are unsupported for Azure Policy exemptions; use policy_definition_reference_ids for member targeting."
    }
  }
}

resource "azurerm_management_group_policy_exemption" "this" {
  for_each   = local.exemption_by_scope["management_group"]
  depends_on = [terraform_data.exemption_contract_guard]

  name                            = each.key
  management_group_id             = each.value.scope_id
  policy_assignment_id            = local.exemption_common_fields[each.key].policy_assignment_id
  exemption_category              = local.exemption_common_fields[each.key].exemption_category
  description                     = local.exemption_common_fields[each.key].description
  display_name                    = local.exemption_common_fields[each.key].display_name
  expires_on                      = local.exemption_common_fields[each.key].expires_on
  policy_definition_reference_ids = local.exemption_common_fields[each.key].policy_definition_reference_ids
  metadata                        = local.exemption_common_fields[each.key].metadata
}

resource "azurerm_subscription_policy_exemption" "this" {
  for_each   = local.exemption_by_scope["subscription"]
  depends_on = [terraform_data.exemption_contract_guard]

  name                            = each.key
  subscription_id                 = each.value.scope_id
  policy_assignment_id            = local.exemption_common_fields[each.key].policy_assignment_id
  exemption_category              = local.exemption_common_fields[each.key].exemption_category
  description                     = local.exemption_common_fields[each.key].description
  display_name                    = local.exemption_common_fields[each.key].display_name
  expires_on                      = local.exemption_common_fields[each.key].expires_on
  policy_definition_reference_ids = local.exemption_common_fields[each.key].policy_definition_reference_ids
  metadata                        = local.exemption_common_fields[each.key].metadata
}

resource "azurerm_resource_group_policy_exemption" "this" {
  for_each   = local.exemption_by_scope["resource_group"]
  depends_on = [terraform_data.exemption_contract_guard]

  name                            = each.key
  resource_group_id               = each.value.scope_id
  policy_assignment_id            = local.exemption_common_fields[each.key].policy_assignment_id
  exemption_category              = local.exemption_common_fields[each.key].exemption_category
  description                     = local.exemption_common_fields[each.key].description
  display_name                    = local.exemption_common_fields[each.key].display_name
  expires_on                      = local.exemption_common_fields[each.key].expires_on
  policy_definition_reference_ids = local.exemption_common_fields[each.key].policy_definition_reference_ids
  metadata                        = local.exemption_common_fields[each.key].metadata
}

resource "azurerm_resource_policy_exemption" "this" {
  for_each   = local.exemption_by_scope["resource"]
  depends_on = [terraform_data.exemption_contract_guard]

  name                            = each.key
  resource_id                     = each.value.scope_id
  policy_assignment_id            = local.exemption_common_fields[each.key].policy_assignment_id
  exemption_category              = local.exemption_common_fields[each.key].exemption_category
  description                     = local.exemption_common_fields[each.key].description
  display_name                    = local.exemption_common_fields[each.key].display_name
  expires_on                      = local.exemption_common_fields[each.key].expires_on
  policy_definition_reference_ids = local.exemption_common_fields[each.key].policy_definition_reference_ids
  metadata                        = local.exemption_common_fields[each.key].metadata
}
