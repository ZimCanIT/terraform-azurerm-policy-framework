locals {
  initiative_envelope_fields = toset([
    "catalogue_key", "name", "display_name", "description", "metadata", "parameters",
    "policy_definition_references", "policy_definition_groups", "management_group_id", "governance", "version"
  ])

  initiative_reference_fields = toset([
    "reference_id", "definition_key", "policy_definition_id", "parameter_values",
    "group_names", "effect", "required", "version_constraint", "pinned_version"
  ])

  initiative_group_fields = toset(["name", "display_name", "description", "metadata"])

  initiative_entries = {
    for key, initiative in var.initiatives : key => {
      catalogue_key                = key
      name                         = try(trimspace(initiative.name), "") != "" ? trimspace(initiative.name) : null
      display_name                 = try(initiative.display_name, null)
      description                  = try(initiative.description, null)
      metadata                     = try(initiative.metadata, null)
      parameters                   = try(initiative.parameters, null)
      management_group_id          = try(trimspace(initiative.management_group_id), "") != "" ? trimspace(initiative.management_group_id) : null
      governance                   = try(initiative.governance, null)
      version                      = try(trimspace(initiative.version), "") != "" ? trimspace(initiative.version) : null
      policy_definition_references = try(initiative.policy_definition_references, null)
      policy_definition_groups     = try(initiative.policy_definition_groups, null)
    }
  }

  initiative_group_names = {
    for key, initiative in local.initiative_entries : key => try([
      for group in initiative.policy_definition_groups : lower(trimspace(group.name))
    ], [])
  }

  initiative_reference_records = flatten([
    for key, initiative in local.initiative_entries : try([
      for index, reference in initiative.policy_definition_references : {
        source_key = key
        index      = index
        reference  = reference
      }
    ], [])
  ])

  # One normalised view per member reference: member-supplied intent, the
  # referenced definition entry and the owning initiative are adapted once;
  # validation rules, version decisions and projections read this view rather
  # than re-deriving raw fields.
  initiative_member_views = {
    for record in local.initiative_reference_records :
    "${record.source_key}/${record.index}" => {
      source_key                    = record.source_key
      index                         = record.index
      reference                     = record.reference
      initiative                    = local.initiative_entries[record.source_key]
      reference_id                  = try(trimspace(record.reference.reference_id), "")
      is_keyed                      = try(trimspace(record.reference.definition_key), "") != ""
      definition_key                = try(trimspace(record.reference.definition_key), "") != "" ? trimspace(record.reference.definition_key) : null
      definition                    = try(trimspace(record.reference.definition_key), "") != "" && contains(keys(local.definitions), trimspace(record.reference.definition_key)) ? local.definitions[trimspace(record.reference.definition_key)] : null
      supplied_version_constraint   = try(trimspace(record.reference.version_constraint), "") != "" ? trimspace(record.reference.version_constraint) : null
      supplied_pinned_version       = try(trimspace(record.reference.pinned_version), "") != "" ? trimspace(record.reference.pinned_version) : null
      supplied_policy_definition_id = try(trimspace(record.reference.policy_definition_id), "") != "" ? trimspace(record.reference.policy_definition_id) : null
      supplied_parameter_values     = try(record.reference.parameter_values, null)
      supplied_group_names          = try(record.reference.group_names, null)
      supplied_effect               = try(trimspace(record.reference.effect), "") != "" ? trimspace(record.reference.effect) : null
      supplied_required             = try(record.reference.required, null)
    }
  }

  # Inherited version is the definition's built-in constraint intent only; a
  # custom content version is provenance, never member version intent. The
  # policy-definition ID resolves from the definition for keyed members only;
  # a missing definition resolves to null and fails its named rules.
  initiative_member_definition_intent = {
    for member_key, view in local.initiative_member_views : member_key => {
      inherited_version    = view.is_keyed && view.definition != null ? view.definition.version_constraint : null
      policy_definition_id = view.is_keyed ? (view.definition != null ? view.definition.id : null) : view.supplied_policy_definition_id
    }
  }

  # One provider-version projection per member record, shared by the
  # validation rule and the resource block. Candidates are tried in precedence
  # order against the AzureRM grammar, which accepts only major.minor or
  # major.minor.* member versions; exact pins stay canonical intent and are
  # deliberately rejected at this boundary.
  initiative_member_provider_versions = {
    for member_key, view in local.initiative_member_views :
    member_key => try([
      for candidate in concat(
        [view.supplied_version_constraint, view.supplied_pinned_version],
        view.is_keyed && view.definition != null ? [view.definition.version_constraint, view.definition.pinned_version] : []
      ) : candidate
      if candidate != null && can(regex("^[0-9]+\\.[0-9]+(\\.\\*)?(-preview)?$", candidate))
    ][0], null)
  }

  # A member requires provider version representation when it declares a
  # version selector or inherits one from a keyed definition's built-in
  # intent. Custom content versions are not member version intent.
  initiative_member_version_intent = {
    for member_key, view in local.initiative_member_views :
    member_key => view.supplied_version_constraint != null || view.supplied_pinned_version != null || (
      view.is_keyed && view.definition != null &&
      (view.definition.version_constraint != null || view.definition.pinned_version != null)
    )
  }

  # Selected version precedence: member selector, then inherited definition
  # intent; all-absent resolves to null (unknown), never a fabricated value.
  initiative_member_selected_versions = {
    for member_key, view in local.initiative_member_views :
    member_key => try(coalesce(view.supplied_version_constraint, view.supplied_pinned_version, local.initiative_member_definition_intent[member_key].inherited_version), null)
  }

  # Validate definition-member and initiative-set parameter schemas through
  # one common view. Null schemas stay unknown; supplied schemas are checked
  # against Azure Policy's seven declared value types.
  azure_policy_parameter_types = toset(["array", "boolean", "datetime", "float", "integer", "object", "string"])

  parameter_schema_contexts = merge(
    {
      for key, definition in local.definitions : "definition:${key}" => {
        owner_type = "definition"
        owner_key  = key
        schema     = definition.parameters
      }
    },
    {
      for key, initiative in local.initiative_entries : "initiative:${key}" => {
        owner_type = "initiative"
        owner_key  = key
        schema     = initiative.parameters
      }
    }
  )

  parameter_schema_context_failures = [
    for context_key, context in local.parameter_schema_contexts :
    "${context.owner_type} ${jsonencode(context.owner_key)}: failed parameter_schema_container_valid"
    if context.schema != null && !can(keys(context.schema))
  ]

  parameter_schema_fields = flatten([
    for context_key, context in local.parameter_schema_contexts : try([
      for parameter_name, parameter in context.schema : {
        field_id               = "${context_key}/${jsonencode(parameter_name)}"
        owner_type             = context.owner_type
        owner_key              = context.owner_key
        parameter_name         = parameter_name
        parameter              = parameter
        parameter_type         = try(lower(parameter.type), "")
        parameter_object_valid = can(keys(parameter))
        parameter_type_valid   = try(can(regex("^\\\".*\\\"$", jsonencode(parameter.type))) && contains(local.azure_policy_parameter_types, lower(parameter.type)), false)
        allowed_values_present = try(contains(keys(parameter), "allowedValues"), false)
        allowed_values_container_valid = try(
          !contains(keys(parameter), "allowedValues") ||
          (!can(keys(parameter.allowedValues)) && startswith(jsonencode(parameter.allowedValues), "[")),
          false
        )
        default_value_present = try(contains(keys(parameter), "defaultValue"), false)
      }
    ], []) if context.schema != null
  ])

  parameter_schema_value_records = flatten([
    for field in local.parameter_schema_fields : concat(
      field.default_value_present ? [{
        field_id       = field.field_id
        parameter_type = field.parameter_type
        value          = try(field.parameter.defaultValue, null)
      }] : [],
      field.allowed_values_present && field.parameter_type != "array" ? try([
        for allowed_value in field.parameter.allowedValues : {
          field_id       = field.field_id
          parameter_type = field.parameter_type
          value          = allowed_value
        }
      ], []) : []
    )
  ])

  # Every typed literal (schema defaults, scalar allowed values and member
  # literal mappings) is checked against Azure's seven parameter types here,
  # once. Strict JSON shape checks avoid Terraform's string coercion.
  typed_value_records = concat(
    [for index, record in local.parameter_schema_value_records : merge(record, { check_id = "schema/${index}" })],
    [
      for index, record in local.initiative_parameter_mapping_records : {
        check_id       = "mapping/${index}"
        parameter_type = record.target_parameter_type
        value          = record.value
      } if record.mapping_shape_valid && record.target_schema_known && !record.binding_candidate
    ]
  )

  typed_value_valid = {
    for record in local.typed_value_records : record.check_id => try(
      (record.parameter_type == "string" && can(regex("^\\\".*\\\"$", jsonencode(record.value)))) ||
      (record.parameter_type == "array" && startswith(jsonencode(record.value), "[")) ||
      (record.parameter_type == "object" && can(keys(record.value))) ||
      (record.parameter_type == "boolean" && can(regex("^(true|false)$", jsonencode(record.value)))) ||
      (record.parameter_type == "integer" && can(regex("^-?(0|[1-9][0-9]*)(\\.[0-9]+)?([eE][+-]?[0-9]+)?$", jsonencode(record.value))) && floor(record.value) == record.value) ||
      (record.parameter_type == "float" && can(regex("^-?(0|[1-9][0-9]*)(\\.[0-9]+)?([eE][+-]?[0-9]+)?$", jsonencode(record.value)))) ||
      (record.parameter_type == "datetime" && can(regex("^\\\".*\\\"$", jsonencode(record.value))) && can(regex("^[0-9]{4}-(0[1-9]|1[0-2])-([0-2][0-9]|3[01])T([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9](\\.[0-9]+)?(Z|[+-]([01][0-9]|2[0-3]):[0-5][0-9])$", record.value)) && can(formatdate("", record.value))),
      false
    )
  }

  parameter_schema_value_type_checks = [
    for index, record in local.parameter_schema_value_records : {
      field_id = record.field_id
      valid    = local.typed_value_valid["schema/${index}"]
    }
  ]

  parameter_schema_failures = concat(
    local.parameter_schema_context_failures,
    [
      for field in local.parameter_schema_fields :
      "${field.owner_type} ${jsonencode(field.owner_key)} parameter ${jsonencode(field.parameter_name)}: failed parameter_schema_valid"
      if !(
        field.parameter_object_valid &&
        field.parameter_type_valid &&
        field.allowed_values_container_valid &&
        alltrue([for check in local.parameter_schema_value_type_checks : check.valid if check.field_id == field.field_id]) &&
        (!field.default_value_present || !field.allowed_values_present || try(
          field.parameter_type == "array" ?
          alltrue([for element in field.parameter.defaultValue : anytrue([for allowed_value in field.parameter.allowedValues : jsonencode(element) == jsonencode(allowed_value)])]) :
          anytrue([for allowed_value in field.parameter.allowedValues : jsonencode(field.parameter.defaultValue) == jsonencode(allowed_value)]),
          false
        ))
      )
    ]
  )

  initiative_parameter_mapping_records = flatten([
    for member_key, view in local.initiative_member_views : try([
      for parameter_name, mapping in view.supplied_parameter_values : {
        member_key             = member_key
        source_key             = view.source_key
        reference_id           = view.reference_id
        parameter_name         = parameter_name
        mapping                = mapping
        value                  = try(mapping.value, null)
        mapping_shape_valid    = try(can(keys(mapping)) && contains(keys(mapping), "value") && length(setsubtract(toset(keys(mapping)), toset(["value"]))) == 0, false)
        target_schema_known    = view.is_keyed && view.definition != null && view.definition.parameters != null && can(keys(view.definition.parameters))
        target_parameter       = try(view.definition.parameters[parameter_name], null)
        target_parameter_type  = try(lower(view.definition.parameters[parameter_name].type), "")
        binding_candidate      = try(can(regex("^\\\".*\\\"$", jsonencode(mapping.value))) && startswith(mapping.value, "["), false)
        binding_parameter_name = try(regexall("^\\[parameters\\('([^']+)'\\)\\]$", mapping.value)[0][0], null)
      }
    ], []) if view.supplied_parameter_values != null
  ])

  initiative_parameter_mapping_checks = [
    for index, record in local.initiative_parameter_mapping_records : {
      member_key = record.member_key
      value_valid = (
        !record.mapping_shape_valid ||
        !record.target_schema_known ||
        (record.binding_candidate ? record.binding_parameter_name != null : local.typed_value_valid["mapping/${index}"])
      )
      allowed_value_valid = !record.mapping_shape_valid || !record.target_schema_known || record.binding_candidate ? true : try(
        !contains(keys(record.target_parameter), "allowedValues") || (
          record.target_parameter_type == "array" ?
          alltrue([for element in record.value : anytrue([for allowed_value in record.target_parameter.allowedValues : jsonencode(element) == jsonencode(allowed_value)])]) :
          anytrue([for allowed_value in record.target_parameter.allowedValues : jsonencode(record.value) == jsonencode(allowed_value)])
        ),
        false
      )
      binding_valid = !record.binding_candidate || try(
        record.binding_parameter_name != null &&
        can(keys(local.initiative_entries[record.source_key].parameters)) &&
        contains(keys(local.initiative_entries[record.source_key].parameters), record.binding_parameter_name) &&
        (
          !record.target_schema_known ||
          (
            contains(local.azure_policy_parameter_types, record.target_parameter_type) &&
            contains(local.azure_policy_parameter_types, lower(local.initiative_entries[record.source_key].parameters[record.binding_parameter_name].type)) &&
            (
              lower(local.initiative_entries[record.source_key].parameters[record.binding_parameter_name].type) == record.target_parameter_type ||
              (lower(local.initiative_entries[record.source_key].parameters[record.binding_parameter_name].type) == "integer" && record.target_parameter_type == "float")
            ) &&
            (
              !contains(keys(record.target_parameter), "allowedValues") ||
              (
                contains(keys(local.initiative_entries[record.source_key].parameters[record.binding_parameter_name]), "allowedValues") &&
                (
                  record.target_parameter_type == "array" ?
                  alltrue([for source_allowed in local.initiative_entries[record.source_key].parameters[record.binding_parameter_name].allowedValues : anytrue([for target_allowed in record.target_parameter.allowedValues : jsonencode(source_allowed) == jsonencode(target_allowed)])]) :
                  alltrue([for source_allowed in local.initiative_entries[record.source_key].parameters[record.binding_parameter_name].allowedValues : anytrue([for target_allowed in record.target_parameter.allowedValues : jsonencode(source_allowed) == jsonencode(target_allowed)])])
                )
              )
            )
          )
        ),
        false
      )
    }
  ]

  initiative_parameter_mapping_checks_by_member = {
    for check in local.initiative_parameter_mapping_checks : check.member_key => check...
  }

  initiative_name_groups = {
    for key, initiative in local.initiative_entries :
    lower("${coalesce(initiative.management_group_id, "subscription")}|${coalesce(initiative.name, key)}") => key...
  }

  duplicate_initiative_names = sort([
    for normalized_name, keys in local.initiative_name_groups : normalized_name
    if length(keys) > 1
  ])

  initiative_entry_validation_records = {
    for key, initiative in local.initiative_entries : key => {
      source_id = key
      document  = initiative
      rules = {
        field_allowlist_valid = try(length(setsubtract(toset(keys(var.initiatives[key])), local.initiative_envelope_fields)) == 0, false)
        key_valid             = try(trimspace(key) == key && trimspace(key) != "", false)
        required_fields_valid = try(can(regex("^\\\".*\\\"$", jsonencode(initiative.display_name))) && trimspace(initiative.display_name) != "" && length(initiative.policy_definition_references) > 0, false)
        scalar_types_valid = try(alltrue([
          for field in ["name", "display_name", "description", "version", "management_group_id"] :
          try(initiative[field], null) == null || can(regex("^\\\".*\\\"$", jsonencode(initiative[field])))
        ]), false)
        metadata_valid             = initiative.metadata == null || can(keys(initiative.metadata))
        parameters_valid           = initiative.parameters == null || can(keys(initiative.parameters))
        governance_valid           = initiative.governance == null || can(keys(initiative.governance))
        version_valid              = initiative.version == null || can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", initiative.version))
        management_group_id_valid  = initiative.management_group_id == null || can(regex(local.management_group_id_pattern, initiative.management_group_id))
        group_container_valid      = initiative.policy_definition_groups == null || try(!can(keys(initiative.policy_definition_groups)) && alltrue([for group in initiative.policy_definition_groups : can(keys(group))]), false)
        group_names_unique_valid   = initiative.policy_definition_groups == null || try(length(distinct([for group in initiative.policy_definition_groups : lower(trimspace(group.name))])) == length(initiative.policy_definition_groups), false)
        reference_ids_unique_valid = try(length(distinct([for reference in initiative.policy_definition_references : lower(trimspace(reference.reference_id))])) == length(initiative.policy_definition_references), false)
      }
    }
  }

  initiative_reference_validation_records = [
    for member_key, view in local.initiative_member_views : {
      source_id    = view.source_key
      reference_id = view.reference_id
      rules = {
        container_valid       = try(!can(keys(view.initiative.policy_definition_references)) && can([for reference in view.initiative.policy_definition_references : reference]), false)
        field_allowlist_valid = try(length(setsubtract(toset(keys(view.reference)), local.initiative_reference_fields)) == 0, false)
        required_fields_valid = try(can(regex("^\\\".*\\\"$", jsonencode(view.reference.reference_id))) && view.reference_id != "", false)
        scalar_types_valid = try(alltrue([
          for field in ["reference_id", "definition_key", "policy_definition_id", "version_constraint", "pinned_version", "effect"] :
          try(view.reference[field], null) == null || can(regex("^\\\".*\\\"$", jsonencode(view.reference[field])))
        ]) && (try(view.reference.required, null) == null || can(regex("^(true|false)$", jsonencode(view.reference.required)))), false)
        source_valid               = try(length([for supplied in [view.definition_key, view.supplied_policy_definition_id] : supplied if supplied != null]) == 1, false)
        definition_exists_valid    = !view.is_keyed || contains(keys(local.definitions), view.definition_key)
        policy_definition_id_valid = try(view.is_keyed || anytrue([for pattern in local.policy_definition_id_patterns : can(regex(pattern, view.supplied_policy_definition_id))]), false)
        scope_valid = (view.is_keyed ?
          (view.definition != null && (view.definition.management_group_id == null || view.definition.management_group_id == view.initiative.management_group_id)) :
          (
            (view.supplied_policy_definition_id == null || !can(regex("^/subscriptions/", view.supplied_policy_definition_id)) || view.initiative.management_group_id == null) &&
            (view.supplied_policy_definition_id == null || !can(regex("^/providers/Microsoft\\.Management/managementGroups/", view.supplied_policy_definition_id)) || view.initiative.management_group_id != null)
          )
        )
        parameters_valid = try(view.supplied_parameter_values == null || can(keys(view.supplied_parameter_values)), false)
        parameter_schema_valid = try(
          view.supplied_parameter_values == null || !view.is_keyed ||
          (view.definition != null && (view.definition.parameters == null || alltrue([
            for parameter_name, _ in view.supplied_parameter_values :
            contains(keys(view.definition.parameters), parameter_name)
          ]))),
        false)
        parameter_required_mappings_valid = try(
          !view.is_keyed || view.definition == null || view.definition.parameters == null || alltrue([
            for parameter_name, parameter in view.definition.parameters :
            try(contains(keys(parameter), "defaultValue"), false) || (
              view.supplied_parameter_values != null &&
              can(keys(view.supplied_parameter_values)) &&
              contains(keys(view.supplied_parameter_values), parameter_name)
            )
          ]),
        false)
        parameter_mapping_valid = try(
          view.supplied_parameter_values == null || alltrue([
            for _, mapping in view.supplied_parameter_values :
            can(keys(mapping)) && contains(keys(mapping), "value") &&
            length(setsubtract(toset(keys(mapping)), toset(["value"]))) == 0
        ]), false)
        parameter_value_valid = alltrue([
          for check in lookup(local.initiative_parameter_mapping_checks_by_member, member_key, []) :
          check.value_valid && check.allowed_value_valid
        ])
        parameter_binding_valid = alltrue([
          for check in lookup(local.initiative_parameter_mapping_checks_by_member, member_key, []) :
          check.binding_valid
        ])
        parameter_collision_valid = try(
          view.initiative.parameters == null || view.supplied_parameter_values == null ||
          length(setintersection(toset(keys(view.initiative.parameters)), toset(keys(view.supplied_parameter_values)))) == 0,
        false)
        group_names_container_valid = try(view.supplied_group_names == null || (!can(keys(view.supplied_group_names)) && can([for group_name in view.supplied_group_names : group_name])), false)
        group_names_valid           = try(view.supplied_group_names == null || length(distinct([for group_name in view.supplied_group_names : lower(trimspace(group_name))])) == length(view.supplied_group_names) && alltrue([for group_name in view.supplied_group_names : can(regex("^\\\".*\\\"$", jsonencode(group_name))) && trimspace(group_name) != "" && contains(local.initiative_group_names[view.source_key], lower(trimspace(group_name)))]), false)
        effect_valid                = try(try(view.reference.effect, null) == null || can(regex("^\\\".*\\\"$", jsonencode(view.reference.effect))) && trimspace(view.reference.effect) != "", false)
        required_valid              = try(try(view.reference.required, null) == null || can(regex("^(true|false)$", jsonencode(view.reference.required))), false)
        version_intent_valid        = view.is_keyed || ((view.supplied_version_constraint == null) != (view.supplied_pinned_version == null))
        version_format_valid = ((view.supplied_version_constraint == null || can(regex("^[0-9]+\\.([0-9]+|\\*)\\.\\*$", view.supplied_version_constraint))) &&
          (view.supplied_pinned_version == null || can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", view.supplied_pinned_version))) &&
        !(view.supplied_version_constraint != null && view.supplied_pinned_version != null))
        provider_version_valid = !local.initiative_member_version_intent[member_key] || local.initiative_member_provider_versions[member_key] != null
        # A member without selectors inherits regardless of definition
        # existence; a missing definition is caught by definition_exists_valid.
        version_inherited_valid = (!view.is_keyed ||
          (view.supplied_version_constraint == null && view.supplied_pinned_version == null) ||
          (view.definition != null && (
            (view.supplied_version_constraint != null && view.supplied_version_constraint == view.definition.version_constraint && view.supplied_pinned_version == null) ||
            (view.supplied_pinned_version != null && view.supplied_version_constraint == null && (view.supplied_pinned_version == view.definition.pinned_version || view.supplied_pinned_version == view.definition.version))
        )))
      }
    }
  ]

  initiative_group_validation_records = flatten([
    for entry in local.initiative_entry_validation_records : try([
      for group in entry.document.policy_definition_groups : {
        source_id  = entry.source_id
        group_name = try(trimspace(group.name), "")
        rules = {
          field_allowlist_valid = try(length(setsubtract(toset(keys(group)), local.initiative_group_fields)) == 0, false)
          required_fields_valid = try(trimspace(group.name) != "" && trimspace(group.display_name) != "", false)
          scalar_types_valid    = try(alltrue([for field in ["name", "display_name", "description"] : try(group[field], null) == null || can(regex("^\\\".*\\\"$", jsonencode(group[field])))]), false)
          metadata_valid        = try(group.metadata == null || can(keys(group.metadata)), false)
        }
      }
    ], [])
  ])

  # Failures per rule family, each naming the source key, the member or group
  # and the failed rule. The guard joins them with the rule explanations below.
  initiative_rule_failures = {
    entry = flatten([
      for source_id, record in local.initiative_entry_validation_records : [
        for rule, passed in record.rules : { rule = rule, text = "${source_id}: failed ${rule}" } if !passed
      ]
    ])
    reference = flatten([
      for record in local.initiative_reference_validation_records : [
        for rule, passed in record.rules : { rule = rule, text = "${record.source_id} member ${jsonencode(record.reference_id)}: failed ${rule}" } if !passed
      ]
    ])
    group = flatten([
      for record in local.initiative_group_validation_records : [
        for rule, passed in record.rules : { rule = rule, text = "${record.source_id} group ${jsonencode(record.group_name)}: failed ${rule}" } if !passed
      ]
    ])
  }

  initiative_rule_explanations = {
    entry = {
      field_allowlist_valid      = "envelopes may use only documented fields"
      key_valid                  = "catalogue keys must be non-blank strings with no surrounding whitespace"
      required_fields_valid      = "envelopes require a display name and at least one policy_definition_references member"
      scalar_types_valid         = "documented string fields must be strings when supplied"
      metadata_valid             = "metadata must be an object when supplied"
      parameters_valid           = "parameters must be an object when supplied"
      governance_valid           = "governance must be an object when supplied"
      version_valid              = "version must be an exact three-part version when supplied"
      management_group_id_valid  = "management_group_id must be null or a management-group resource ID"
      group_container_valid      = "policy_definition_groups must be a list of group objects when supplied"
      group_names_unique_valid   = "group names must be unique case-insensitively within each initiative"
      reference_ids_unique_valid = "member reference_id values must be unique case-insensitively within each initiative"
    }
    reference = {
      container_valid                   = "policy_definition_references must be a list of member objects"
      field_allowlist_valid             = "member references may use only documented fields"
      required_fields_valid             = "each member requires a non-blank reference_id"
      scalar_types_valid                = "member identity fields must be strings when supplied"
      source_valid                      = "each member must be either a keyed definition_key or a direct policy_definition_id, never both and never neither"
      definition_exists_valid           = "keyed members must reference an existing definition key"
      policy_definition_id_valid        = "direct member IDs must use a supported Azure Policy definition resource ID format"
      scope_valid                       = "member definition scope must match the initiative scope"
      parameters_valid                  = "member parameter_values must be an object when supplied"
      parameter_schema_valid            = "member parameter mappings may name only declared definition parameters"
      parameter_required_mappings_valid = "each required definition parameter without a default must have a member mapping"
      parameter_mapping_valid           = "member parameter mappings must be objects containing only value"
      parameter_value_valid             = "member parameter values must match the referenced definition schema, defaults and allowed values"
      parameter_binding_valid           = "member parameter expressions must be supported [parameters('name')] bindings to compatible declared initiative parameters"
      parameter_collision_valid         = "initiative parameters and member parameter mappings must not collide"
      group_names_container_valid       = "member group_names must be null or a list when supplied"
      group_names_valid                 = "member group_names must be unique non-blank names of groups declared on the same initiative"
      effect_valid                      = "member effect must be a non-blank string when supplied"
      required_valid                    = "member required must be a boolean when supplied"
      version_intent_valid              = "direct members require exactly one of version_constraint or pinned_version; keyed members may omit both"
      version_format_valid              = "member version_constraint must be major.*.* or major.minor.* and pinned_version must be an exact x.y.z"
      provider_version_valid            = "member version intent must be representable by AzureRM (major.minor or major.minor.*); exact pins are rejected rather than widened"
      version_inherited_valid           = "keyed member version intent must match the referenced definition intent"
    }
    group = {
      field_allowlist_valid = "group records may use only name, display_name, description and metadata"
      required_fields_valid = "group records require a non-blank name and display_name"
      scalar_types_valid    = "group name, display_name and description must be strings when supplied"
      metadata_valid        = "group metadata must be an object when supplied"
    }
  }

  initiative_rule_messages = {
    for family, failures in local.initiative_rule_failures : family => join(" | ", [
      for rule, texts in { for failure in failures : failure.rule => failure.text... } :
      "${local.initiative_rule_explanations[family][rule]}: ${join("; ", texts)}"
    ])
  }

  initiative_contract_valid = length(local.parameter_schema_failures) == 0 && alltrue([
    for failures in values(local.initiative_rule_failures) : length(failures) == 0
  ])

  # Output-contract projection per member view; every field is a copy from
  # the normalised view or one of the per-member decision maps above.
  initiative_member_projections = {
    for member_key, view in local.initiative_member_views : member_key => {
      reference_id         = view.reference_id
      definition_key       = view.definition_key
      source_type          = view.is_keyed && view.definition != null ? view.definition.source_type : null
      created_by_module    = view.is_keyed && view.definition != null ? view.definition.created_by_module : null
      initiative_key       = view.source_key
      policy_definition_id = local.initiative_member_definition_intent[member_key].policy_definition_id
      parameter_values     = view.supplied_parameter_values
      parameter_schema     = view.is_keyed && view.definition != null ? view.definition.parameters : null
      group_names          = view.supplied_group_names
      effect               = view.supplied_effect
      required             = view.supplied_required
      version_constraint   = view.supplied_version_constraint
      pinned_version       = view.supplied_pinned_version
      inherited_version    = local.initiative_member_definition_intent[member_key].inherited_version
      selected_version     = local.initiative_member_selected_versions[member_key]
      parameter_mappings   = view.supplied_parameter_values
      capabilities         = view.is_keyed && view.definition != null ? view.definition.capabilities : null
      role_definition_ids  = view.is_keyed && view.definition != null ? view.definition.role_definition_ids : null
      list_fields = {
        supported_effects       = view.is_keyed && view.definition != null ? view.definition.supported_effects : null
        supported_overrides     = view.is_keyed && view.definition != null ? view.definition.supported_overrides : null
        selectors               = view.is_keyed && view.definition != null ? view.definition.selectors : null
        non_compliance_messages = view.is_keyed && view.definition != null ? view.definition.non_compliance_messages : null
      }
      governance       = view.initiative.governance
      resource_version = local.initiative_member_selected_versions[member_key]
      provider_version = local.initiative_member_provider_versions[member_key]
      target = {
        reference_id         = view.reference_id
        definition_key       = view.definition_key
        initiative_key       = view.source_key
        policy_definition_id = local.initiative_member_definition_intent[member_key].policy_definition_id
      }
    }
  }

  # Regrouped per initiative in reference order; iterating the initiative's
  # own reference list preserves member order, which a map for-expression
  # would lexically sort by member key.
  initiative_member_resolution = {
    for key, initiative in local.initiative_entries : key => [
      for index, reference in try([for reference in initiative.policy_definition_references : reference], []) :
      local.initiative_member_projections["${key}/${index}"]
    ]
  }

  subscription_initiatives     = { for key, initiative in local.initiative_entries : key => initiative if initiative.management_group_id == null }
  management_group_initiatives = { for key, initiative in local.initiative_entries : key => initiative if initiative.management_group_id != null }
}
