locals {
  # Native HCL adaptation. The outer map key is the stable catalogue key and
  # native entries never carry an inline catalogue_key. The shared projection in
  # definitions.tf turns this record into the canonical envelope once for every
  # authoring path.
  native_definition_raw_entries = {
    for key, definition in var.native_definitions :
    "native:${key}" => {
      catalogue_key    = key
      projection_key   = key
      authoring_format = "hcl"
      source_type      = try(definition.source_type, null)
      document         = definition
      parameters       = try(definition.parameters, null)
    }
  }

  # Canonical native definitions, keyed by stable catalogue key, ready for the
  # integration merge with the JSON source.
  native_definitions = {
    for origin, entry in local.definition_raw_entries :
    entry.catalogue_key => local.definition_projected_entries[origin]
    if entry.authoring_format == "hcl"
  }

  # Initiative resources are owned downstream; catalogue only preserves the
  # composition envelope and stable member references.
  native_initiatives = {
    for key, initiative in var.native_initiatives :
    key => {
      name                         = try(initiative.name, null)
      display_name                 = try(initiative.display_name, null)
      description                  = try(initiative.description, null)
      metadata                     = try(initiative.metadata, null)
      parameters                   = try(initiative.parameters, null)
      policy_definition_references = try(initiative.policy_definition_references, null)
      policy_definition_groups     = try(initiative.policy_definition_groups, null)
      management_group_id          = try(initiative.management_group_id, null)
      governance                   = try(initiative.governance, null)
      version                      = try(initiative.version, null)
    }
  }
}
