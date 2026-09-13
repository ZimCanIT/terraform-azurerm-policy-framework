locals {
  # Shared definition adaptation and semantic validation.
  #
  # The native HCL adapter (hcl.tf) and the JSON adapters (json.tf) each read
  # their source and declare common raw-entry records in
  # local.native_definition_raw_entries, local.custom_definition_raw_entries and
  # local.built_in_definition_raw_entries. Every record exposes the same view:
  # catalogue and projection keys, authoring format, resolved source type, the
  # raw document and the source-selected parameters value. Semantic rules that
  # apply to more than one path are implemented once against this view.
  #
  # Each raw entry is then wrapped in a validation record carrying a fixed set
  # of named boolean rules. Every rule is an independent predicate, so a
  # failure can name the offending source file or catalogue key and the failed
  # rule instead of collapsing several rule classes into one boolean. The
  # blocking preconditions in json.tf assert each rule separately.
  #
  # Native field semantics cannot live in variable validation: a validation
  # condition may only reference the variable it guards, and referencing a
  # local derived from that variable is a dependency cycle (verified against
  # Terraform 1.15.9). The rules below are therefore enforced as preconditions
  # on terraform_data.json_ingestion_contract in json.tf. Only cheap outer-shape
  # checks remain at the native variable boundary.
  definition_raw_entries = merge(
    local.native_definition_raw_entries,
    local.custom_definition_raw_entries,
    local.built_in_definition_raw_entries,
  )

  # The full built-in policy definition ID shape is shared by required-field
  # checks; kept as a named value so the predicate line stays readable.
  built_in_policy_definition_id_pattern = "^/providers/Microsoft\\.Authorization/policyDefinitions/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"

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

  # One failure string per failing entry and rule. Each string names the source
  # file or key, the catalogue key and the failed rule.
  definition_rule_failures = {
    for rule in local.definition_rule_names :
    rule => [
      for origin, record in local.definition_validation_records :
      "${record.source_id} (catalogue key ${jsonencode(record.catalogue_key)}): failed ${rule}"
      if !record.rules[rule]
    ]
  }

  # Bounded, human-readable text for every named-rule failure list in the
  # module. Preconditions assert one rule each and interpolate the matching
  # text, so a diagnostic always names the failed rule and a bounded number of
  # offending sources instead of an unbounded dump.
  catalogue_failure_text = {
    for scope, rule_failures in {
      definition           = local.definition_rule_failures
      definition_companion = local.definition_companion_failures
      initiative_entry     = local.initiative_entry_rule_failures
      initiative_reference = local.initiative_reference_rule_failures
      initiative_group     = local.initiative_group_rule_failures
      initiative_companion = local.initiative_companion_failures
    } :
    scope => {
      for rule, failures in rule_failures :
      rule => join("", [
        join("; ", slice(failures, 0, min(3, length(failures)))),
        length(failures) > 3 ? "; and ${length(failures) - 3} more" : "",
      ])
    }
  }

  # The preconditions read their text from these aliases so the definition
  # diagnostics resolve to the matching rule list.
  definition_failure_text   = local.catalogue_failure_text.definition
  definition_companion_text = local.catalogue_failure_text.definition_companion

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
