locals {
  # Custom-definition and built-in-reference JSON adapter. Discovery and decode
  # are shared in json-sources.tf; this file separates primary envelopes from
  # parameter companions, resolves companion precedence, builds raw entries for
  # the shared model in definitions.tf, and groups JSON definition keys for
  # duplicate detection.

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

  # Only successfully decoded files are shape-checked here: malformed JSON is
  # reported by the malformed rule, and a JSON null is a decoded non-object
  # rather than a decode failure.
  non_object_custom_parameter_files = sort([
    for stem, record in local.custom_parameter_file_records :
    local.custom_parameter_source_paths[stem]
    if record.decode_ok && !can(keys(record.decoded))
  ])

  # Primary envelopes only. Companion-pattern paths are owned once by
  # companion_object_valid, so an array, null, string, number or boolean
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

  # Companion values deliberately win over inline parameters because try
  # returns the first successful value, including a JSON null companion, which
  # the non-object precondition rejects. A non-null inline value plus a
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
}
