locals {
  supported_parameter_types = toset(["string", "array", "object", "boolean", "integer", "float", "datetime"])
  json_number_pattern       = "^-?(0|[1-9][0-9]*)(\\.[0-9]+)?([eE][+-]?[0-9]+)?$"
  json_integer_pattern      = "^-?(0|[1-9][0-9]*)$"
  rfc3339_pattern           = "^[0-9]{4}-[0-9]{2}-[0-9]{2}T([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9](\\.[0-9]+)?(Z|[+-]([01][0-9]|2[0-3]):[0-5][0-9])$"

  # Scope grammar, written once for this module. Variable validations read
  # these constants, so they must stay independent of every variable.
  # Subscription IDs are GUIDs, as Azure issues them, and a resource scope names
  # a provider, a type and a resource. behaviour-resolution and identity-rbac
  # write the same grammar, so an ID is accepted or rejected alike at each
  # hand-off.
  scope_types = ["management_group", "subscription", "resource_group", "resource"]

  scope_patterns = {
    management_group = "^/providers/Microsoft\\.Management/managementGroups/[^/]+$"
    subscription     = "^/subscriptions/[0-9a-fA-F-]{36}$"
    resource_group   = "^/subscriptions/[0-9a-fA-F-]{36}/resourceGroups/[^/]+$"
    resource         = "^/subscriptions/[0-9a-fA-F-]{36}/resourceGroups/[^/]+/providers/[^/]+/[^/]+/[^/]+(/[^/]+)*$"
  }

  assignment_entries = {
    for key, record in var.assignments :
    key => {
      assignment_key = key
      intent         = record.intent
      resolved       = record.resolved
      target = {
        reference_id         = trimspace(record.intent.target.reference_id)
        definition_key       = try(trimspace(record.intent.target.definition_key), "") != "" ? trimspace(record.intent.target.definition_key) : null
        initiative_key       = try(trimspace(record.intent.target.initiative_key), "") != "" ? trimspace(record.intent.target.initiative_key) : null
        policy_definition_id = trimspace(record.resolved.policy_definition_id)
      }
      # Only the intent carries the direct-target marker; target.policy_definition_id above is the resolved Azure target.
      target_direct_definition_id = try(trimspace(record.intent.target.policy_definition_id), "") != "" ? trimspace(record.intent.target.policy_definition_id) : null
      scope = {
        type = record.intent.scope.type
        id   = trimspace(record.intent.scope.id)
      }
      # The assignment payload carries the caller's assignment-time parameters
      # only. resolved.parameter_values merges the member's template-expression
      # mapping for member targets, and those keys are set-definition wiring:
      # Azure rejects them as UndefinedPolicyParameter on the assignment.
      parameters                 = try(record.intent.parameters, null)
      selectors                  = try(record.intent.selectors, null)
      overrides                  = try(record.resolved.overrides, try(record.intent.overrides, null))
      exclusions                 = try(record.intent.exclusions, null)
      enforcement_mode           = try(trimspace(record.intent.enforcement_mode), "") != "" ? trimspace(record.intent.enforcement_mode) : null
      non_compliance_messages    = try(record.intent.non_compliance_messages, null)
      rollout                    = try(record.intent.rollout, null)
      governance                 = try(record.resolved.governance, null) == null ? try(record.intent.governance, null) : record.resolved.governance
      version_binding            = try(record.intent.version_binding, null)
      resolved_effect            = try(record.resolved.effective_effect, null)
      definition_default_effect  = try(record.resolved.definition_default_effect, null)
      resolved_version           = try(record.resolved.selected_version, null)
      source_version             = try(record.resolved.source_version, null)
      identity                   = try(record.resolved.identity, null)
      parameter_schema           = try(record.resolved.parameter_schema, null)
      initiative_content_version = try(record.resolved.initiative_content_version, null)
      members                    = try(record.resolved.members, null)
      parameter_mappings         = try(record.resolved.parameter_mappings, null)
      identity_binding           = try(var.identity_bindings[key], null)
      identity_id                = try(var.identity_bindings[key].id, try(var.identity_bindings[key].identity_id, null))
    }
  }

  normalised_name_parts = {
    for key, assignment in local.assignment_entries :
    key => join("", [
      for character in split("", lower(join("-", [key, assignment.scope.type, assignment.target.reference_id]))) :
      contains(split("", "abcdefghijklmnopqrstuvwxyz0123456789-"), character) ? character : "-"
    ])
  }

  name_bases = {
    for key, value in local.normalised_name_parts :
    key => trim(value, "-") == "" ? "assignment" : trim(value, "-")
  }

  # One grouping pass over the name bases; duplicate detection is then a direct
  # length lookup instead of rescanning the collection per base.
  name_base_groups = {
    for key, base in local.name_bases : base => key...
  }

  duplicate_name_bases = toset([
    for base, keys in local.name_base_groups : base
    if length(keys) > 1
  ])

  # Provider arguments identical across the four scope resources are projected
  # once; the resource blocks stay explicit because their scope arguments differ.
  provider_arguments = {
    for key, assignment in local.assignment_entries :
    key => {
      description = try(assignment.governance.description, null)
      metadata    = assignment.governance == null ? null : jsonencode(assignment.governance)
      enforce     = assignment.enforcement_mode == null ? true : assignment.enforcement_mode != "DoNotEnforce"
      location    = try(assignment.identity.location, null)
    }
  }

  assignment_names = {
    for key, assignment in local.assignment_entries :
    key => (
      contains(local.duplicate_name_bases, local.name_bases[key]) || length(local.name_bases[key]) > (assignment.scope.type == "management_group" ? 24 : 64)
      ? "${substr(local.name_bases[key], 0, assignment.scope.type == "management_group" ? 15 : 55)}-${substr(sha1(key), 0, 8)}"
      : local.name_bases[key]
    )
  }

  # One normalised parameter review per assignment. A null schema is unknown,
  # an explicit empty schema is verified absence, and values overlay schema
  # defaults with supplied values after unwrapping { value = ... } wrappers.
  # Initiative targets use the policy set's own schema; member defaults remain
  # inside the initiative and are never injected into set assignment values.
  parameter_reviews = {
    for key, assignment in local.assignment_entries :
    key => {
      initiative_target = assignment.target.initiative_key != null
      schema            = assignment.parameter_schema
      schema_keys       = assignment.parameter_schema == null ? null : toset(keys(assignment.parameter_schema))
      supplied          = assignment.parameters
      values = assignment.target.initiative_key != null ? try({
        for parameter_key, parameter_value in assignment.parameters : parameter_key => try(parameter_value.value, parameter_value)
        }, null) : (
        assignment.parameters == null && assignment.parameter_schema == null ? null : merge(
          try({
            for parameter_key, schema in assignment.parameter_schema : parameter_key => schema.defaultValue
            if try(schema.defaultValue, null) != null
          }, {}),
          try({
            for parameter_key, parameter_value in assignment.parameters : parameter_key => try(parameter_value.value, parameter_value)
          }, {})
        )
      )
    }
  }

  parameter_payloads = {
    for key, review in local.parameter_reviews :
    key => review.values == null ? null : jsonencode({
      for parameter_key, parameter_value in review.values : parameter_key => { value = parameter_value }
    })
  }

  # Assignments partitioned by scope type once; each scope resource iterates
  # its own partition. Keys are the stable assignment keys.
  by_scope = {
    for scope_type in local.scope_types : scope_type => {
      for key, assignment in local.assignment_entries : key => assignment if assignment.scope.type == scope_type
    }
  }

  # Dynamic-block inputs normalised once per assignment so the scope resources
  # carry no guarded raw-field reads. A single selector object is accepted in
  # place of a selector list. Null in/not_in stay null for the provider.
  dynamic_payloads = {
    for key, assignment in local.assignment_entries : key => {
      non_compliance_messages = assignment.non_compliance_messages == null ? [] : [
        for message in assignment.non_compliance_messages : {
          content                        = message.content
          policy_definition_reference_id = try(message.policy_definition_reference_id, null)
        }
      ]
      overrides = assignment.overrides == null ? [] : [
        for override in assignment.overrides : {
          value = override.value
          selectors = try(override.selectors, null) == null ? [] : [
            for selector in try(tolist(override.selectors), [override.selectors]) : {
              kind   = try(selector.kind, null)
              in     = try(selector.in, null)
              not_in = try(selector.not_in, null)
            }
          ]
        }
      ]
      resource_selectors = assignment.selectors == null ? [] : [
        for selector in assignment.selectors : {
          name = try(selector.name, null)
          selectors = [
            for nested in try(selector.selectors, [selector]) : {
              kind   = nested.kind
              in     = try(nested.in, null)
              not_in = try(nested.not_in, null)
            }
          ]
        }
      ]
    }
  }

  # Lower-cased schema type per parameter, read by every type and allowed-value
  # check below instead of re-deriving it per rule.
  parameter_schema_types = {
    for key, review in local.parameter_reviews : key => review.schema == null ? {} : {
      for parameter_key, schema in review.schema : parameter_key => try(lower(schema.type), "")
    }
  }

  parameter_unknown_keys = {
    for key, review in local.parameter_reviews :
    # A null values view carries no supplied keys; member defaults are never
    # injected into initiative assignment payloads.
    key => review.schema_keys == null || review.values == null ? [] : setsubtract(toset(keys(review.values)), review.schema_keys)
  }

  parameter_missing_required = {
    for key, review in local.parameter_reviews :
    key => review.schema == null ? [] : [
      for parameter_key, schema in review.schema : parameter_key
      if try(schema.defaultValue, null) == null && !contains(try(keys(review.values), []), parameter_key)
    ]
  }

  # Validate defaults as well as supplied values without adding initiative
  # defaults to the assignment payload. The payload remains intent-only for sets.
  parameter_type_validation_values = {
    for key, review in local.parameter_reviews : key => review.schema == null ? null : try(merge(
      {
        for parameter_key, schema in review.schema : parameter_key => schema.defaultValue
        if try(schema.defaultValue, null) != null
      },
      review.values
      ), {
      for parameter_key, schema in review.schema : parameter_key => schema.defaultValue
      if try(schema.defaultValue, null) != null
    })
  }

  parameter_schema_type_valid_by_parameter = {
    for key, review in local.parameter_reviews : key => review.schema == null ? {} : {
      for parameter_key, schema in review.schema : parameter_key => can(keys(schema)) && contains(local.supported_parameter_types, local.parameter_schema_types[key][parameter_key]) && (
        try(schema.allowedValues, null) == null || can(regex("^\\[", jsonencode(schema.allowedValues)))
      )
    }
  }

  parameter_schema_type_offenders = {
    for key, valid in local.parameter_schema_type_valid_by_parameter : key => [
      for parameter_key, is_valid in valid : parameter_key if !is_valid
    ]
  }

  parameter_type_valid_by_parameter = {
    for key, review in local.parameter_reviews :
    key => review.schema == null || local.parameter_type_validation_values[key] == null ? {} : {
      for parameter_key, value in local.parameter_type_validation_values[key] : parameter_key => (
        !contains(keys(review.schema), parameter_key) ? false :
        local.parameter_schema_types[key][parameter_key] == "string" ? can(regex("^\\\".*\\\"$", jsonencode(value))) :
        local.parameter_schema_types[key][parameter_key] == "boolean" ? can(regex("^(true|false)$", jsonencode(value))) :
        local.parameter_schema_types[key][parameter_key] == "integer" ? can(regex(local.json_integer_pattern, jsonencode(value))) :
        local.parameter_schema_types[key][parameter_key] == "float" ? can(regex(local.json_number_pattern, jsonencode(value))) :
        local.parameter_schema_types[key][parameter_key] == "datetime" ? (
          can(regex("^\\\".*\\\"$", jsonencode(value))) ? can(regex(local.rfc3339_pattern, value)) && can(formatdate("YYYY", value)) : false
        ) :
        local.parameter_schema_types[key][parameter_key] == "array" ? can(regex("^\\[", jsonencode(value))) :
        local.parameter_schema_types[key][parameter_key] == "object" ? can(keys(value)) && can(regex("^\\{", jsonencode(value))) : false
      )
    }
  }

  parameter_type_valid = {
    for key, valid in local.parameter_type_valid_by_parameter :
    key => alltrue(values(valid))
  }

  parameter_type_offenders = {
    for key, valid in local.parameter_type_valid_by_parameter :
    key => [for parameter_key, is_valid in valid : parameter_key if !is_valid]
  }

  parameter_allowed_values_valid = {
    for key, review in local.parameter_reviews :
    key => review.schema == null || local.parameter_type_validation_values[key] == null ? true : alltrue([
      for parameter_key, value in local.parameter_type_validation_values[key] :
      !contains(keys(review.schema), parameter_key) || try(review.schema[parameter_key].allowedValues, null) == null ? true :
      can(regex("^\\[", jsonencode(review.schema[parameter_key].allowedValues))) && (
        local.parameter_schema_types[key][parameter_key] == "array" ? (
          can(regex("^\\[", jsonencode(value))) && alltrue([
            for item in value : anytrue([
              for allowed_value in review.schema[parameter_key].allowedValues : jsonencode(allowed_value) == jsonencode(item)
            ])
          ])
          ) : anytrue([
            for allowed_value in review.schema[parameter_key].allowedValues : jsonencode(allowed_value) == jsonencode(value)
        ])
      )
    ])
  }

  parameters_valid = {
    for key, review in local.parameter_reviews :
    # Unknown schemas accept only absent or explicit-empty intent. Known set
    # schemas are validated with the same required/type/value rules as direct
    # definition schemas.
    key => review.schema == null ? (review.supplied == null || length(keys(review.supplied)) == 0) : length(local.parameter_unknown_keys[key]) == 0 && length(local.parameter_missing_required[key]) == 0 && alltrue(values(local.parameter_schema_type_valid_by_parameter[key])) && local.parameter_type_valid[key] && local.parameter_allowed_values_valid[key]
  }

  # An effect override addresses the definition unless a policyDefinitionReferenceId
  # selector re-points it at other set members; a direct target has no member
  # references, so that selector form can never address its single definition.
  effect_override_projection_valid = {
    for key, assignment in local.assignment_entries :
    key => assignment.resolved_effect == null || anytrue([
      for override in(assignment.overrides == null ? [] : assignment.overrides) :
      jsonencode(try(override.value, null)) == jsonencode(assignment.resolved_effect) && alltrue([
        for selector in(try(override.selectors, null) == null ? [] : override.selectors) :
        lower(try(selector.kind, "")) != "policydefinitionreferenceid" || (
          assignment.target.initiative_key != null && try(contains(selector.in, assignment.target.reference_id), false)
        )
      ])
    ])
  }

  # The deployed parameter payload is authoritative: an effect parameter carrying
  # the effective effect enforces it without an override.
  effect_parameter_projection_valid = {
    for key, assignment in local.assignment_entries :
    key => assignment.resolved_effect != null && try(jsonencode(local.parameter_reviews[key].values["effect"]) == jsonencode(assignment.resolved_effect), false)
  }

  # Quoted-JSON string comparison keeps null (unknown) distinct from an absent default.
  effect_enforceability_valid = {
    for key, assignment in local.assignment_entries :
    key => assignment.resolved_effect == null ? true : (
      jsonencode(assignment.resolved_effect) == jsonencode(assignment.definition_default_effect)
      || local.effect_override_projection_valid[key]
      || local.effect_parameter_projection_valid[key]
    )
  }

  requested_selector_kinds = {
    for key, assignment in local.assignment_entries : key => concat(
      flatten([
        for selector in(assignment.selectors == null ? [] : assignment.selectors) :
        try(selector.selectors, null) == null ? [lower(try(selector.kind, ""))] : [for nested in(try(selector.selectors, null) == null ? [] : selector.selectors) : lower(try(nested.kind, ""))]
      ]),
      flatten([
        for override in(assignment.overrides == null ? [] : assignment.overrides) : try(override.selectors, null) == null ? [] : [
          for selector in override.selectors : lower(try(selector.kind, ""))
        ]
      ])
    )
  }

  declared_selector_kinds = {
    for key, assignment in local.assignment_entries : key => flatten([
      for selector in(try(assignment.resolved.list_fields.selectors, null) == null ? [] : assignment.resolved.list_fields.selectors) :
      try(selector.selectors, null) == null ? [lower(try(selector.kind, ""))] : [for nested in(try(selector.selectors, null) == null ? [] : selector.selectors) : lower(try(nested.kind, ""))]
    ])
  }

  # AzureRM policy assignment resources expose no definitionVersion argument.
  # Any selected direct-target version is therefore unrepresentable, including
  # an exact pin that is not encoded into the stable policy definition ID.
  direct_version_unenforceable = {
    for key, assignment in local.assignment_entries :
    key => assignment.target.initiative_key == null && assignment.resolved_version != null
  }

  resolved_control_support_valid = {
    for key, assignment in local.assignment_entries :
    key => alltrue([
      for kind in local.requested_selector_kinds[key] :
      kind == "policydefinitionreferenceid" ? assignment.target.initiative_key != null : contains(local.declared_selector_kinds[key], kind)
      ]) && alltrue([
      for override in(assignment.overrides == null ? [] : assignment.overrides) : anytrue([
        for declaration in(try(assignment.resolved.list_fields.supported_overrides, null) == null ? [] : assignment.resolved.list_fields.supported_overrides) :
        lower(try(declaration.kind, "policyeffect")) == "policyeffect" &&
        lower(try(declaration.value, "")) == lower(try(override.value, ""))
      ])
      ]) && alltrue([
      for message in(assignment.non_compliance_messages == null ? [] : assignment.non_compliance_messages) :
      try(assignment.resolved.list_fields.non_compliance_messages, null) != null && (
        try(message.policy_definition_reference_id, null) == null ? length(keys(assignment.resolved.list_fields.non_compliance_messages)) > 0 :
        contains(keys(assignment.resolved.list_fields.non_compliance_messages), message.policy_definition_reference_id)
      )
    ])
  }

  effect_values_supported = {
    for key, assignment in local.assignment_entries : key => alltrue(concat(
      [
        assignment.resolved_effect == null || try(assignment.resolved.list_fields.supported_effects, null) == null ? true : contains(assignment.resolved.list_fields.supported_effects, assignment.resolved_effect)
      ],
      assignment.members == null ? [] : flatten([
        for member in assignment.members : [
          for effect in(try(member.possible_effects, null) == null ? [] : member.possible_effects) :
          try(member.list_fields.supported_effects, null) == null ? true : contains(member.list_fields.supported_effects, effect)
        ]
      ])
    ))
  }

  provider_limits_valid = {
    for key, assignment in local.assignment_entries :
    key => try(length(assignment.exclusions) <= 400, true) &&
    try(length(assignment.overrides) <= 10, true) &&
    try(alltrue([
      for override in(assignment.overrides == null ? [] : assignment.overrides) : alltrue([
        for selector in(try(override.selectors, null) == null ? [] : override.selectors) :
        try(length(selector.in) <= 50, true) && try(length(selector.not_in) <= 50, true)
      ])
    ]), true) &&
    try(alltrue([
      for group in(assignment.selectors == null ? [] : assignment.selectors) : (
        try(group.selectors, null) == null ?
        try(length(group.in) <= 50, true) && try(length(group.not_in) <= 50, true) :
        alltrue([for selector in group.selectors : try(length(selector.in) <= 50, true) && try(length(selector.not_in) <= 50, true)])
      )
    ]), true)
  }

  control_declarations_valid = {
    for key, assignment in local.assignment_entries :
    key => alltrue(concat(
      assignment.selectors == null ? [] : [for selector in assignment.selectors : can(keys(selector)) && (
        contains(["resourceLocation", "resourceType", "resourceWithoutLocation"], try(selector.kind, "")) || (
          can(regex("^\\[", jsonencode(selector.selectors))) && alltrue([
            for nested in selector.selectors : can(keys(nested)) && contains(["resourceLocation", "resourceType", "resourceWithoutLocation"], try(nested.kind, "")) && !(try(nested.in, null) != null && try(nested.not_in, null) != null)
          ])
        )
      ) && !(try(selector.in, null) != null && try(selector.not_in, null) != null)],
      assignment.overrides == null ? [] : [for override in assignment.overrides : can(keys(override)) && contains(["Audit", "Deny", "Disabled", "Modify", "DeployIfNotExists", "Append"], try(override.value, "")) && (try(override.selectors, null) == null || alltrue([
        for selector in override.selectors : can(keys(selector)) && contains(["resourceLocation", "policyDefinitionReferenceId"], try(selector.kind, "")) && !(try(selector.in, null) != null && try(selector.not_in, null) != null)
      ]))],
      assignment.non_compliance_messages == null ? [] : [for message in assignment.non_compliance_messages : can(keys(message)) && trimspace(try(message.content, "")) != ""]
    ))
  }

  assignment_outputs = {
    for key, assignment in local.assignment_entries :
    key => {
      assignment_key              = key
      id                          = try(local.assignment_resource_ids[key], null)
      name                        = local.assignment_names[key]
      target_reference_id         = assignment.target.reference_id
      target_definition_key       = assignment.target.definition_key
      target_initiative_key       = assignment.target.initiative_key
      target_policy_definition_id = assignment.target.policy_definition_id
      scope                       = assignment.scope
      parameters = try({
        for parameter_key, parameter_value in assignment.parameters : parameter_key => parameter_value
        },
        assignment.parameters == null && assignment.target.initiative_key == null && assignment.parameter_schema != null ? {} : null
      )
      selectors               = assignment.selectors
      overrides               = assignment.overrides
      exclusions              = assignment.exclusions
      enforcement_mode        = assignment.enforcement_mode
      non_compliance_messages = assignment.non_compliance_messages
      rollout                 = assignment.rollout
      resolved                = assignment.resolved
      assignment              = { id = try(local.assignment_resource_ids[key], null), name = local.assignment_names[key] }
      identity                = assignment.identity

      identity_binding   = assignment.identity_binding
      effective_effect   = assignment.resolved_effect
      selected_version   = assignment.resolved_version
      source_version     = assignment.source_version
      version_binding    = assignment.version_binding
      governance         = assignment.governance
      replacement_review = local.replacement_review[key]
      created_by_module  = true
    }
  }

  # The records this module received, handed back with the lifecycle binding of
  # the assignment it owns. Records are otherwise unchanged. The binding ID is
  # null when no assignment resource exists for the record and unknown while one
  # is planned, and a consumer must not read either as a match. Downstream
  # modules read this instead of rebuilding it.
  resolved_assignments = {
    for key, record in var.assignments : key => merge(record, {
      assignment = merge(try(record.assignment, {}), local.assignment_outputs[key].assignment)
    })
  }

  assignment_resource_ids = merge([
    for resources in [
      azurerm_management_group_policy_assignment.this,
      azurerm_subscription_policy_assignment.this,
      azurerm_resource_group_policy_assignment.this,
      azurerm_resource_policy_assignment.this,
    ] : { for key, assignment in resources : key => assignment.id }
  ]...)

  replacement_review = {
    for key, assignment in local.assignment_entries :
    key => {
      name_changes_force_replacement              = true
      scope_changes_force_replacement             = true
      target_changes_force_replacement            = true
      identity_location_changes_force_replacement = true
      name_basis                                  = local.assignment_names[key]
      review_required_for                         = ["name", "scope", "target.policy_definition_id", "identity.location", "identity.resource_group_name"]
    }
  }
}
