locals {
  # Initiative member reference validation: one named rule record per member
  # reference. The entry view and member-record plumbing live in
  # initiatives-validation.tf; a malformed container produces one synthetic
  # record with container_ok = false, and every semantic rule is marked not
  # applicable on that record so the container defect is the only reported
  # failure rather than cascading rule diagnostics.

  initiative_reference_fields = toset([
    "reference_id", "definition_key", "policy_definition_id", "parameter_values",
    "group_names", "version_constraint", "pinned_version"
  ])

  # Azure policy definitions can be referenced by a root built-in ID or by a
  # fully-qualified externally managed custom definition at subscription or
  # management-group scope. Resource/module IDs and bare custom names are not
  # portable references and are intentionally rejected.
  valid_policy_definition_id = [
    "^/providers/Microsoft\\.Authorization/policyDefinitions/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$",
    "^/subscriptions/[0-9a-fA-F-]{36}/providers/Microsoft\\.Authorization/policyDefinitions/[^/]+$",
    "^/providers/Microsoft\\.Management/managementGroups/[^/]+/providers/Microsoft\\.Authorization/policyDefinitions/[^/]+$",
  ]

  initiative_reference_rule_names = [
    "container_valid",
    "field_allowlist_valid",
    "required_fields_valid",
    "scalar_types_valid",
    "reference_source_valid",
    "direct_definition_id_valid",
    "parameters_valid",
    "group_names_container_valid",
    "group_names_valid",
    "version_intent_valid",
    "version_format_valid",
  ]

  initiative_reference_validation_records = [
    for record in local.initiative_reference_records : {
      source_id    = record.source_id
      reference_id = try(trimspace(record.reference.reference_id), "")
      rules = {
        # Rule class: reference container. The container must be a list, not
        # an object-keyed map or scalar; container_ok records whether the
        # shape probe accepted the collection and its members iterated.
        container_valid = record.container_ok

        # Rule class: raw-field allowlist.
        field_allowlist_valid = record.container_ok ? try(
          can(keys(record.reference)) &&
          length(setsubtract(toset(keys(record.reference)), local.initiative_reference_fields)) == 0,
          false
        ) : true

        # Rule class: required fields. Every member requires a non-blank
        # reference_id.
        required_fields_valid = record.container_ok ? try(
          can(regex("^\\\".*\\\"$", jsonencode(record.reference.reference_id))) &&
          trimspace(record.reference.reference_id) != "",
          false
        ) : true

        # Rule class: strict scalar types. Member identity fields must be
        # actual strings when supplied; null keeps the absent state and
        # required_fields_valid owns required presence. Strict string check:
        # jsonencode first so only a JSON string matches the surrounding-quote
        # regex; a plain regex would coerce numbers and booleans to text.
        scalar_types_valid = record.container_ok ? (
          (try(record.reference.reference_id, null) == null ||
          can(regex("^\\\".*\\\"$", jsonencode(record.reference.reference_id)))) &&
          (try(record.reference.definition_key, null) == null ||
          can(regex("^\\\".*\\\"$", jsonencode(record.reference.definition_key)))) &&
          (try(record.reference.policy_definition_id, null) == null ||
          can(regex("^\\\".*\\\"$", jsonencode(record.reference.policy_definition_id)))) &&
          (try(record.reference.version_constraint, null) == null ||
          can(regex("^\\\".*\\\"$", jsonencode(record.reference.version_constraint)))) &&
          (try(record.reference.pinned_version, null) == null ||
          can(regex("^\\\".*\\\"$", jsonencode(record.reference.pinned_version))))
        ) : true

        # Rule class: direct-versus-keyed source exclusivity. A member is
        # either a catalogue definition_key or a direct policy_definition_id,
        # never both and never neither.
        reference_source_valid = record.container_ok ? try(
          (
            try(record.reference.definition_key, null) != null &&
            trimspace(record.reference.definition_key) != "" &&
            try(record.reference.policy_definition_id, null) == null
          ) ||
          (
            try(record.reference.definition_key, null) == null &&
            try(record.reference.policy_definition_id, null) != null &&
            trimspace(record.reference.policy_definition_id) != ""
          ),
          false
        ) : true

        # Rule class: direct policy definition ID format. Keyed members
        # inherit the referenced definition's ID and pass this rule.
        direct_definition_id_valid = record.container_ok ? try(
          try(record.reference.definition_key, null) != null && trimspace(record.reference.definition_key) != "" ||
          anytrue([
            for pattern in local.valid_policy_definition_id :
            can(regex(pattern, record.reference.policy_definition_id))
          ]),
          false
        ) : true

        # Rule class: parameter_values container. Null keeps the definition's
        # defaults; a supplied value must be an object.
        parameters_valid = record.container_ok ? (
          try(record.reference.parameter_values, null) == null ||
          can(keys(record.reference.parameter_values))
        ) : true

        # Rule class: group_names container. Null is allowed; a supplied
        # value must be a non-keyed collection whose element iteration is
        # safe. The probe is non-raising so a malformed group_names cannot
        # abort the member-container try fallback and misreport the member
        # container.
        group_names_container_valid = record.container_ok ? record.group_names_container_ok : true

        # Rule class: group_names semantics. Guarded behind
        # group_names_container_valid; a supplied list must hold unique,
        # non-blank strings that name groups declared on the same
        # initiative. Strict string check: jsonencode first so only a JSON
        # string matches the surrounding-quote regex; a plain regex would
        # coerce numbers and booleans to text.
        group_names_valid = record.container_ok ? (
          !record.group_names_container_ok ||
          try(record.reference.group_names, null) == null || (
            alltrue([
              for group_name in record.reference.group_names :
              can(regex("^\\\".*\\\"$", jsonencode(group_name))) &&
              trimspace(group_name) != "" &&
              contains(local.initiative_group_names[record.source_id], lower(trimspace(group_name)))
            ]) &&
            length(distinct([
              for group_name in record.reference.group_names : lower(trimspace(group_name))
            ])) == length([for group_name in record.reference.group_names : group_name])
          )
        ) : true

        # Rule class: version intent. Direct members require exactly one of
        # version_constraint or pinned_version; keyed members inherit the
        # referenced definition's intent when both are omitted.
        version_intent_valid = record.container_ok ? try(
          try(trimspace(record.reference.definition_key), "") != "" ||
          (
            (
              try(trimspace(record.reference.version_constraint), "") != "" &&
              try(trimspace(record.reference.pinned_version), "") == ""
            ) ||
            (
              try(trimspace(record.reference.version_constraint), "") == "" &&
              try(trimspace(record.reference.pinned_version), "") != ""
            )
          ),
          false
        ) : true

        # Rule class: version format. Whichever intent is supplied must match
        # its documented format; supplying both is rejected by
        # version_intent_valid and by this rule.
        version_format_valid = record.container_ok ? (
          (
            try(trimspace(record.reference.version_constraint), "") == "" ||
            can(regex("^[0-9]+\\.([0-9]+|\\*)\\.\\*$", trimspace(record.reference.version_constraint)))
          ) &&
          (
            try(trimspace(record.reference.pinned_version), "") == "" ||
            can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", trimspace(record.reference.pinned_version)))
          ) &&
          !(
            try(trimspace(record.reference.version_constraint), "") != "" &&
            try(trimspace(record.reference.pinned_version), "") != ""
          )
        ) : true
      }
    }
  ]
}
