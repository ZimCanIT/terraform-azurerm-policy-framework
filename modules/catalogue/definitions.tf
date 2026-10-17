locals {
  # One raw-entry view for native HCL, custom JSON and built-in JSON sources;
  # every semantic rule below is a named predicate evaluated once against it
  # and asserted by guards.tf. Native rules cannot live in variable validation
  # because a condition cannot reference a local derived from its own variable.
  definition_raw_entries = merge(
    local.native_definition_raw_entries,
    local.custom_definition_raw_entries,
    local.built_in_definition_raw_entries,
  )

  # The full built-in policy definition ID shape is shared by required-field
  # checks; kept as a named value so the predicate line stays readable.
  built_in_policy_definition_id_pattern = "^/providers/Microsoft\\.Authorization/policyDefinitions/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"

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

  definition_rule_names = [
    "source_type_valid",
    "field_exclusivity_valid",
    "field_allowlist_valid",
    "key_valid",
    "required_fields_valid",
    "scalar_types_valid",
    "metadata_valid",
    "parameters_valid",
    "version_format_valid",
    "version_intent_valid",
    "capability_containers_valid",
  ]

  definition_validation_records = {
    for origin, entry in local.definition_raw_entries :
    origin => {
      source_id     = origin
      catalogue_key = entry.catalogue_key
      rules = {
        # Rule class: source type. JSON adapters derive the source type from
        # the selected directory, so only native entries can fail this rule.
        source_type_valid = (
          entry.authoring_format == "json" ||
          entry.source_type == "custom" ||
          entry.source_type == "built_in"
        )

        # Rule class: source-type field exclusivity. JSON allowlists reject the
        # other source type's fields as a separate rule; native entries accept
        # the full canonical field set and are checked here. An unknown or
        # invalid source type passes this rule and fails source_type_valid.
        field_exclusivity_valid = try(
          (
            entry.source_type == "custom" &&
            length([
              for field in ["policy_definition_id", "version_constraint", "pinned_version"] : field
              if contains(keys(entry.document), field)
            ]) == 0
          ) ||
          (
            entry.source_type == "built_in" &&
            length([
              for field in ["policy_rule", "management_group_id", "version"] : field
              if contains(keys(entry.document), field)
            ]) == 0
          ) ||
          (entry.source_type != "custom" && entry.source_type != "built_in"),
          false
        )

        # Rule class: raw-field allowlist. Native entries are allowlisted at
        # the variable boundary; JSON envelopes are checked here so a failure
        # can name the offending file.
        field_allowlist_valid = entry.authoring_format == "hcl" ? true : (
          entry.source_type == "custom" ? try(
            can(keys(entry.document)) &&
            length(setsubtract(toset(keys(entry.document)), local.custom_envelope_fields)) == 0,
            false
            ) : try(
            can(keys(entry.document)) &&
            length(setsubtract(toset(keys(entry.document)), local.built_in_envelope_fields)) == 0,
            false
          )
        )

        # Rule class: stable catalogue key. One key rule for both authoring
        # formats: the native outer key and the JSON inline catalogue_key must
        # be a non-blank string with no surrounding whitespace. The
        # strict-string test runs first because trimspace coerces numbers and
        # booleans; rejecting surrounding whitespace, rather than trimming it,
        # stops a source mistake from silently renaming an identity between
        # key validation, grouping, projection and provenance. key_valid owns
        # the key's string test, so the required-field rule does not repeat it.
        key_valid = try(
          can(regex("^\\\".*\\\"$", jsonencode(entry.catalogue_key))) &&
          trimspace(entry.catalogue_key) != "" &&
          entry.catalogue_key == trimspace(entry.catalogue_key),
          false
        )

        # Rule class: required fields. display_name and the policy rule or
        # policy definition ID are read from the raw document; key_valid owns
        # the catalogue key checks. A missing or non-string display_name is
        # owned by scalar_types_valid, so this rule keeps only the non-blank
        # check for an actual string and does not cascade on a collection.
        required_fields_valid = entry.source_type == "custom" ? try(
          can(regex("^\\\".*\\\"$", jsonencode(entry.document.display_name))) &&
          trimspace(entry.document.display_name) != "" &&
          can(keys(entry.document.policy_rule)),
          false
          ) : entry.source_type == "built_in" ? try(
          can(regex("^\\\".*\\\"$", jsonencode(entry.document.display_name))) &&
          trimspace(entry.document.display_name) != "" &&
          can(regex(
            local.built_in_policy_definition_id_pattern,
            entry.document.policy_definition_id
          )),
          false
        ) : true

        # Rule class: scalar types. The consumer contract requires actual
        # strings and string functions coerce numbers and booleans, so this
        # rule proves the documented string fields are strict strings before
        # any trimspace-based rule accepts them: display_name is required; the
        # other documented string fields are null-or-string. The strict-string
        # test jsonencodes first so only a JSON string matches the
        # surrounding-quote regex. metadata.version resolves to null when
        # metadata is absent or null, so optional null behaviour is retained.
        scalar_types_valid = try(
          can(regex("^\\\".*\\\"$", jsonencode(entry.document.display_name))) &&
          (try(entry.document.name, null) == null || can(regex("^\\\".*\\\"$", jsonencode(entry.document.name)))) &&
          (try(entry.document.description, null) == null || can(regex("^\\\".*\\\"$", jsonencode(entry.document.description)))) &&
          (try(entry.document.mode, null) == null || can(regex("^\\\".*\\\"$", jsonencode(entry.document.mode)))) &&
          (try(entry.document.policy_definition_id, null) == null || can(regex("^\\\".*\\\"$", jsonencode(entry.document.policy_definition_id)))) &&
          (try(entry.document.management_group_id, null) == null || can(regex("^\\\".*\\\"$", jsonencode(entry.document.management_group_id)))) &&
          (try(entry.document.version, null) == null || can(regex("^\\\".*\\\"$", jsonencode(entry.document.version)))) &&
          (try(entry.document.version_constraint, null) == null || can(regex("^\\\".*\\\"$", jsonencode(entry.document.version_constraint)))) &&
          (try(entry.document.pinned_version, null) == null || can(regex("^\\\".*\\\"$", jsonencode(entry.document.pinned_version)))) &&
          (try(entry.document.metadata.version, null) == null || can(regex("^\\\".*\\\"$", jsonencode(entry.document.metadata.version)))),
          false
        )

        # Rule class: metadata container. Null keeps the unknown state; an
        # explicitly supplied object stays structured.
        metadata_valid = (
          try(entry.document.metadata, null) == null ||
          can(keys(entry.document.metadata))
        )

        # Rule class: parameters container. Null keeps the unknown state; an
        # explicitly supplied object stays structured.
        parameters_valid = (
          try(entry.document.parameters, null) == null ||
          can(keys(entry.document.parameters))
        )

        # Rule class: version format. Custom entries require one exact
        # three-part version in version or metadata.version. Built-in entries
        # validate the format of whichever version field is supplied;
        # version_intent_valid enforces exactly one.
        version_format_valid = entry.source_type == "custom" ? (
          (
            try(trimspace(entry.document.version), "") != "" &&
            can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", trimspace(entry.document.version)))
          ) ||
          (
            try(trimspace(entry.document.metadata.version), "") != "" &&
            can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", trimspace(entry.document.metadata.version)))
          )
          ) : entry.source_type == "built_in" ? (
          (
            try(trimspace(entry.document.version_constraint), "") == "" ||
            can(regex("^[0-9]+\\.([0-9]+|\\*)\\.\\*$", trimspace(entry.document.version_constraint)))
          ) &&
          (
            try(trimspace(entry.document.pinned_version), "") == "" ||
            can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", trimspace(entry.document.pinned_version)))
          )
        ) : true

        # Rule class: version intent. Custom entries must use matching version
        # and metadata.version values when both are supplied. Built-in
        # references require exactly one of version_constraint or
        # pinned_version.
        version_intent_valid = entry.source_type == "custom" ? try(
          !(
            try(trimspace(entry.document.version), "") != "" &&
            try(trimspace(entry.document.metadata.version), "") != "" &&
            trimspace(entry.document.version) != trimspace(entry.document.metadata.version)
          ),
          false
          ) : entry.source_type == "built_in" ? try(
          (
            try(trimspace(entry.document.version_constraint), "") != "" &&
            try(trimspace(entry.document.pinned_version), "") == ""
          ) ||
          (
            try(trimspace(entry.document.version_constraint), "") == "" &&
            try(trimspace(entry.document.pinned_version), "") != ""
          ),
          false
        ) : true

        # Rule class: capability and governance containers. Null keeps the
        # unknown state; an explicitly supplied empty collection stays empty.
        # Checks are structural only; behaviour resolution and governance
        # consumers own the meaning of supplied keys. Strict string check:
        # jsonencode first so only a JSON string matches the surrounding-quote
        # regex; a plain regex would coerce numbers and booleans to text.
        capability_containers_valid = try(
          (try(entry.document.supported_effects, null) == null || (
            can(concat(entry.document.supported_effects, [])) &&
            alltrue([
              for effect in entry.document.supported_effects :
              can(regex("^\\\".*\\\"$", jsonencode(effect))) && trimspace(effect) != ""
            ])
          )) &&
          (try(entry.document.supported_overrides, null) == null || (
            can(concat(entry.document.supported_overrides, [])) &&
            alltrue([for override in entry.document.supported_overrides : can(keys(override))])
          )) &&
          (try(entry.document.selectors, null) == null || (
            can(concat(entry.document.selectors, [])) &&
            alltrue([for selector in entry.document.selectors : can(keys(selector))])
          )) &&
          (try(entry.document.non_compliance_messages, null) == null || can(keys(entry.document.non_compliance_messages))) &&
          (try(entry.document.capabilities, null) == null || can(keys(entry.document.capabilities))) &&
          (try(entry.document.governance, null) == null || can(keys(entry.document.governance))),
          false
        )
      }
    }
  }

  # Canonical projection: one object shape per entry, applied once for every
  # authoring path. Every canonical field is read from the raw document with
  # the same guarded access the native path always used, so null-versus-empty
  # and structured value types are preserved verbatim. Source-type-inapplicable
  # fields are null because the allowlists and exclusivity rule never supply
  # them, not because the projection forces them.
  #
  # Custom JSON envelopes never carry policy_definition_id, so that key stays
  # absent for the custom JSON path exactly as before; every other path
  # projects it, null when not applicable. Attribute access distinguishes an
  # absent key from a null one, so this shape is preserved deliberately.
  definition_projected_entries = {
    for origin, entry in local.definition_raw_entries :
    origin => merge(
      {
        source_type             = entry.source_type
        name                    = try(entry.document.name, null)
        display_name            = try(entry.document.display_name, null)
        description             = try(entry.document.description, null)
        mode                    = try(entry.document.mode, null)
        metadata                = try(entry.document.metadata, null)
        parameters              = entry.parameters
        policy_rule             = try(entry.document.policy_rule, null)
        management_group_id     = try(entry.document.management_group_id, null)
        role_definition_ids     = try(entry.document.role_definition_ids, null)
        supported_effects       = try(entry.document.supported_effects, null)
        supported_overrides     = try(entry.document.supported_overrides, null)
        selectors               = try(entry.document.selectors, null)
        non_compliance_messages = try(entry.document.non_compliance_messages, null)
        capabilities            = try(entry.document.capabilities, null)
        governance              = try(entry.document.governance, null)
        version                 = try(entry.document.version, null)
        version_constraint      = try(entry.document.version_constraint, null)
        pinned_version          = try(entry.document.pinned_version, null)
      },
      entry.authoring_format == "json" && entry.source_type == "custom" ? {} : {
        policy_definition_id = try(entry.document.policy_definition_id, null)
      }
    )
  }
}
