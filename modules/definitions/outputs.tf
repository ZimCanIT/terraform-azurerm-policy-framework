locals {
  base_definition_outputs = {
    for key, definition in local.definition_entries :
    key => {
      catalogue_key       = key
      source_type         = definition.source_type
      display_name        = definition.display_name
      description         = try(definition.description, "")
      mode                = try(definition.mode, "All")
      metadata            = definition.metadata
      parameters          = definition.parameters
      policy_rule         = definition.policy_rule
      role_definition_ids = distinct(definition.role_definition_ids)
      supported_effects   = definition.supported_effects
      version             = null
      version_constraint  = definition.version_constraint
      pinned_version      = definition.pinned_version
      management_group_id = definition.management_group_id
    }
  }

  custom_definition_outputs = {
    for key, definition in local.custom_definitions :
    key => merge(local.base_definition_outputs[key], {
      id                  = azurerm_policy_definition.this[key].id
      name                = azurerm_policy_definition.this[key].name
      display_name        = azurerm_policy_definition.this[key].display_name
      description         = azurerm_policy_definition.this[key].description
      mode                = azurerm_policy_definition.this[key].mode
      metadata            = local.custom_metadata[key]
      role_definition_ids = distinct(concat(local.base_definition_outputs[key].role_definition_ids, local.custom_policy_role_definition_ids[key]))
      version             = local.custom_versions[key]
      created_by_module   = true
    })
  }

  built_in_definition_outputs = {
    for key, definition in local.definition_entries :
    key => merge(local.base_definition_outputs[key], {
      id                  = definition.policy_definition_id
      name                = definition.name_was_supplied ? definition.name : basename(definition.policy_definition_id)
      created_by_module   = false
      management_group_id = null
    })
    if definition.source_type == "built_in"
  }

  definitions = merge(local.built_in_definition_outputs, local.custom_definition_outputs)
}

output "definitions" {
  description = "Canonical policy definition objects keyed by catalogue key. Custom and built-in definitions share the same downstream contract."
  value       = local.definitions
}

output "custom_definition_ids" {
  description = "Azure resource IDs for custom definitions created by this module."
  value = {
    for key, definition in local.custom_definition_outputs :
    key => definition.id
  }
}

output "built_in_definition_ids" {
  description = "Azure resource IDs for built-in definitions referenced by this module."
  value = {
    for key, definition in local.built_in_definition_outputs :
    key => definition.id
  }
}
