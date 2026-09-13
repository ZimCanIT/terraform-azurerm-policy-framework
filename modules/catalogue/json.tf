locals {
  # fileset returns an empty set when an opted-in path is missing or an empty
  # directory, so both states present as zero top-level files and the contract
  # rejects either by default. try remains the dynamic-source guard: it catches
  # unexpected fileset errors (for example an invalid pattern) and still yields
  # the empty list. The recursive ** view keeps nested-only content distinct so
  # it is reported as nested, not as an empty source.
  custom_json_files        = var.custom_definition_directory == null ? [] : try(sort(fileset(var.custom_definition_directory, "*")), [])
  custom_json_tree_files   = var.custom_definition_directory == null ? [] : try(sort(fileset(var.custom_definition_directory, "**")), [])
  built_in_json_files      = var.built_in_reference_directory == null ? [] : try(sort(fileset(var.built_in_reference_directory, "*")), [])
  built_in_json_tree_files = var.built_in_reference_directory == null ? [] : try(sort(fileset(var.built_in_reference_directory, "**")), [])

  unsupported_custom_files = [
    for path in local.custom_json_files : path
    if !endswith(path, ".json")
  ]

  unsupported_built_in_files = [
    for path in local.built_in_json_files : path
    if !endswith(path, ".json")
  ]

  nested_custom_files = [
    for path in local.custom_json_tree_files : path
    if length(split("/", path)) > 1
  ]

  nested_built_in_files = [
    for path in local.built_in_json_tree_files : path
    if length(split("/", path)) > 1
  ]

  # One decode per JSON file. Each record retains the decoded value and whether
  # decoding succeeded, so malformed JSON (decode_ok = false) stays distinct
  # from a JSON null (decode_ok = true, decoded = null) without a second read.
  # try evaluates the record constructor first; when file or jsondecode raises
  # a dynamic error the fallback record is used, so those cases become stable
  # diagnostics rather than a raw expression failure.
  custom_json_file_records = {
    for path in local.custom_json_files :
    path => try(
      {
        decode_ok = true
        decoded   = jsondecode(file("${var.custom_definition_directory}/${path}"))
      },
      {
        decode_ok = false
        decoded   = null
      }
    )
    if endswith(path, ".json")
  }

  built_in_json_file_records = {
    for path in local.built_in_json_files :
    path => try(
      {
        decode_ok = true
        decoded   = jsondecode(file("${var.built_in_reference_directory}/${path}"))
      },
      {
        decode_ok = false
        decoded   = null
      }
    )
    if endswith(path, ".json")
  }

  malformed_custom_json_files = sort([
    for path, record in local.custom_json_file_records : path
    if !record.decode_ok
  ])

  malformed_built_in_json_files = sort([
    for path, record in local.built_in_json_file_records : path
    if !record.decode_ok
  ])

  custom_policy_documents = {
    for path, record in local.custom_json_file_records :
    trimsuffix(path, ".json") => record.decoded
    if !endswith(path, "-parameters.json")
  }

  custom_parameter_file_records = {
    for path, record in local.custom_json_file_records :
    trimsuffix(path, "-parameters.json") => record
    if endswith(path, "-parameters.json")
  }

  custom_parameter_documents = {
    for stem, record in local.custom_parameter_file_records : stem => record.decoded
  }

  built_in_json_documents = {
    for path, record in local.built_in_json_file_records : path => record.decoded
  }

  # Only decoded primary envelopes with an object document enter the shared
  # semantic records. Malformed and non-object primaries are owned by the
  # malformed and envelope container rules, so they cannot cascade into
  # field-exclusivity, allowlist, required-field and version-format failures.
  object_custom_policy_documents = {
    for path, document in local.custom_policy_documents : path => document
    if can(keys(document))
  }

  object_built_in_json_documents = {
    for path, document in local.built_in_json_documents : path => document
    if can(keys(document))
  }

  # Safe string map keys for the object-shaped JSON primaries. A catalogue key
  # that is an actual string is used verbatim, so grouping, duplicate detection
  # and provenance see the same key the shared key_valid rule checks; any other
  # shape gets a path-specific placeholder because Terraform map keys must be
  # strings. The placeholder is not a validity decision: key_valid reads the
  # raw key and rejects the placeholder's source value.
  custom_definition_key_safe = {
    for path, document in local.object_custom_policy_documents :
    path => can(regex("^\\\".*\\\"$", jsonencode(document.catalogue_key))) ?
    document.catalogue_key : "__invalid_custom_${path}"
  }

  built_in_definition_key_safe = {
    for path, document in local.object_built_in_json_documents :
    path => can(regex("^\\\".*\\\"$", jsonencode(document.catalogue_key))) ?
    document.catalogue_key : "__invalid_built_in_${path}"
  }

  custom_policy_source_paths = {
    for path in keys(local.custom_policy_documents) : path => "${path}.json"
  }

  # Companion keys are already-normalised stems; never strip -parameters again,
  # or repeated-suffix filenames would collapse onto a different key.
  custom_parameter_source_paths = {
    for path in keys(local.custom_parameter_documents) : path => "${path}-parameters.json"
  }

  orphan_custom_parameter_files = sort(tolist(setsubtract(
    toset(keys(local.custom_parameter_documents)),
    toset(keys(local.custom_policy_documents))
  )))

  custom_parameter_conflict_stems = sort([
    for stem, document in local.custom_policy_documents : stem
    if contains(keys(local.custom_parameter_documents), stem) && try(contains(keys(document), "parameters") && document.parameters != null, false)
  ])

  # Named companion and envelope-shape failures. Each string names the source
  # file and the failed rule so the preconditions below assert one rule each
  # with an attributable diagnostic. Only successfully decoded files are
  # shape-checked here: malformed JSON is reported by the malformed rule, and a
  # JSON null is a decoded non-object rather than a decode failure.
  non_object_custom_parameter_files = sort([
    for stem, record in local.custom_parameter_file_records :
    local.custom_parameter_source_paths[stem]
    if record.decode_ok && !can(keys(record.decoded))
  ])

  # Primary envelopes only. Companion-pattern paths are owned once by
  # companion_object_valid below, so an array, null, string, number or boolean
  # companion is reported by one rule and one precondition, not two.
  non_object_custom_json_files = sort([
    for path, record in local.custom_json_file_records :
    path
    if record.decode_ok && !endswith(path, "-parameters.json") && !can(keys(record.decoded))
  ])

  non_object_built_in_json_files = sort([
    for path, record in local.built_in_json_file_records :
    path
    if record.decode_ok && !can(keys(record.decoded))
  ])

  definition_companion_failures = {
    companion_parent_valid = [
      for path in local.orphan_custom_parameter_files :
      "custom:${local.custom_parameter_source_paths[path]}: failed companion_parent_valid"
    ]
    companion_conflict_valid = [
      for path in local.custom_parameter_conflict_stems :
      "custom:${local.custom_policy_source_paths[path]}: failed companion_conflict_valid"
    ]
    companion_object_valid = [
      for path in local.non_object_custom_parameter_files :
      "custom:${path}: failed companion_object_valid"
    ]
  }

  # Companion values deliberately win over inline parameters because try
  # returns the first successful value, including a JSON null companion, which
  # the non-object precondition below rejects. A non-null inline value plus a
  # companion is rejected, avoiding conditional-expression type coercion and
  # ambiguous ownership.
  custom_definition_raw_entries = {
    for path, document in local.object_custom_policy_documents :
    "custom:${path}" => {
      catalogue_key    = try(document.catalogue_key, null)
      projection_key   = local.custom_definition_key_safe[path]
      authoring_format = "json"
      source_type      = "custom"
      document         = document
      parameters       = try(local.custom_parameter_documents[path], document.parameters, null)
    }
  }

  built_in_definition_raw_entries = {
    for path, document in local.object_built_in_json_documents :
    "built_in:${path}" => {
      catalogue_key    = try(document.catalogue_key, null)
      projection_key   = local.built_in_definition_key_safe[path]
      authoring_format = "json"
      source_type      = "built_in"
      document         = document
      parameters       = try(document.parameters, null)
    }
  }

  # Integration merges this source-only map with native HCL entries once. The
  # shared projection in definitions.tf has already applied the canonical field
  # shape; grouping keeps duplicate keys from raising a raw duplicate-key error
  # before the deliberate duplicate preconditions report them. Sorted origin
  # order makes a built-in reference win over a custom envelope with the same
  # key, matching the previous merge(custom, built-in) order. Grouping produces
  # a list per key, so the first entry is unwrapped below.
  json_definition_groups = {
    for origin, entry in local.definition_raw_entries :
    entry.projection_key => local.definition_projected_entries[origin]...
    if entry.authoring_format == "json"
  }

  json_definitions = {
    for key, definitions in local.json_definition_groups : key => definitions[0]
  }

  # Duplicate detection reads the same verbatim keys that grouping, projection
  # and provenance use: a valid JSON key is never trimmed. Only actual strings
  # enter the list; the path-specific placeholders for non-string keys stay out
  # because key_valid rejects those sources, and no placeholder prefix is
  # reserved, so a literal key can never be excluded. Cross-source collisions
  # are compared by the same rule in integration.tf.
  json_definition_keys = [
    for entry in concat(
      values(local.custom_definition_raw_entries),
      values(local.built_in_definition_raw_entries)
    ) :
    entry.catalogue_key
    if can(regex("^\\\".*\\\"$", jsonencode(entry.catalogue_key)))
  ]

  # One grouping pass keyed by the case-normalised JSON key. Duplicate
  # detection below reads group sizes directly instead of rescanning all keys
  # for each key.
  json_definition_key_groups = {
    for key in local.json_definition_keys :
    lower(key) => key...
    if key != ""
  }

  json_duplicate_definition_keys = sort([
    for normalized_key, keys in local.json_definition_key_groups : normalized_key
    if length(keys) > 1
  ])

  custom_envelope_fields = toset([
    "catalogue_key", "name", "display_name", "description", "mode", "metadata", "parameters",
    "policy_rule", "management_group_id", "role_definition_ids", "supported_effects", "supported_overrides",
    "selectors", "non_compliance_messages", "capabilities", "governance", "version"
  ])

  built_in_envelope_fields = toset([
    "catalogue_key", "name", "policy_definition_id", "display_name", "description", "mode", "metadata",
    "parameters", "role_definition_ids", "supported_effects", "supported_overrides", "selectors",
    "non_compliance_messages", "capabilities", "governance", "version_constraint", "pinned_version"
  ])
}

resource "terraform_data" "json_ingestion_contract" {
  # Deliberately no input: this resource exists only to evaluate the blocking
  # preconditions below. Storing the catalogue payload in instance state would
  # make policy content part of a resource whose purpose is validation and
  # create content-change plans. The preconditions reference the same locals,
  # so they still evaluate and still block invalid sources.
  lifecycle {
    precondition {
      condition     = var.custom_definition_directory == null || var.allow_empty_sources || length(local.custom_json_tree_files) > 0
      error_message = "custom_definition_directory was opted in but contains no files (the path may be missing or empty); add a top-level JSON envelope or set allow_empty_sources = true explicitly."
    }

    precondition {
      condition     = var.built_in_reference_directory == null || var.allow_empty_sources || length(local.built_in_json_tree_files) > 0
      error_message = "built_in_reference_directory was opted in but contains no files (the path may be missing or empty); add a top-level JSON envelope or set allow_empty_sources = true explicitly."
    }

    precondition {
      condition     = length(local.nested_custom_files) == 0 && length(local.nested_built_in_files) == 0
      error_message = "JSON source directories are flat; nested files are unsupported (custom: ${join(", ", local.nested_custom_files)}, built-in: ${join(", ", local.nested_built_in_files)})."
    }

    precondition {
      condition = length(local.unsupported_custom_files) == 0 && length(local.unsupported_built_in_files) == 0
      error_message = join("", [
        "JSON source directories may contain only top-level .json files ",
        "(custom: ${join(", ", local.unsupported_custom_files)}, built-in: ${join(", ", local.unsupported_built_in_files)}).",
      ])
    }

    precondition {
      condition     = length(local.malformed_custom_json_files) == 0 && length(local.malformed_built_in_json_files) == 0
      error_message = "Malformed JSON source envelope(s): custom [${join(", ", local.malformed_custom_json_files)}], built-in [${join(", ", local.malformed_built_in_json_files)}]."
    }

    precondition {
      condition = length(local.non_object_custom_json_files) == 0 && length(local.non_object_built_in_json_files) == 0
      error_message = join("", [
        "JSON source envelopes must contain non-null JSON objects; null, arrays, strings, numbers and booleans are unsupported ",
        "(custom: ${join(", ", local.non_object_custom_json_files)}, built-in: ${join(", ", local.non_object_built_in_json_files)}). ",
        "Parameter companions are checked separately by companion_object_valid.",
      ])
    }

    # Shared definition field semantics. Each precondition asserts one named
    # rule from definitions.tf so a failure names the rule and the offending
    # source key or file. The rules cover native HCL, custom JSON and built-in
    # JSON in one place; the native variable boundary deliberately keeps only
    # outer-shape checks because a validation condition cannot reference locals.
    precondition {
      condition     = length(local.definition_rule_failures.source_type_valid) == 0
      error_message = "Each native definition requires source_type = \"custom\" or source_type = \"built_in\". Failures: ${local.definition_failure_text.source_type_valid}"
    }

    precondition {
      condition = length(local.definition_rule_failures.field_exclusivity_valid) == 0
      error_message = join("", [
        "Definition entries must not mix source-type fields: custom entries cannot set policy_definition_id, version_constraint or pinned_version, ",
        "and built-in entries cannot set policy_rule, management_group_id or version. ",
        "Failures: ${local.definition_failure_text.field_exclusivity_valid}",
      ])
    }

    precondition {
      condition     = length(local.definition_rule_failures.field_allowlist_valid) == 0
      error_message = "Custom and built-in JSON envelopes may use only documented fields for their source type. Failures: ${local.definition_failure_text.field_allowlist_valid}"
    }

    precondition {
      condition     = length(local.definition_rule_failures.key_valid) == 0
      error_message = "Definition catalogue keys must be non-blank strings with no surrounding whitespace. Failures: ${local.definition_failure_text.key_valid}"
    }

    precondition {
      condition = length(local.definition_rule_failures.required_fields_valid) == 0
      error_message = join("", [
        "Definition entries require display_name; custom entries require a policy_rule object and ",
        "built-in entries require a complete /providers/Microsoft.Authorization/policyDefinitions/<GUID> policy_definition_id. ",
        "Failures: ${local.definition_failure_text.required_fields_valid}",
      ])
    }

    precondition {
      condition = length(local.definition_rule_failures.scalar_types_valid) == 0
      error_message = join("", [
        "Definition string fields must be actual strings: display_name is required; name, description, mode, policy_definition_id, ",
        "management_group_id, version, version_constraint, pinned_version and metadata.version are null-or-string when supplied. ",
        "Failures: ${local.definition_failure_text.scalar_types_valid}",
      ])
    }

    precondition {
      condition     = length(local.definition_rule_failures.metadata_valid) == 0
      error_message = "Definition metadata must be an object when supplied. Failures: ${local.definition_failure_text.metadata_valid}"
    }

    precondition {
      condition     = length(local.definition_rule_failures.parameters_valid) == 0
      error_message = "Definition parameters must be an object when supplied. Failures: ${local.definition_failure_text.parameters_valid}"
    }

    precondition {
      condition = length(local.definition_rule_failures.version_format_valid) == 0
      error_message = join("", [
        "Custom definitions require an exact three-part version in version or metadata.version; built-in version_constraint must be ",
        "major.*.* or major.minor.* and pinned_version must be an exact x.y.z. ",
        "Failures: ${local.definition_failure_text.version_format_valid}",
      ])
    }

    precondition {
      condition = length(local.definition_rule_failures.version_intent_valid) == 0
      error_message = join("", [
        "Custom definitions must use matching version and metadata.version values when both are supplied; built-in references require ",
        "exactly one of version_constraint or pinned_version. Failures: ${local.definition_failure_text.version_intent_valid}",
      ])
    }

    precondition {
      condition = length(local.definition_rule_failures.capability_containers_valid) == 0
      error_message = join("", [
        "Definition capability fields must use the documented container shapes: supported_effects is a list of non-blank strings; ",
        "supported_overrides and selectors are lists of objects; non_compliance_messages, capabilities and governance are objects. ",
        "Null means unknown and an explicit empty collection means verified absence. ",
        "Failures: ${local.definition_failure_text.capability_containers_valid}",
      ])
    }

    precondition {
      condition     = length(local.definition_companion_failures.companion_parent_valid) == 0
      error_message = "Each custom *-parameters.json file must have a matching policy envelope JSON file. Failures: ${local.definition_companion_text.companion_parent_valid}"
    }

    precondition {
      condition = length(local.definition_companion_failures.companion_conflict_valid) == 0
      error_message = join("", [
        "A custom envelope and its *-parameters.json companion cannot both contain non-null parameters; remove one source. ",
        "Failures: ${local.definition_companion_text.companion_conflict_valid}",
      ])
    }

    precondition {
      condition     = length(local.definition_companion_failures.companion_object_valid) == 0
      error_message = "Custom parameter companion files must contain a JSON object. Failures: ${local.definition_companion_text.companion_object_valid}"
    }

    precondition {
      condition     = length(local.json_duplicate_definition_keys) == 0
      error_message = "JSON catalogue keys must be unique case-insensitively across custom definitions and built-in references (collisions: ${join(", ", local.json_duplicate_definition_keys)})."
    }
  }
}
