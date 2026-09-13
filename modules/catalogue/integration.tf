locals {
  # Source adapters own decoding. This final boundary only combines their
  # canonical, keyed maps before handing them to modules/definitions.
  definition_sources = {
    native = local.native_definitions
    json   = local.json_definitions
  }

  # Azure policy-definition identities are case-insensitive in practice, so
  # reject keys that collide after case normalisation as well as exact repeats.
  definition_key_origins = flatten([
    for source, definitions in local.definition_sources : [
      for key in keys(definitions) : {
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
  definition_key_groups = {
    for origin in local.definition_key_origins :
    origin.normalized_key => "${origin.source}:${origin.key}"...
  }

  duplicate_definition_keys = sort([
    for normalized_key, origins in local.definition_key_groups : normalized_key
    if length(origins) > 1
  ])

  # Do not add catalogue-only provenance fields here. The result deliberately
  # remains the definitions module's canonical input envelope.
  definitions = merge(
    local.definition_sources.native,
    local.definition_sources.json,
  )
}

output "definitions" {
  description = "Canonical policy definition entries keyed by stable catalogue key; pass directly to modules/definitions.definitions."
  value       = local.definitions

  precondition {
    condition     = length(local.duplicate_definition_keys) == 0
    error_message = "Definition catalogue keys must be unique across native HCL and JSON sources (case-insensitive collisions: ${join(", ", local.duplicate_definition_keys)})."
  }
}
