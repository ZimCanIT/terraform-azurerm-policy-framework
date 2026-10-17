resource "terraform_data" "initiative_ingestion_contract" {
  lifecycle {
    precondition {
      condition     = length(local.duplicate_initiative_names) == 0
      error_message = "Initiative names must be unique per management-group or subscription scope (collisions: ${join(", ", local.duplicate_initiative_names)})."
    }

    precondition {
      condition     = length(local.parameter_schema_failures) == 0
      error_message = "Azure Policy parameter schemas must use supported types, object parameter records, type-compatible defaults and allowed values. Failures: ${join("; ", local.parameter_schema_failures)}"
    }

    # One precondition per rule family. Each failure names the initiative key,
    # the member or group, the failed rule and that rule's explanation.
    precondition {
      condition     = length(local.initiative_rule_failures.entry) == 0
      error_message = "Initiative envelope contract violations: ${local.initiative_rule_messages.entry}"
    }

    precondition {
      condition     = length(local.initiative_rule_failures.reference) == 0
      error_message = "Initiative member contract violations: ${local.initiative_rule_messages.reference}"
    }

    precondition {
      condition     = length(local.initiative_rule_failures.group) == 0
      error_message = "Initiative group contract violations: ${local.initiative_rule_messages.group}"
    }
  }
}

resource "azurerm_policy_set_definition" "subscription" {
  for_each = { for key, initiative in local.subscription_initiatives : key => initiative if local.initiative_contract_valid }

  depends_on = [terraform_data.initiative_ingestion_contract]

  name         = coalesce(each.value.name, each.key)
  policy_type  = "Custom"
  display_name = each.value.display_name
  description  = each.value.description
  metadata     = each.value.metadata == null ? null : jsonencode(each.value.metadata)
  parameters   = each.value.parameters == null ? null : jsonencode(each.value.parameters)

  dynamic "policy_definition_group" {
    for_each = each.value.policy_definition_groups == null ? [] : each.value.policy_definition_groups

    content {
      name                            = policy_definition_group.value.name
      display_name                    = policy_definition_group.value.display_name
      description                     = try(policy_definition_group.value.description, null)
      category                        = try(policy_definition_group.value.metadata.category, null)
      additional_metadata_resource_id = try(policy_definition_group.value.metadata.additional_metadata_resource_id, null)
    }
  }

  dynamic "policy_definition_reference" {
    for_each = local.initiative_member_resolution[each.key]

    content {
      reference_id         = policy_definition_reference.value.reference_id
      policy_definition_id = policy_definition_reference.value.policy_definition_id
      parameter_values     = policy_definition_reference.value.parameter_values == null ? null : jsonencode(policy_definition_reference.value.parameter_values)
      policy_group_names   = policy_definition_reference.value.group_names == null ? null : policy_definition_reference.value.group_names
      version              = policy_definition_reference.value.provider_version
    }
  }
}

resource "azurerm_management_group_policy_set_definition" "management_group" {
  for_each = { for key, initiative in local.management_group_initiatives : key => initiative if local.initiative_contract_valid }

  depends_on = [terraform_data.initiative_ingestion_contract]

  name                = coalesce(each.value.name, each.key)
  policy_type         = "Custom"
  management_group_id = each.value.management_group_id
  display_name        = each.value.display_name
  description         = each.value.description
  metadata            = each.value.metadata == null ? null : jsonencode(each.value.metadata)
  parameters          = each.value.parameters == null ? null : jsonencode(each.value.parameters)

  dynamic "policy_definition_group" {
    for_each = each.value.policy_definition_groups == null ? [] : each.value.policy_definition_groups

    content {
      name                            = policy_definition_group.value.name
      display_name                    = policy_definition_group.value.display_name
      description                     = try(policy_definition_group.value.description, null)
      category                        = try(policy_definition_group.value.metadata.category, null)
      additional_metadata_resource_id = try(policy_definition_group.value.metadata.additional_metadata_resource_id, null)
    }
  }

  dynamic "policy_definition_reference" {
    for_each = local.initiative_member_resolution[each.key]

    content {
      reference_id         = policy_definition_reference.value.reference_id
      policy_definition_id = policy_definition_reference.value.policy_definition_id
      parameter_values     = policy_definition_reference.value.parameter_values == null ? null : jsonencode(policy_definition_reference.value.parameter_values)
      policy_group_names   = policy_definition_reference.value.group_names == null ? null : policy_definition_reference.value.group_names
      version              = policy_definition_reference.value.provider_version
    }
  }
}
