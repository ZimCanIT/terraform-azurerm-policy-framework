locals {
  # Initiative JSON adapter and canonical merge. Discovery and decode are
  # shared in json-sources.tf; this file separates primary envelopes from
  # parameter companions, normalises JSON initiatives, merges native and JSON
  # sources, and detects cross-source duplicate keys. Validation rules live in
  # initiatives-validation.tf, initiatives-references.tf and
  # initiatives-groups.tf; diagnostics in diagnostics.tf; the guard in
  # guards.tf.

  initiative_documents = {
    for path, record in local.initiative_json_file_records :
    trimsuffix(path, ".json") => record.decoded
    if !endswith(path, "-parameters.json")
  }

  initiative_parameter_file_records = {
    for path, record in local.initiative_json_file_records :
    trimsuffix(path, "-parameters.json") => record
    if endswith(path, "-parameters.json")
  }

  initiative_parameter_documents = {
    for stem, record in local.initiative_parameter_file_records : stem => record.decoded
  }

  # Keys are already-normalised companion stems (the -parameters.json suffix is
  # removed once above). Do not strip another -parameters suffix here: a
  # repeated-suffix filename such as orphan-parameters-parameters.json would
  # collapse onto a different key and later direct map indexing would fail with
  # a raw Invalid index error instead of a deliberate diagnostic.
  initiative_parameter_source_paths = {
    for path in keys(local.initiative_parameter_documents) : path => "${path}-parameters.json"
  }

  orphan_initiative_parameter_files = sort(tolist(setsubtract(
    toset(keys(local.initiative_parameter_documents)),
    toset(keys(local.initiative_documents))
  )))

  initiative_parameter_conflict_stems = sort([
    for stem, document in local.initiative_documents : stem
    if contains(keys(local.initiative_parameter_documents), stem) && try(contains(keys(document), "parameters") && document.parameters != null, false)
  ])

  # Companion records retain decode status: a JSON null companion
  # (decode_ok = true, decoded = null) is a decoded non-object and is rejected
  # here, while malformed JSON is reported by the malformed-file precondition.
  non_object_initiative_parameter_files = sort([
    for stem, record in local.initiative_parameter_file_records :
    local.initiative_parameter_source_paths[stem]
    if record.decode_ok && !can(keys(record.decoded))
  ])

  # Projection map only: trimming the inline key here cannot rename an
  # accepted identity because the key_valid precondition rejects any key that
  # differs from its trimspace, and the try fallback keeps malformed documents
  # out of direct map indexing.
  json_initiative_key_safe = {
    for path, document in local.initiative_documents :
    path => try(
      can(regex("^\\\".*\\\"$", jsonencode(document.catalogue_key))) ? document.catalogue_key : "__invalid_initiative_${path}",
      "__invalid_initiative_${path}"
    )
  }

  json_initiative_groups = {
    for path, document in local.initiative_documents :
    local.json_initiative_key_safe[path] => {
      name                         = try(document.name, null)
      display_name                 = try(document.display_name, null)
      description                  = try(document.description, null)
      metadata                     = try(document.metadata, null)
      parameters                   = try(local.initiative_parameter_documents[path], document.parameters, null)
      policy_definition_references = try(document.policy_definition_references, null)
      policy_definition_groups     = try(document.policy_definition_groups, null)
      management_group_id          = try(document.management_group_id, null)
      governance                   = try(document.governance, null)
      version                      = try(document.version, null)
    }...
  }

  json_initiatives = {
    for key, initiatives in local.json_initiative_groups : key => initiatives[0]
  }

  initiative_json_keys = values(local.json_initiative_key_safe)

  # One grouping pass keyed by the case-normalised JSON key. Duplicate
  # detection below reads group sizes directly instead of rescanning all keys
  # for each key.
  json_initiative_key_groups = {
    for key in local.initiative_json_keys :
    lower(key) => key...
    if key != ""
  }

  json_duplicate_initiative_keys = sort([
    for normalized_key, keys in local.json_initiative_key_groups : normalized_key
    if length(keys) > 1
  ])

  initiative_sources = {
    native = local.native_initiatives
    json   = local.json_initiatives
  }

  # Key origins, grouping and duplicate detection compare the same key text
  # for both authoring formats: the key_valid precondition rejects any key
  # whose trimspace differs, so an accepted JSON inline key equals its
  # trimmed form and an accepted native outer key is retained verbatim.
  initiative_key_origins = flatten([
    for source, initiatives in local.initiative_sources : [
      for key in keys(initiatives) : {
        source         = source
        key            = key
        normalized_key = lower(key)
      }
    ]
  ])

  # One grouping pass keyed by the case-normalised key. Duplicate detection
  # below reads group sizes directly instead of rescanning every origin for
  # each distinct key. Group membership and map iteration are deterministic,
  # and only the group sizes feed the duplicate diagnostics.
  initiative_key_groups = {
    for origin in local.initiative_key_origins :
    origin.normalized_key => "${origin.source}:${origin.key}"...
  }

  duplicate_initiative_keys = sort([
    for normalized_key, origins in local.initiative_key_groups : normalized_key
    if length(origins) > 1
  ])

  initiatives = merge(
    local.initiative_sources.native,
    local.initiative_sources.json,
  )
}
