locals {
  # Shared flat-directory discovery and decode for every JSON source kind: the
  # custom-definition, built-in-reference and initiative adapters each read
  # exactly one opted-in directory, so these predicates are defined once and
  # the adapters keep only source-specific stages.
  #
  # fileset returns an empty set when an opted-in path is missing or an empty
  # directory, so both states present as zero top-level files and the contract
  # rejects either by default. try remains the dynamic-source guard: it catches
  # unexpected fileset errors (for example an invalid pattern) and still yields
  # the empty list. The recursive ** view keeps nested-only content distinct so
  # it is reported as nested, not as an empty source.
  json_source_directories = {
    custom     = var.custom_definition_directory
    built_in   = var.built_in_reference_directory
    initiative = var.initiative_directory
  }

  json_source_flat_files = {
    for name, directory in local.json_source_directories :
    name => directory == null ? [] : try(sort(fileset(directory, "*")), [])
  }

  json_source_tree_files = {
    for name, directory in local.json_source_directories :
    name => directory == null ? [] : try(sort(fileset(directory, "**")), [])
  }

  json_source_unsupported_files = {
    for name, files in local.json_source_flat_files :
    name => [for path in files : path if !endswith(path, ".json")]
  }

  json_source_nested_files = {
    for name, files in local.json_source_tree_files :
    name => [for path in files : path if length(split("/", path)) > 1]
  }

  # One decode per JSON file. Each record retains the decoded value and whether
  # decoding succeeded, so malformed JSON (decode_ok = false) stays distinct
  # from a JSON null (decode_ok = true, decoded = null) without a second read.
  # try evaluates the record constructor first; when file or jsondecode raises
  # a dynamic error the fallback record is used, so those cases become stable
  # diagnostics rather than a raw expression failure.
  json_source_file_records = {
    for name, directory in local.json_source_directories :
    name => {
      for path in local.json_source_flat_files[name] :
      path => try(
        {
          decode_ok = true
          decoded   = jsondecode(file("${directory}/${path}"))
        },
        {
          decode_ok = false
          decoded   = null
        }
      )
      if endswith(path, ".json")
    }
  }

  json_source_malformed_files = {
    for name, records in local.json_source_file_records :
    name => sort([
      for path, record in records : path
      if !record.decode_ok
    ])
  }

  # Per-source views over the shared maps above. These preserve the
  # established local names used by the adapters and the guard preconditions;
  # they add no logic of their own.
  custom_json_tree_files          = local.json_source_tree_files.custom
  built_in_json_tree_files        = local.json_source_tree_files.built_in
  initiative_json_tree_files      = local.json_source_tree_files.initiative
  unsupported_custom_files        = local.json_source_unsupported_files.custom
  unsupported_built_in_files      = local.json_source_unsupported_files.built_in
  unsupported_initiative_files    = local.json_source_unsupported_files.initiative
  nested_custom_files             = local.json_source_nested_files.custom
  nested_built_in_files           = local.json_source_nested_files.built_in
  nested_initiative_files         = local.json_source_nested_files.initiative
  custom_json_file_records        = local.json_source_file_records.custom
  built_in_json_file_records      = local.json_source_file_records.built_in
  initiative_json_file_records    = local.json_source_file_records.initiative
  malformed_custom_json_files     = local.json_source_malformed_files.custom
  malformed_built_in_json_files   = local.json_source_malformed_files.built_in
  malformed_initiative_json_files = local.json_source_malformed_files.initiative
}
