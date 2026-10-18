locals {
  # Grammar constants, written once for this module. Variable validations read
  # them, so they must never reference a variable or anything derived from one:
  # that would make a validation depend on the value it validates.
  guid_pattern = "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"

  # Scope prefixes. Every management-group and subscription form below derives
  # from these, and the unkeyed member scope probe reads them too, so each
  # prefix is written once.
  management_group_prefix = "^/providers/Microsoft\\.Management/managementGroups/"
  subscription_prefix     = "^/subscriptions/"

  built_in_definition_id_pattern = "^/providers/Microsoft\\.Authorization/policyDefinitions/${local.guid_pattern}$"
  management_group_id_pattern    = "${local.management_group_prefix}[^/]+$"

  # Accepted forms of a direct initiative member definition ID: built-in,
  # subscription custom and management-group custom.
  policy_definition_id_patterns = [
    local.built_in_definition_id_pattern,
    "${local.subscription_prefix}[0-9a-fA-F-]{36}/providers/Microsoft\\.Authorization/policyDefinitions/[^/]+$",
    "${local.management_group_prefix}[^/]+/providers/Microsoft\\.Authorization/policyDefinitions/[^/]+$",
  ]

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
    key => local.custom_versions[key] == null ? definition.metadata : merge(definition.metadata, { version = local.custom_versions[key] })
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
