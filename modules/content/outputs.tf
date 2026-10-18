locals {
  base_definition_outputs = {
    for key, definition in local.definition_entries :
    key => {
      catalogue_key = key
      source_type   = definition.source_type
      display_name  = definition.display_name
      # definition_entries already normalises description to a plain string.
      description = definition.description
      mode        = definition.mode
      metadata    = definition.metadata
      parameters  = definition.parameters
      policy_rule = definition.policy_rule
      # distinct would error on the built-in null unknown state; only a
      # supplied or defaulted list is deduplicated.
      role_definition_ids = definition.role_definition_ids == null ? null : distinct(definition.role_definition_ids)

      # Unknown-versus-verified-absence semantics for these fields are set in
      # locals.tf definition_entries and passed through unchanged.
      supported_effects       = definition.supported_effects
      supported_overrides     = definition.supported_overrides
      selectors               = definition.selectors
      non_compliance_messages = definition.non_compliance_messages
      capabilities            = definition.capabilities
      governance              = definition.governance

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
  description = "Canonical definition outputs keyed by stable catalogue key, for custom and built-in entries alike. This is the hand-off to behaviour resolution."
  value       = local.definitions
}

output "custom_definition_ids" {
  description = "Created custom definition IDs keyed by stable catalogue key."
  value = {
    for key, definition in local.custom_definition_outputs :
    key => definition.id
  }
}

output "built_in_definition_ids" {
  description = "Supplied built-in references keyed by stable catalogue key."
  value = {
    for key, definition in local.built_in_definition_outputs :
    key => definition.id
  }
}

locals {
  initiative_outputs = merge(
    {
      for key, initiative in local.subscription_initiatives :
      key => {
        catalogue_key                = key
        id                           = azurerm_policy_set_definition.subscription[key].id
        name                         = azurerm_policy_set_definition.subscription[key].name
        display_name                 = initiative.display_name
        description                  = initiative.description
        management_group_id          = null
        metadata                     = initiative.metadata
        parameters                   = initiative.parameters
        parameter_schema             = initiative.parameters
        policy_definition_groups     = initiative.policy_definition_groups
        policy_definition_references = local.initiative_member_resolution[key]
        governance                   = initiative.governance
        version                      = initiative.version
        created_by_module            = true
      } if local.initiative_contract_valid
    },
    {
      for key, initiative in local.management_group_initiatives :
      key => {
        catalogue_key                = key
        id                           = azurerm_management_group_policy_set_definition.management_group[key].id
        name                         = azurerm_management_group_policy_set_definition.management_group[key].name
        display_name                 = initiative.display_name
        description                  = initiative.description
        management_group_id          = initiative.management_group_id
        metadata                     = initiative.metadata
        parameters                   = initiative.parameters
        parameter_schema             = initiative.parameters
        policy_definition_groups     = initiative.policy_definition_groups
        policy_definition_references = local.initiative_member_resolution[key]
        governance                   = initiative.governance
        version                      = initiative.version
        created_by_module            = true
      } if local.initiative_contract_valid
    }
  )
}

output "initiatives" {
  description = "Canonical initiative outputs keyed by stable catalogue key, including the created Azure initiative ID, set-level parameter_schema and resolved member references with each member's independent schema and capability context. This is the hand-off to behaviour resolution."
  value       = local.initiative_outputs
}

output "initiative_ids" {
  description = "Azure initiative IDs keyed by stable catalogue key."
  value = {
    for key, initiative in local.initiative_outputs :
    key => initiative.id
  }
}

output "policy_definition_references" {
  description = "Resolved initiative member references keyed by stable catalogue key."
  value = {
    for key, initiative in local.initiative_outputs :
    key => initiative.policy_definition_references
  }
}
