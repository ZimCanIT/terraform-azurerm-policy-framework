# Both ingestion guards declare no input: storing catalogue payload in state
# would make policy content part of a validation resource and create
# content-change plans.

resource "terraform_data" "json_ingestion_contract" {
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

resource "terraform_data" "initiative_ingestion_contract" {
  lifecycle {
    precondition {
      condition     = var.initiative_directory == null || var.allow_empty_sources || length(local.initiative_json_tree_files) > 0
      error_message = "initiative_directory was opted in but contains no files (the path may be missing or empty); add a top-level JSON envelope or set allow_empty_sources = true explicitly."
    }

    precondition {
      condition     = length(local.nested_initiative_files) == 0
      error_message = "Initiative JSON source directories are flat; nested files are unsupported: ${join(", ", local.nested_initiative_files)}."
    }

    precondition {
      condition     = length(local.unsupported_initiative_files) == 0
      error_message = "Initiative JSON source directories may contain only top-level .json files: ${join(", ", local.unsupported_initiative_files)}."
    }

    precondition {
      condition     = length(local.malformed_initiative_json_files) == 0
      error_message = "Malformed initiative JSON source envelope(s): ${join(", ", local.malformed_initiative_json_files)}."
    }

    precondition {
      condition = length(local.initiative_companion_failures.companion_object_valid) == 0
      error_message = join("", [
        "Initiative parameter companion files must contain a JSON object; null, arrays, strings, numbers and booleans are unsupported. ",
        "Failures: ${local.initiative_companion_failure_text.companion_object_valid}",
      ])
    }

    precondition {
      condition     = length(local.initiative_companion_failures.companion_parent_valid) == 0
      error_message = "Each initiative *-parameters.json file must have a matching initiative envelope JSON file. Failures: ${local.initiative_companion_failure_text.companion_parent_valid}"
    }

    precondition {
      condition = length(local.initiative_companion_failures.companion_conflict_valid) == 0
      error_message = join("", [
        "An initiative envelope and its *-parameters.json companion cannot both contain non-null parameters; remove one source. ",
        "Failures: ${local.initiative_companion_failure_text.companion_conflict_valid}",
      ])
    }

    # Named initiative envelope rules. Each precondition asserts one rule from
    # initiatives-validation.tf so a failure names the rule and the offending
    # source key or file.
    precondition {
      condition     = length(local.initiative_entry_rule_failures.field_allowlist_valid) == 0
      error_message = "Initiative envelopes may use only documented fields. Failures: ${local.initiative_entry_failure_text.field_allowlist_valid}"
    }

    precondition {
      condition = length(local.initiative_entry_rule_failures.key_valid) == 0
      error_message = join("", [
        "Initiative catalogue keys must be non-blank strings with no surrounding whitespace; native outer keys and JSON inline keys use the same rule. ",
        "Failures: ${local.initiative_entry_failure_text.key_valid}",
      ])
    }

    precondition {
      condition = length(local.initiative_entry_rule_failures.required_fields_valid) == 0
      error_message = join("", [
        "Initiative envelopes require a display name and at least one policy_definition_references member. ",
        "Failures: ${local.initiative_entry_failure_text.required_fields_valid}",
      ])
    }

    precondition {
      condition     = length(local.initiative_entry_rule_failures.scalar_types_valid) == 0
      error_message = "Initiative documented string fields must be strings when supplied. Failures: ${local.initiative_entry_failure_text.scalar_types_valid}"
    }

    precondition {
      condition     = length(local.initiative_entry_rule_failures.metadata_valid) == 0
      error_message = "Initiative metadata must be an object when supplied. Failures: ${local.initiative_entry_failure_text.metadata_valid}"
    }

    precondition {
      condition     = length(local.initiative_entry_rule_failures.parameters_valid) == 0
      error_message = "Initiative parameters must be an object when supplied. Failures: ${local.initiative_entry_failure_text.parameters_valid}"
    }

    precondition {
      condition     = length(local.initiative_entry_rule_failures.governance_valid) == 0
      error_message = "Initiative governance must be an object when supplied. Failures: ${local.initiative_entry_failure_text.governance_valid}"
    }

    precondition {
      condition     = length(local.initiative_entry_rule_failures.version_valid) == 0
      error_message = "Initiative version must be an exact three-part version when supplied. Failures: ${local.initiative_entry_failure_text.version_valid}"
    }

    precondition {
      condition     = length(local.initiative_entry_rule_failures.group_container_valid) == 0
      error_message = "Initiative policy_definition_groups must be a list of group objects when supplied. Failures: ${local.initiative_entry_failure_text.group_container_valid}"
    }

    precondition {
      condition     = length(local.initiative_entry_rule_failures.group_names_unique_valid) == 0
      error_message = "Initiative group names must be unique case-insensitively within each initiative. Failures: ${local.initiative_entry_failure_text.group_names_unique_valid}"
    }

    precondition {
      condition     = length(local.initiative_entry_rule_failures.reference_ids_unique_valid) == 0
      error_message = "Initiative member reference_id values must be unique case-insensitively within each initiative. Failures: ${local.initiative_entry_failure_text.reference_ids_unique_valid}"
    }

    # Named member reference rules.
    precondition {
      condition     = length(local.initiative_reference_rule_failures.container_valid) == 0
      error_message = "Initiative policy_definition_references must be a list of member objects. Failures: ${local.initiative_reference_failure_text.container_valid}"
    }

    precondition {
      condition     = length(local.initiative_reference_rule_failures.field_allowlist_valid) == 0
      error_message = "Initiative member references may use only documented fields. Failures: ${local.initiative_reference_failure_text.field_allowlist_valid}"
    }

    precondition {
      condition     = length(local.initiative_reference_rule_failures.required_fields_valid) == 0
      error_message = "Each initiative member requires a non-blank reference_id. Failures: ${local.initiative_reference_failure_text.required_fields_valid}"
    }

    precondition {
      condition     = length(local.initiative_reference_rule_failures.scalar_types_valid) == 0
      error_message = "Initiative member identity fields must be strings when supplied. Failures: ${local.initiative_reference_failure_text.scalar_types_valid}"
    }

    precondition {
      condition = length(local.initiative_reference_rule_failures.reference_source_valid) == 0
      error_message = join("", [
        "Each initiative member must be either a keyed definition_key or a direct policy_definition_id, never both and never neither. ",
        "Failures: ${local.initiative_reference_failure_text.reference_source_valid}",
      ])
    }

    precondition {
      condition = length(local.initiative_reference_rule_failures.direct_definition_id_valid) == 0
      error_message = join("", [
        "Direct initiative member policy_definition_id values must be a built-in root ID, a subscription-scoped ID or a ",
        "management-group-scoped ID. Failures: ${local.initiative_reference_failure_text.direct_definition_id_valid}",
      ])
    }

    precondition {
      condition     = length(local.initiative_reference_rule_failures.parameters_valid) == 0
      error_message = "Initiative member parameter_values must be an object when supplied. Failures: ${local.initiative_reference_failure_text.parameters_valid}"
    }

    precondition {
      condition     = length(local.initiative_reference_rule_failures.group_names_container_valid) == 0
      error_message = "Initiative member group_names must be null or a list when supplied. Failures: ${local.initiative_reference_failure_text.group_names_container_valid}"
    }

    precondition {
      condition = length(local.initiative_reference_rule_failures.group_names_valid) == 0
      error_message = join("", [
        "Initiative member group_names must be unique non-blank names of groups declared on the same initiative. ",
        "Failures: ${local.initiative_reference_failure_text.group_names_valid}",
      ])
    }

    precondition {
      condition = length(local.initiative_reference_rule_failures.version_intent_valid) == 0
      error_message = join("", [
        "Direct initiative members require exactly one of version_constraint or pinned_version; keyed members may omit both (inheritance). ",
        "Failures: ${local.initiative_reference_failure_text.version_intent_valid}",
      ])
    }

    precondition {
      condition = length(local.initiative_reference_rule_failures.version_format_valid) == 0
      error_message = join("", [
        "Initiative member version_constraint must be major.*.* or major.minor.* and pinned_version must be an exact x.y.z; ",
        "supplying both is rejected. Failures: ${local.initiative_reference_failure_text.version_format_valid}",
      ])
    }

    # Named group rules.
    precondition {
      condition     = length(local.initiative_group_rule_failures.field_allowlist_valid) == 0
      error_message = "Initiative group records may use only name, display_name, description and metadata. Failures: ${local.initiative_group_failure_text.field_allowlist_valid}"
    }

    precondition {
      condition     = length(local.initiative_group_rule_failures.required_fields_valid) == 0
      error_message = "Initiative group records require a non-blank name and display_name. Failures: ${local.initiative_group_failure_text.required_fields_valid}"
    }

    precondition {
      condition     = length(local.initiative_group_rule_failures.scalar_types_valid) == 0
      error_message = "Initiative group name, display_name and description must be strings when supplied. Failures: ${local.initiative_group_failure_text.scalar_types_valid}"
    }

    precondition {
      condition     = length(local.initiative_group_rule_failures.metadata_valid) == 0
      error_message = "Initiative group metadata must be an object when supplied. Failures: ${local.initiative_group_failure_text.metadata_valid}"
    }

    precondition {
      condition     = length(local.json_duplicate_initiative_keys) == 0
      error_message = "JSON initiative catalogue keys must be unique case-insensitively (collisions: ${join(", ", local.json_duplicate_initiative_keys)})."
    }
  }
}
