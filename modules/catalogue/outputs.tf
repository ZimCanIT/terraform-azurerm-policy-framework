locals {
  # One record per actual catalogue entry. Parameter companions are attached to
  # their parent entry as companion_source_path and never emitted separately.
  # The record shape is identical across native HCL and JSON, definitions and
  # initiatives; native entries have a null source_path.
  definition_source_summary = concat(
    [for key, definition in local.native_definitions : {
      catalogue_key         = key
      source_type           = try(definition.source_type, null)
      authoring_format      = "hcl"
      source_path           = null
      companion_source_path = null
    }],
    [for origin, entry in local.custom_definition_raw_entries : {
      catalogue_key         = entry.projection_key
      source_type           = "custom"
      authoring_format      = "json"
      source_path           = local.custom_policy_source_paths[trimprefix(origin, "custom:")]
      companion_source_path = lookup(local.custom_parameter_source_paths, trimprefix(origin, "custom:"), null)
    }],
    [for origin, entry in local.built_in_definition_raw_entries : {
      catalogue_key         = entry.projection_key
      source_type           = "built_in"
      authoring_format      = "json"
      source_path           = trimprefix(origin, "built_in:")
      companion_source_path = null
    }]
  )

  initiative_source_summary = concat(
    [for key in keys(local.native_initiatives) : {
      catalogue_key         = key
      source_type           = "initiative"
      authoring_format      = "hcl"
      source_path           = null
      companion_source_path = null
    }],
    [for path, document in local.initiative_documents : {
      catalogue_key         = try(trimspace(document.catalogue_key), "")
      source_type           = "initiative"
      authoring_format      = "json"
      source_path           = "${path}.json"
      companion_source_path = lookup(local.initiative_parameter_source_paths, path, null)
    }]
  )
}

output "source_summary" {
  description = "Non-sensitive source provenance with exactly one record per catalogue entry; companions are reported as companion_source_path on their parent record. Downstream resource identity must still use the stable catalogue keys."
  value = concat(
    local.definition_source_summary,
    local.initiative_source_summary,
  )
}
