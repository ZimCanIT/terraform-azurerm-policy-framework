resource "terraform_data" "contract_guard" {
  for_each = local.assignment_entries

  input = each.key

  lifecycle {
    precondition {
      condition     = local.parameters_valid[each.key]
      error_message = "Assignment ${each.key} has invalid parameters: unknown keys [${join(", ", sort(tolist(local.parameter_unknown_keys[each.key])))}], missing required values [${join(", ", local.parameter_missing_required[each.key])}], malformed or unsupported schema entries [${join(", ", local.parameter_schema_type_offenders[each.key])}], type mismatches [${join(", ", local.parameter_type_offenders[each.key])}], or values outside the schema allowedValues."
    }
    precondition {
      condition     = local.effect_enforceability_valid[each.key]
      error_message = "Assignment ${each.key} (policy definition ${each.value.target.policy_definition_id}) resolves effective effect ${coalesce(each.value.resolved_effect, "unknown")} that no deployment mechanism enforces; the effect must equal the definition default effect, be projected by an effect override that addresses the definition, or be carried by an effect assignment parameter."
    }
    precondition {
      condition     = local.effect_values_supported[each.key]
      error_message = "Assignment ${each.key} requests an effective effect outside the known supported_effects declarations for its target or initiative members."
    }
    precondition {
      condition     = !local.direct_version_unenforceable[each.key]
      error_message = "Assignment ${each.key} (policy definition ${each.value.target.policy_definition_id}) requests selected version ${coalesce(each.value.resolved_version, "unknown")}, but AzureRM policy assignment resources cannot carry a definitionVersion override. A direct target cannot guarantee that version; deploy the version through an initiative or leave it unselected."
    }
    precondition {
      condition     = local.control_declarations_valid[each.key]
      error_message = "Assignment ${each.key} contains an unsupported, malformed or ambiguous selector, override or non-compliance message."
    }
    precondition {
      condition     = local.resolved_control_support_valid[each.key]
      error_message = "Assignment ${each.key} requests a selector, override or non-compliance message not declared by the resolved capability contract."
    }
    precondition {
      condition     = local.provider_limits_valid[each.key]
      error_message = "Assignment ${each.key} exceeds an Azure Policy assignment limit: exclusions 400, overrides 10, or selector values 50 per selector."
    }

    precondition {
      condition     = try(each.value.identity.required, false) == false || (try(each.value.identity.strategy, null) == "user_assigned" && try(each.value.identity_binding.assignment_key, null) == each.key && try(each.value.identity_binding.identity_strategy, null) == "user_assigned" && each.value.identity_binding != null && each.value.identity_id != null)
      error_message = "Assignment ${each.key} requires the resolver-owned user-assigned identity binding for the same assignment key."
    }
    precondition {
      condition     = try(each.value.identity.required, false) == true || (each.value.identity_binding == null && each.value.identity_id == null)
      error_message = "Assignment ${each.key} cannot attach an identity when the resolver says identity is not required."
    }
  }
}

# Four AzureRM resource types, one per scope. The blocks stay explicit because
# the scope argument differs; every other argument reads the shared
# projections in locals.tf.
resource "azurerm_management_group_policy_assignment" "this" {
  for_each   = local.by_scope["management_group"]
  depends_on = [terraform_data.contract_guard]

  name                 = local.assignment_names[each.key]
  management_group_id  = each.value.scope.id
  policy_definition_id = each.value.target.policy_definition_id
  display_name         = each.value.target.reference_id
  description          = local.provider_arguments[each.key].description
  enforce              = local.provider_arguments[each.key].enforce
  parameters           = local.parameter_payloads[each.key]
  not_scopes           = each.value.exclusions
  metadata             = local.provider_arguments[each.key].metadata
  location             = local.provider_arguments[each.key].location

  dynamic "identity" {
    for_each = each.value.identity_binding == null ? [] : [each.value.identity_binding]
    content {
      type         = "UserAssigned"
      identity_ids = [each.value.identity_id]
    }
  }
  dynamic "non_compliance_message" {
    for_each = local.dynamic_payloads[each.key].non_compliance_messages
    content {
      content                        = non_compliance_message.value.content
      policy_definition_reference_id = non_compliance_message.value.policy_definition_reference_id
    }
  }
  dynamic "overrides" {
    for_each = local.dynamic_payloads[each.key].overrides
    content {
      value = overrides.value.value
      dynamic "selectors" {
        for_each = overrides.value.selectors
        content {
          kind   = selectors.value.kind
          in     = selectors.value.in
          not_in = selectors.value.not_in
        }
      }
    }
  }
  dynamic "resource_selectors" {
    for_each = local.dynamic_payloads[each.key].resource_selectors
    content {
      name = resource_selectors.value.name
      dynamic "selectors" {
        for_each = resource_selectors.value.selectors
        content {
          kind   = selectors.value.kind
          in     = selectors.value.in
          not_in = selectors.value.not_in
        }
      }
    }
  }
}

resource "azurerm_subscription_policy_assignment" "this" {
  for_each   = local.by_scope["subscription"]
  depends_on = [terraform_data.contract_guard]

  name                 = local.assignment_names[each.key]
  subscription_id      = each.value.scope.id
  policy_definition_id = each.value.target.policy_definition_id
  display_name         = each.value.target.reference_id
  description          = local.provider_arguments[each.key].description
  enforce              = local.provider_arguments[each.key].enforce
  parameters           = local.parameter_payloads[each.key]
  not_scopes           = each.value.exclusions
  metadata             = local.provider_arguments[each.key].metadata
  location             = local.provider_arguments[each.key].location

  dynamic "identity" {
    for_each = each.value.identity_binding == null ? [] : [each.value.identity_binding]
    content {
      type         = "UserAssigned"
      identity_ids = [each.value.identity_id]
    }
  }
  dynamic "non_compliance_message" {
    for_each = local.dynamic_payloads[each.key].non_compliance_messages
    content {
      content                        = non_compliance_message.value.content
      policy_definition_reference_id = non_compliance_message.value.policy_definition_reference_id
    }
  }
  dynamic "overrides" {
    for_each = local.dynamic_payloads[each.key].overrides
    content {
      value = overrides.value.value
      dynamic "selectors" {
        for_each = overrides.value.selectors
        content {
          kind   = selectors.value.kind
          in     = selectors.value.in
          not_in = selectors.value.not_in
        }
      }
    }
  }
  dynamic "resource_selectors" {
    for_each = local.dynamic_payloads[each.key].resource_selectors
    content {
      name = resource_selectors.value.name
      dynamic "selectors" {
        for_each = resource_selectors.value.selectors
        content {
          kind   = selectors.value.kind
          in     = selectors.value.in
          not_in = selectors.value.not_in
        }
      }
    }
  }
}

resource "azurerm_resource_group_policy_assignment" "this" {
  for_each   = local.by_scope["resource_group"]
  depends_on = [terraform_data.contract_guard]

  name                 = local.assignment_names[each.key]
  resource_group_id    = each.value.scope.id
  policy_definition_id = each.value.target.policy_definition_id
  display_name         = each.value.target.reference_id
  description          = local.provider_arguments[each.key].description
  enforce              = local.provider_arguments[each.key].enforce
  parameters           = local.parameter_payloads[each.key]
  not_scopes           = each.value.exclusions
  metadata             = local.provider_arguments[each.key].metadata
  location             = local.provider_arguments[each.key].location

  dynamic "identity" {
    for_each = each.value.identity_binding == null ? [] : [each.value.identity_binding]
    content {
      type         = "UserAssigned"
      identity_ids = [each.value.identity_id]
    }
  }
  dynamic "non_compliance_message" {
    for_each = local.dynamic_payloads[each.key].non_compliance_messages
    content {
      content                        = non_compliance_message.value.content
      policy_definition_reference_id = non_compliance_message.value.policy_definition_reference_id
    }
  }
  dynamic "overrides" {
    for_each = local.dynamic_payloads[each.key].overrides
    content {
      value = overrides.value.value
      dynamic "selectors" {
        for_each = overrides.value.selectors
        content {
          kind   = selectors.value.kind
          in     = selectors.value.in
          not_in = selectors.value.not_in
        }
      }
    }
  }
  dynamic "resource_selectors" {
    for_each = local.dynamic_payloads[each.key].resource_selectors
    content {
      name = resource_selectors.value.name
      dynamic "selectors" {
        for_each = resource_selectors.value.selectors
        content {
          kind   = selectors.value.kind
          in     = selectors.value.in
          not_in = selectors.value.not_in
        }
      }
    }
  }
}

resource "azurerm_resource_policy_assignment" "this" {
  for_each   = local.by_scope["resource"]
  depends_on = [terraform_data.contract_guard]

  name                 = local.assignment_names[each.key]
  resource_id          = each.value.scope.id
  policy_definition_id = each.value.target.policy_definition_id
  display_name         = each.value.target.reference_id
  description          = local.provider_arguments[each.key].description
  enforce              = local.provider_arguments[each.key].enforce
  parameters           = local.parameter_payloads[each.key]
  not_scopes           = each.value.exclusions
  metadata             = local.provider_arguments[each.key].metadata
  location             = local.provider_arguments[each.key].location

  dynamic "identity" {
    for_each = each.value.identity_binding == null ? [] : [each.value.identity_binding]
    content {
      type         = "UserAssigned"
      identity_ids = [each.value.identity_id]
    }
  }
  dynamic "non_compliance_message" {
    for_each = local.dynamic_payloads[each.key].non_compliance_messages
    content {
      content                        = non_compliance_message.value.content
      policy_definition_reference_id = non_compliance_message.value.policy_definition_reference_id
    }
  }
  dynamic "overrides" {
    for_each = local.dynamic_payloads[each.key].overrides
    content {
      value = overrides.value.value
      dynamic "selectors" {
        for_each = overrides.value.selectors
        content {
          kind   = selectors.value.kind
          in     = selectors.value.in
          not_in = selectors.value.not_in
        }
      }
    }
  }
  dynamic "resource_selectors" {
    for_each = local.dynamic_payloads[each.key].resource_selectors
    content {
      name = resource_selectors.value.name
      dynamic "selectors" {
        for_each = resource_selectors.value.selectors
        content {
          kind   = selectors.value.kind
          in     = selectors.value.in
          not_in = selectors.value.not_in
        }
      }
    }
  }
}
