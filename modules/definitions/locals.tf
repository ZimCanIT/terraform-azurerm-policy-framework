locals {
  definition_entries = {
    for key, definition in var.definitions :
    key => {
      source_type          = definition.source_type
      name                 = try(trimspace(definition.name), "") != "" ? trimspace(definition.name) : key
      name_was_supplied    = try(trimspace(definition.name), "") != ""
      policy_definition_id = try(trimspace(definition.policy_definition_id), "") != "" ? trimspace(definition.policy_definition_id) : null
      display_name         = definition.display_name
      description          = try(coalesce(definition.description, ""), "")
      metadata             = try(merge(definition.metadata), {})
      policy_rule          = try(definition.policy_rule, null)
      management_group_id  = try(trimspace(definition.management_group_id), "") != "" ? trimspace(definition.management_group_id) : null

      # mode, parameters and role_definition_ids follow a built-in-specific
      # unknown-state contract: for built-in entries, which this module never
      # looks up in Azure, omitted or null stays null (unknown), an explicit
      # empty value stays empty (verified absence) and supplied values are
      # preserved, with role lists normalised by tolist preserving element
      # values. Custom entries retain the "All", {} and [] resource defaults
      # because the custom policy-definition resource carries exactly those
      # values. supported_effects and the capability and governance
      # declarations are preserved for downstream interpretation for both
      # source types: absent or null stays null (unknown), an explicit empty
      # collection stays empty (verified absence) and supplied values are
      # preserved verbatim.
      mode       = definition.source_type == "built_in" ? try(definition.mode, null) : try(coalesce(definition.mode, "All"), "All")
      parameters = definition.source_type == "built_in" ? try(definition.parameters, null) : try(merge(definition.parameters), {})
      role_definition_ids = definition.source_type == "built_in" ? try(
        definition.role_definition_ids == null ? null : tolist(definition.role_definition_ids),
        null
        ) : try(
        definition.role_definition_ids == null ? [] : tolist(definition.role_definition_ids),
        []
      )
      supported_effects       = try(definition.supported_effects == null ? null : tolist(definition.supported_effects), null)
      supported_overrides     = try(definition.supported_overrides, null)
      selectors               = try(definition.selectors, null)
      non_compliance_messages = try(definition.non_compliance_messages, null)
      capabilities            = try(definition.capabilities, null)
      governance              = try(definition.governance, null)
      version                 = try(trimspace(definition.version), "") != "" ? trimspace(definition.version) : null
      version_constraint      = try(trimspace(definition.version_constraint), "") != "" ? trimspace(definition.version_constraint) : null
      pinned_version          = try(trimspace(definition.pinned_version), "") != "" ? trimspace(definition.pinned_version) : null
    }
  }

  custom_definitions = {
    for key, definition in local.definition_entries :
    key => definition
    if definition.source_type == "custom"
  }

  custom_metadata_versions = {
    for key, definition in local.custom_definitions :
    key => try(trimspace(definition.metadata.version), "") != "" ? trimspace(definition.metadata.version) : null
  }

  custom_versions = {
    for key, definition in local.custom_definitions :
    key => try(coalesce(definition.version, local.custom_metadata_versions[key]), null)
  }

  custom_metadata = {
    for key, definition in local.custom_definitions :
    key => merge(definition.metadata, {
      for field, value in { version = local.custom_versions[key] } : field => value
      if value != null
    })
  }

  custom_policy_role_definition_ids = {
    for key, definition in local.custom_definitions :
    key => try(definition.policy_rule.then.details.roleDefinitionIds == null ? [] : tolist(definition.policy_rule.then.details.roleDefinitionIds), [])
  }

  custom_identity_groups = {
    for key, definition in local.custom_definitions :
    lower("${coalesce(definition.management_group_id, "subscription")}|${definition.name}") => key...
  }

  custom_identity_collisions = [
    for identity, keys in local.custom_identity_groups : identity
    if length(keys) > 1
  ]
}
