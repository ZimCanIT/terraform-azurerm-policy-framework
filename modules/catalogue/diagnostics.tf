locals {
  # Diagnostics stage: every failure-string map and the bounded human-readable
  # text the guard preconditions interpolate. One failure string per failing
  # entry, member, group or companion and rule; each string names the source
  # key or file and the failed rule.

  definition_rule_failures = {
    for rule in local.definition_rule_names :
    rule => [
      for origin, record in local.definition_validation_records :
      "${record.source_id} (catalogue key ${jsonencode(record.catalogue_key)}): failed ${rule}"
      if !record.rules[rule]
    ]
  }

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

  initiative_companion_failures = {
    companion_parent_valid = [
      for path in local.orphan_initiative_parameter_files :
      "json:${local.initiative_parameter_source_paths[path]}: failed companion_parent_valid"
    ]
    companion_conflict_valid = [
      for path in local.initiative_parameter_conflict_stems :
      "json:${path}.json: failed companion_conflict_valid"
    ]
    companion_object_valid = [
      for path in local.non_object_initiative_parameter_files :
      "json:${path}: failed companion_object_valid"
    ]
  }

  initiative_entry_rule_failures = {
    for rule in local.initiative_entry_rule_names :
    rule => [
      for source_id, record in local.initiative_entry_validation_records :
      "${record.source_id} (catalogue key ${jsonencode(record.catalogue_key)}): failed ${rule}"
      if !record.rules[rule]
    ]
  }

  initiative_reference_rule_failures = {
    for rule in local.initiative_reference_rule_names :
    rule => [
      for record in local.initiative_reference_validation_records :
      "${record.source_id} member ${jsonencode(record.reference_id)}: failed ${rule}"
      if !record.rules[rule]
    ]
  }

  initiative_group_rule_failures = {
    for rule in local.initiative_group_rule_names :
    rule => [
      for record in local.initiative_group_validation_records :
      "${record.source_id} group ${jsonencode(record.group_name)}: failed ${rule}"
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

  # The preconditions read their text from these aliases so each diagnostic
  # resolves to the matching rule list.
  definition_failure_text           = local.catalogue_failure_text.definition
  definition_companion_text         = local.catalogue_failure_text.definition_companion
  initiative_entry_failure_text     = local.catalogue_failure_text.initiative_entry
  initiative_reference_failure_text = local.catalogue_failure_text.initiative_reference
  initiative_group_failure_text     = local.catalogue_failure_text.initiative_group
  initiative_companion_failure_text = local.catalogue_failure_text.initiative_companion
}
