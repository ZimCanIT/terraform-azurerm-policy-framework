locals {
  # Shared scope grammar: subscription IDs are GUIDs, as Azure issues them, so
  # the resolver, identity-rbac, remediations and exemptions agree on one form.
  scope_patterns = {
    management_group = "^/providers/Microsoft\\.Management/managementGroups/[^/]+$"
    subscription     = "^/subscriptions/[0-9a-fA-F-]{36}$"
    resource_group   = "^/subscriptions/[0-9a-fA-F-]{36}/resourceGroups/[^/]+$"
    resource         = "^/subscriptions/[0-9a-fA-F-]{36}/resourceGroups/[^/]+/providers/[^/]+/[^/]+/[^/]+(/[^/]+)*$"
  }

  normalised_effects = {
    audit             = "Audit"
    deny              = "Deny"
    disabled          = "Disabled"
    deployifnotexists = "DeployIfNotExists"
    modify            = "Modify"
    append            = "Append"
    auditifnotexists  = "AuditIfNotExists"
  }

  identity_effects = ["Modify", "DeployIfNotExists"]

  definition_entries = {
    for key, definition in var.definitions : key => {
      catalogue_key           = key
      id                      = try(definition.id, null)
      source_type             = try(definition.source_type, null)
      parameters              = try(definition.parameters, null)
      supported_effects       = try(definition.supported_effects, null)
      supported_overrides     = try(definition.supported_overrides, null)
      selectors               = try(definition.selectors, null)
      non_compliance_messages = try(definition.non_compliance_messages, null)
      capabilities            = try(definition.capabilities, null)
      governance              = try(definition.governance, null)
      role_definition_ids     = try(definition.role_definition_ids, null)
      version                 = try(definition.version, null)
      version_constraint      = try(definition.version_constraint, null)
      pinned_version          = try(definition.pinned_version, null)
      mode                    = try(definition.mode, null)
      policy_rule             = try(definition.policy_rule, null)
      # The definition's own default effect: capability default first, then
      # the policy rule's then.effect, normalised once here.
      default_effect = try(definition.capabilities.default_effect, null) != null ? try(local.normalised_effects[lower(trimspace(definition.capabilities.default_effect))], trimspace(definition.capabilities.default_effect)) : (
        try(definition.policy_rule.then.effect, null) == null ? null : try(local.normalised_effects[lower(trimspace(definition.policy_rule.then.effect))], trimspace(definition.policy_rule.then.effect))
      )
      normalised_supported_effects = try(definition.supported_effects, null) == null ? null : [
        for effect in tolist(definition.supported_effects) : try(local.normalised_effects[lower(trimspace(effect))], trimspace(effect))
      ]
    }
  }

  initiative_entries = {
    for key, initiative in var.initiatives : key => {
      catalogue_key                = key
      id                           = try(initiative.id, null)
      name                         = try(initiative.name, null)
      display_name                 = try(initiative.display_name, null)
      description                  = try(initiative.description, null)
      management_group_id          = try(initiative.management_group_id, null)
      metadata                     = try(initiative.metadata, null)
      created_by_module            = try(initiative.created_by_module, null)
      parameters                   = try(initiative.parameters, null)
      parameter_schema             = try(initiative.parameter_schema, try(initiative.parameters, null))
      policy_definition_references = contains(keys(initiative), "policy_definition_references") ? initiative.policy_definition_references : null
      governance                   = try(initiative.governance, null)
      version                      = try(initiative.version, null)
    }
  }

  assignment_entries = {
    for key, assignment in var.assignments : key => {
      assignment_key = key
      target = {
        reference_id         = try(assignment.target.reference_id, null) == null ? null : trimspace(assignment.target.reference_id)
        definition_key       = try(assignment.target.definition_key, null) == null ? null : trimspace(assignment.target.definition_key) == "" ? null : trimspace(assignment.target.definition_key)
        initiative_key       = try(assignment.target.initiative_key, null) == null ? null : trimspace(assignment.target.initiative_key) == "" ? null : trimspace(assignment.target.initiative_key)
        policy_definition_id = try(assignment.target.policy_definition_id, null) == null ? null : trimspace(assignment.target.policy_definition_id) == "" ? null : trimspace(assignment.target.policy_definition_id)
      }
      scope = {
        type = try(assignment.scope.type, null)
        id   = try(trimspace(assignment.scope.id), "")
      }
      parameters              = try(assignment.parameters, null)
      selectors               = try(assignment.selectors, null)
      overrides               = try(assignment.overrides, null)
      exclusions              = try(assignment.exclusions, null)
      enforcement_mode        = try(assignment.enforcement_mode, null)
      non_compliance_messages = try(assignment.non_compliance_messages, null)
      rollout                 = try(assignment.rollout, null)
      governance              = try(assignment.governance, null)
      requested_effect        = try(assignment.effect, null) == null ? null : try(local.normalised_effects[lower(trimspace(assignment.effect))], trimspace(assignment.effect))
      requested_constraint    = try(assignment.version_constraint, null)
      requested_pin           = try(assignment.pinned_version, null)
      version_binding         = try(assignment.version_binding, null)
      identity_intent         = try(assignment.identity, null)
      # Per-role grant-scope overrides keyed by the exact role definition ID; null falls back to assignment scope.
      role_grant_scopes = try(assignment.role_grant_scopes, null)
    }
  }

  target_entries = {
    for key, assignment in local.assignment_entries : key => merge(assignment, {
      definition = assignment.target.definition_key == null ? null : contains(keys(local.definition_entries), assignment.target.definition_key) ? local.definition_entries[assignment.target.definition_key] : null
      initiative = assignment.target.initiative_key == null ? null : contains(keys(local.initiative_entries), assignment.target.initiative_key) ? local.initiative_entries[assignment.target.initiative_key] : null
    })
  }

  # Caller overrides plus, for an initiative target with a requested effect, a
  # synthesised member-scoped effect override unless an equivalent one exists.
  compiled_overrides = {
    for key, assignment in local.target_entries : key => concat(
      (assignment.overrides == null ? [] : assignment.overrides),
      assignment.target.initiative_key == null || assignment.requested_effect == null || anytrue([
        for override in(assignment.overrides == null ? [] : assignment.overrides) :
        try(local.normalised_effects[lower(trimspace(override.value))], trimspace(override.value)) == assignment.requested_effect &&
        try(length(override.selectors), 0) == 1 &&
        lower(try(override.selectors[0].kind, "")) == "policydefinitionreferenceid" &&
        try(contains(override.selectors[0].in, assignment.target.reference_id), false)
        ]) ? [] : [{
        kind  = "policyEffect"
        value = assignment.requested_effect
        selectors = [{
          kind = "PolicyDefinitionReferenceId"
          in   = [assignment.target.reference_id]
        }]
      }]
    )
  }

  # One normalised view per override: whether it sets an effect, the effect
  # value, its reference-ID selectors and whether any other selector kind
  # makes it conditional. Applicability to a reference ID is then a short
  # check over reference_selectors instead of a repeated raw-field walk.
  override_views = {
    for key, overrides in local.compiled_overrides : key => [
      for override in overrides : {
        is_effect = try(override.value, null) != null && contains(["effect", "policyeffect"], lower(trimspace(try(override.kind, try(override.field, "policyEffect")))))
        effect    = try(override.value, null) == null ? null : try(local.normalised_effects[lower(trimspace(override.value))], trimspace(override.value))
        reference_selectors = [
          for selector in(try(override.selectors, null) == null ? [] : override.selectors) : {
            in     = try(selector.in, null)
            not_in = try(selector.not_in, null)
          } if lower(try(selector.kind, "")) == "policydefinitionreferenceid"
        ]
        has_other_selector = anytrue([for selector in(try(override.selectors, null) == null ? [] : override.selectors) : lower(try(selector.kind, "")) != "policydefinitionreferenceid"])
      }
    ]
  }

  initiative_member_index = {
    for initiative_key, initiative in local.initiative_entries : initiative_key => {
      for member in initiative.policy_definition_references[*] : lower(trimspace(member.reference_id)) => member...
    }
  }

  initiative_member_entry_index = {
    for initiative_key, initiative in local.initiative_entries : initiative_key => [
      for member in initiative.policy_definition_references[*] : merge(member, {
        definition    = try(member.definition_key, null) == null || trimspace(try(member.definition_key, "")) == "" ? null : contains(keys(local.definition_entries), trimspace(member.definition_key)) ? local.definition_entries[trimspace(member.definition_key)] : null
        member_effect = try(member.effect, null) == null ? null : try(local.normalised_effects[lower(trimspace(member.effect))], trimspace(member.effect))
      })
    ]
  }

  member_entries = {
    for key, assignment in local.target_entries : key => (
      assignment.target.initiative_key == null ? null : contains(keys(local.initiative_member_index), assignment.target.initiative_key) ? (
        contains(keys(local.initiative_member_index[assignment.target.initiative_key]), lower(assignment.target.reference_id)) ? local.initiative_member_index[assignment.target.initiative_key][lower(assignment.target.reference_id)][0] : null
      ) : null
    )
  }

  initiative_member_entries = {
    for key, assignment in local.target_entries : key => (
      assignment.target.initiative_key == null ? null : contains(keys(local.initiative_member_entry_index), assignment.target.initiative_key) ? local.initiative_member_entry_index[assignment.target.initiative_key] : null
    )[*]
  }

  # The definition is the direct definition-key target, otherwise the targeted
  # member's definition when the assignment resolves through an initiative.
  resolved_definition_entries = {
    for key, assignment in local.target_entries : key => (
      assignment.target.definition_key != null ? assignment.definition : (
        trimspace(try(local.member_entries[key].definition_key, "")) == "" ? null :
        try(local.definition_entries[trimspace(local.member_entries[key].definition_key)], null)
      )
    )
  }

  target_rules = {
    # Iterating the enriched target_entries records makes the initiative rules
    # read the resolved initiative lookup instead of the raw assignment intent,
    # which never carries the initiative envelope.
    for key, assignment in local.target_entries : key => {
      exactly_one_target        = length([for value in [assignment.target.definition_key, assignment.target.initiative_key, assignment.target.policy_definition_id] : value if value != null]) == 1
      definition_exists         = assignment.target.definition_key == null ? true : contains(keys(local.definition_entries), assignment.target.definition_key)
      initiative_exists         = assignment.target.initiative_key == null ? true : contains(keys(local.initiative_entries), assignment.target.initiative_key)
      initiative_contract_valid = assignment.target.initiative_key == null ? true : try(trimspace(assignment.initiative.id), "") != "" && try(assignment.initiative.created_by_module, null) != null
      member_exists             = assignment.target.initiative_key == null ? true : try(contains(keys(local.initiative_member_index[assignment.target.initiative_key]), lower(trimspace(assignment.target.reference_id))), false)
      direct_id_valid           = assignment.target.policy_definition_id == null || can(regex("^(/providers/Microsoft\\.Authorization/policyDefinitions/[^/]+|/subscriptions/[0-9a-fA-F-]{36}/providers/Microsoft\\.Authorization/policyDefinitions/[^/]+|/providers/Microsoft\\.Management/managementGroups/[^/]+/providers/Microsoft\\.Authorization/policyDefinitions/[^/]+)$", assignment.target.policy_definition_id))
      definition_id_known       = assignment.target.policy_definition_id != null ? true : assignment.target.initiative_key != null ? try(trimspace(assignment.initiative.id), "") != "" : try(trimspace(local.resolved_definition_entries[key].id), "") != ""
      scope_id_valid            = can(regex(local.scope_patterns[assignment.scope.type], assignment.scope.id))
    }
  }

  # Effect overrides applicable to the direct target reference.
  effect_override_values = {
    for key, assignment in local.target_entries : key => [
      for override in local.override_views[key] : override.effect
      if override.is_effect && alltrue([
        for selector in override.reference_selectors :
        selector.in != null ? contains(selector.in, assignment.target.reference_id) :
        selector.not_in != null ? !contains(selector.not_in, assignment.target.reference_id) : false
      ])
    ]
  }

  effect_candidates = {
    for key, assignment in local.target_entries : key => {
      direct             = assignment.requested_effect
      member             = try(local.member_entries[key].effect, null) == null ? null : try(local.normalised_effects[lower(trimspace(local.member_entries[key].effect))], trimspace(local.member_entries[key].effect))
      definition_default = try(local.resolved_definition_entries[key].default_effect, null)
      selected_override  = length(local.effect_override_values[key]) == 0 ? null : local.effect_override_values[key][0]
    }
  }

  # Precedence: assignment effect, member effect, definition default. A
  # conditional chain, not coalesce: coalesce errors when every candidate is
  # null, which is exactly the unknown-reference case the guard must report.
  selected_effects = {
    for key, candidate in local.effect_candidates : key => (
      try(trimspace(candidate.direct), "") != "" ? candidate.direct :
      try(trimspace(candidate.member), "") != "" ? candidate.member :
      try(trimspace(candidate.definition_default), "") != "" ? candidate.definition_default : null
    )
  }

  effective_effects = {
    for key, candidate in local.effect_candidates : key => local.target_entries[key].target.initiative_key == null ? (candidate.selected_override != null ? candidate.selected_override : local.selected_effects[key]) : (
      length(local.initiative_member_decisions[key]) > 0 && alltrue([for member in local.initiative_member_decisions[key] : member.effective_effect != null]) && length(distinct([for member in local.initiative_member_decisions[key] : member.effective_effect])) == 1 ? local.initiative_member_decisions[key][0].effective_effect : null
    )
  }

  effect_override_conflicts = {
    for key, candidate in local.effect_candidates : key => length(distinct(local.effect_override_values[key])) > 1
  }

  normalised_supported_effects = {
    for key, definition in local.resolved_definition_entries : key => try(definition.normalised_supported_effects, null)
  }

  # Stage 1 per initiative member: base effect by precedence (member-scoped
  # assignment effect, member effect, definition default) and the applicable
  # effect overrides.
  initiative_member_effects = {
    for key, members in local.initiative_member_entries : key => [
      for member in members : {
        reference_id              = member.reference_id
        definition_key            = try(member.definition_key, null)
        requested_effect          = local.target_entries[key].target.reference_id == member.reference_id ? local.target_entries[key].requested_effect : null
        member_effect             = try(member.effect, null)
        definition_default_effect = try(member.definition.default_effect, null)
        base_effect = (
          local.target_entries[key].target.reference_id == member.reference_id && try(trimspace(local.target_entries[key].requested_effect), "") != "" ? local.target_entries[key].requested_effect :
          try(trimspace(member.member_effect), "") != "" ? member.member_effect :
          try(trimspace(member.definition.default_effect), "") != "" ? member.definition.default_effect : null
        )
        override_effects = [
          for override in local.override_views[key] : override.effect
          if override.is_effect && alltrue([
            for selector in override.reference_selectors :
            selector.in != null ? contains(selector.in, member.reference_id) :
            selector.not_in != null ? !contains(selector.not_in, member.reference_id) : false
          ])
        ]
        conditional_override = anytrue([
          for override in local.override_views[key] : override.is_effect && override.has_other_selector && alltrue([
            for selector in override.reference_selectors :
            selector.in != null ? contains(selector.in, member.reference_id) :
            selector.not_in != null ? !contains(selector.not_in, member.reference_id) : false
          ])
        ])
      }
    ]
  }

  # Stage 2: the set of effects a member may evaluate with. An unconditional
  # override replaces the base effect; a conditional one adds to it.
  initiative_member_possible_effects = {
    for key, members in local.initiative_member_effects : key => [
      for member in members : distinct(concat(
        member.conditional_override || length(member.override_effects) == 0 ? [for value in [member.base_effect] : value if value != null] : [],
        member.override_effects
      ))
    ]
  }

  # Stage 3: decisions derived from the possible-effect set, read by every
  # later identity, role and remediation local.
  initiative_member_decisions = {
    for key, members in local.initiative_member_effects : key => [
      for member_index, member in members : {
        reference_id      = member.reference_id
        definition_key    = member.definition_key
        requested_effect  = member.requested_effect
        member_effect     = member.member_effect
        base_effect       = member.base_effect
        possible_effects  = local.initiative_member_possible_effects[key][member_index]
        effective_effect  = length(local.initiative_member_possible_effects[key][member_index]) == 1 ? local.initiative_member_possible_effects[key][member_index][0] : null
        override_conflict = length(distinct(member.override_effects)) > 1
        needs_identity    = anytrue([for effect in local.initiative_member_possible_effects[key][member_index] : contains(local.identity_effects, effect)])
      }
    ]
  }

  initiative_identity_required = {
    for key, members in local.initiative_member_decisions : key => (
      anytrue([for member in members : member.needs_identity]) ? true :
      alltrue([for member in members : member.effective_effect != null]) ? false : null
    )
  }

  initiative_required_roles = {
    for key, members in local.initiative_member_entries : key => distinct(flatten([
      for member_index, member in members :
      local.initiative_member_decisions[key][member_index].needs_identity ? (try(member.role_definition_ids, null) == null ? [] : try(tolist(member.role_definition_ids), [])) : []
    ]))
  }

  initiative_roles_unknown = {
    for key, members in local.initiative_member_entries : key => anytrue([
      for member_index, member in members :
      local.initiative_member_decisions[key][member_index].needs_identity && try(member.role_definition_ids == null, true)
    ])
  }

  initiative_aggregate_roles = {
    for key, roles in local.initiative_required_roles : key => local.initiative_identity_required[key] == false ? [] : local.initiative_identity_required[key] == null || local.initiative_roles_unknown[key] ? null : roles
  }

  initiative_unsupported_effects = {
    for key, members in local.initiative_member_entries : key => flatten([
      for member_index, member in members : [
        for effect in local.initiative_member_decisions[key][member_index].possible_effects : effect
        if try(member.definition.normalised_supported_effects, null) != null && !contains(member.definition.normalised_supported_effects, effect)
      ]
    ])
  }

  initiative_member_operation_decisions = {
    for key, members in local.initiative_member_entries : key => [
      for member_index, member in members : {
        identity_required = local.initiative_member_decisions[key][member_index].needs_identity ? true : local.initiative_member_decisions[key][member_index].effective_effect == null ? null : false
        required_roles = (
          local.initiative_member_decisions[key][member_index].needs_identity
          ? (try(member.role_definition_ids, null) == null ? null : [
            for role_id in tolist(member.role_definition_ids) : {
              role_definition_id = role_id
              purpose            = "policy_effect"
              grant_scope        = coalesce(try(trimspace(local.target_entries[key].role_grant_scopes[role_id]), null), local.target_entries[key].scope.id)
            }
          ])
          : local.initiative_member_decisions[key][member_index].effective_effect == null ? null : []
        )
        remediation_eligibility = (
          local.initiative_member_decisions[key][member_index].needs_identity
          ? (try(member.role_definition_ids, null) == null ? null : length(member.role_definition_ids) == 0 ? "blocked" : "eligible")
          : local.initiative_member_decisions[key][member_index].effective_effect == null ? null : "not_eligible"
        )
        remediation_reason = (
          local.initiative_member_decisions[key][member_index].needs_identity
          ? (try(member.role_definition_ids, null) == null ? "Eligibility is unknown because this member's role candidates are unknown." : length(member.role_definition_ids) == 0 ? "This member requires remediation identity but has no role candidates." : "This member can execute remediation and has role candidates.")
          : local.initiative_member_decisions[key][member_index].effective_effect == null ? "Eligibility is unknown because this member's effective effect is unknown." : "This member's effective effect does not support remediation."
        )
      }
    ]
  }

  version_candidates = {
    for key, assignment in local.target_entries : key => {
      requested_pin              = assignment.requested_pin
      requested_constraint       = assignment.requested_constraint
      version_binding            = assignment.version_binding
      member_pin                 = try(local.member_entries[key].pinned_version, null)
      member_constraint          = try(local.member_entries[key].version_constraint, null)
      initiative_content_version = try(assignment.initiative.version, null)
      definition_pin             = try(local.resolved_definition_entries[key].pinned_version, null)
      definition_constraint      = try(local.resolved_definition_entries[key].version_constraint, null)
      # Custom content versions (metadata.version) are provenance, not
      # version intent: the definitions envelope only carries them for
      # custom entries and no provider argument can reference them.
      definition_version = null
    }
  }

  version_contradictions = {
    for key, candidate in local.version_candidates : key => (
      (candidate.requested_pin != null && candidate.requested_constraint != null) ||
      (candidate.member_pin != null && candidate.member_constraint != null) ||
      (candidate.definition_pin != null && candidate.definition_constraint != null) ||
      length(distinct([
        for value in [candidate.requested_pin, candidate.requested_constraint, candidate.member_pin, candidate.member_constraint, candidate.definition_pin, candidate.definition_constraint] : value
        if value != null
      ])) > 1
    )
  }

  requested_versions = {
    for key, candidate in local.version_candidates : key => candidate.requested_pin != null ? candidate.requested_pin : candidate.requested_constraint
  }

  inherited_versions = {
    for key, candidate in local.version_candidates : key => candidate.member_pin != null ? candidate.member_pin : candidate.member_constraint
  }

  declared_versions = {
    for key, candidate in local.version_candidates : key => candidate.definition_pin != null ? candidate.definition_pin : candidate.definition_constraint != null ? candidate.definition_constraint : candidate.definition_version
  }

  selected_versions = {
    for key, candidate in local.version_candidates : key => local.version_contradictions[key] || candidate.version_binding == "unversioned" ? null : local.requested_versions[key] != null ? local.requested_versions[key] : local.inherited_versions[key] != null ? local.inherited_versions[key] : local.declared_versions[key]
  }

  parameter_mappings = {
    for key, member in local.member_entries : key => try(member.parameter_mappings, try(member.parameter_values, null))
  }

  parameter_values = {
    for key, assignment in local.target_entries : key => (
      local.parameter_mappings[key] == null && assignment.parameters == null ? null : merge(
        try({
          for parameter_key, parameter_value in local.parameter_mappings[key] : parameter_key => parameter_value
        }, {}),
        try({
          for parameter_key, parameter_value in assignment.parameters : parameter_key => parameter_value
        }, {})
      )
    )
  }

  candidate_roles = {
    for key, definition in local.resolved_definition_entries : key => local.target_entries[key].target.initiative_key == null ? try(definition.role_definition_ids, null) : local.initiative_aggregate_roles[key]
  }

  identity_required = {
    for key, effect in local.effective_effects : key => local.target_entries[key].target.initiative_key == null ? (effect == null ? null : contains(local.identity_effects, effect)) : local.initiative_identity_required[key]
  }

  identity_strategies = {
    for key, required in local.identity_required : key => required == null ? null : required ? try(local.target_entries[key].identity_intent.strategy, "user_assigned") : "none"
  }

  identity_rules = {
    for key, required in local.identity_required : key => {
      strategy_valid       = required == null ? true : required == true ? contains(["user_assigned"], local.identity_strategies[key]) : try(local.target_entries[key].identity_intent.strategy, null) == null || try(local.target_entries[key].identity_intent.strategy, "") == "none"
      location_value       = try(trimspace(coalesce(local.target_entries[key].identity_intent.location, "")), "")
      resource_group_value = try(trimspace(coalesce(local.target_entries[key].identity_intent.resource_group_name, "")), "")
      location_valid       = required != true || (try(trimspace(coalesce(local.target_entries[key].identity_intent.location, "")), "") != "" && lower(try(trimspace(coalesce(local.target_entries[key].identity_intent.location, "")), "")) != "global")
      resource_group_valid = required != true || try(trimspace(coalesce(local.target_entries[key].identity_intent.resource_group_name, "")), "") != ""
      roles_known          = required != true || try(local.candidate_roles[key] != null, false)
      roles_non_empty      = required != true || try(local.candidate_roles[key] == null || length(local.candidate_roles[key]) > 0, false)
      role_ids_valid       = required != true || try(local.candidate_roles[key] == null || alltrue([for role_id in tolist(local.candidate_roles[key]) : can(regex("^/(subscriptions/[0-9a-fA-F-]{36}/)?providers/Microsoft\\.Authorization/roleDefinitions/[0-9a-fA-F-]{36}$", trimspace(role_id)))]), false)
    }
  }

  required_roles = {
    for key, roles in local.candidate_roles : key => local.identity_required[key] == null ? null : !local.identity_required[key] ? [] : roles == null ? null : [
      for role_id in tolist(roles) : {
        role_definition_id = role_id
        purpose            = "policy_effect"
        # An explicit caller-supplied grant scope for this role wins; the
        # assignment scope is only the documented fallback, never a broad default.
        grant_scope = coalesce(try(trimspace(local.target_entries[key].role_grant_scopes[role_id]), null), local.target_entries[key].scope.id)
      }
    ]
  }

  remediation_eligibility = {
    for key, required in local.identity_required : key => required == null ? null : !required ? "not_eligible" : local.candidate_roles[key] == null ? null : length(local.candidate_roles[key]) == 0 ? "blocked" : "eligible"
  }

  governance_decisions = {
    for key, assignment in local.target_entries : key => length([for value in [try(local.resolved_definition_entries[key].governance, null), try(assignment.initiative.governance, null), assignment.governance] : value if value != null]) == 0 ? null : merge([for value in [try(local.resolved_definition_entries[key].governance, null), try(assignment.initiative.governance, null), assignment.governance] : value if value != null]...)
  }

  resolved_assignments = {
    for key, assignment in local.target_entries : key => {
      assignment_key = key
      intent = {
        target                  = assignment.target
        scope                   = assignment.scope
        parameters              = assignment.parameters
        selectors               = assignment.selectors
        overrides               = assignment.overrides
        exclusions              = assignment.exclusions
        enforcement_mode        = assignment.enforcement_mode
        non_compliance_messages = assignment.non_compliance_messages
        rollout                 = assignment.rollout
        governance              = assignment.governance
        version_constraint      = assignment.requested_constraint
        pinned_version          = assignment.requested_pin
        version_binding         = assignment.version_binding
      }
      resolved = {
        # An initiative-keyed assignment targets the initiative's policy set
        # definition resource, never one member policy definition.
        policy_definition_id = assignment.target.policy_definition_id != null ? assignment.target.policy_definition_id : assignment.target.initiative_key != null ? try(assignment.initiative.id, null) : try(local.resolved_definition_entries[key].id, null)
        # The definition's own default effect, used by assignments to decide
        # whether an effective effect needs an explicit override or parameter.
        definition_default_effect  = local.effect_candidates[key].definition_default
        definition_key             = assignment.target.definition_key != null ? assignment.target.definition_key : try(local.member_entries[key].definition_key, null)
        initiative_key             = assignment.target.initiative_key
        member_reference_id        = assignment.target.initiative_key == null ? null : assignment.target.reference_id
        requested_effect           = local.effect_candidates[key].direct
        effective_effect           = local.effective_effects[key]
        member_effect              = try(local.member_entries[key].effect, null)
        member_required            = try(local.member_entries[key].required, null)
        requested_version          = local.requested_versions[key]
        inherited_version          = local.inherited_versions[key]
        selected_version           = local.selected_versions[key]
        source_version             = local.declared_versions[key]
        initiative_content_version = try(local.version_candidates[key].initiative_content_version, null)
        parameter_schema           = try(assignment.initiative.parameter_schema, try(local.resolved_definition_entries[key].parameters, null))
        parameter_values           = local.parameter_values[key]
        parameter_mappings         = local.parameter_mappings[key]
        capabilities               = try(local.resolved_definition_entries[key].capabilities, null)
        list_fields = {
          supported_effects       = local.normalised_supported_effects[key]
          supported_overrides     = try(local.resolved_definition_entries[key].supported_overrides, null)
          selectors               = try(local.resolved_definition_entries[key].selectors, null)
          non_compliance_messages = try(local.resolved_definition_entries[key].non_compliance_messages, null)
          role_definition_ids     = local.candidate_roles[key]
        }
        members = [
          for member_index, member in local.initiative_member_entries[key] : {
            reference_id            = member.reference_id
            definition_key          = try(member.definition_key, null)
            policy_definition_id    = try(member.policy_definition_id, try(member.target.policy_definition_id, try(member.definition.id, null)))
            source_type             = try(member.source_type, null)
            created_by_module       = try(member.created_by_module, null)
            requested_effect        = local.initiative_member_decisions[key][member_index].requested_effect
            member_effect           = local.initiative_member_decisions[key][member_index].member_effect
            effective_effect        = local.initiative_member_decisions[key][member_index].effective_effect
            possible_effects        = local.initiative_member_decisions[key][member_index].possible_effects
            override_conflict       = local.initiative_member_decisions[key][member_index].override_conflict
            identity_required       = local.initiative_member_operation_decisions[key][member_index].identity_required
            required_roles          = local.initiative_member_operation_decisions[key][member_index].required_roles
            remediation_eligibility = local.initiative_member_operation_decisions[key][member_index].remediation_eligibility
            remediation_reason      = local.initiative_member_operation_decisions[key][member_index].remediation_reason
            selected_version        = try(member.selected_version, try(member.resource_version, null))
            parameter_schema        = try(member.parameter_schema, null)
            parameter_values        = try(member.parameter_values, null)
            parameter_mappings      = try(member.parameter_mappings, try(member.parameter_values, null))
            capabilities            = try(member.capabilities, null)
            list_fields             = merge(try(member.list_fields, null) == null ? {} : member.list_fields, { role_definition_ids = try(member.role_definition_ids, null) })
            role_definition_ids     = try(member.role_definition_ids, null)
            governance              = try(member.governance, null)
          }
        ]
        selectors            = assignment.selectors
        overrides            = local.compiled_overrides[key]
        member_reference_ids = try([for member in assignment.initiative.policy_definition_references : member.reference_id], [])
        exclusions           = assignment.exclusions
        identity = {
          required            = local.identity_required[key]
          strategy            = local.identity_strategies[key]
          name_basis          = key
          location            = try(assignment.identity_intent.location, null)
          resource_group_name = try(assignment.identity_intent.resource_group_name, null)
          rationale           = local.identity_required[key] == null ? "Identity requirement is unknown because effective effect is unknown." : local.identity_required[key] ? "Effective effect requires a managed identity for policy remediation; role candidates are preserved without grants." : "Effective effect does not require an assignment identity."
        }
        required_roles          = local.required_roles[key]
        remediation_eligibility = local.remediation_eligibility[key]
        remediation_reason      = local.remediation_eligibility[key] == null ? "Eligibility is unknown because required policy capability or role information is unknown." : local.remediation_eligibility[key] == "eligible" ? "Modify or DeployIfNotExists is known and role candidates are supplied." : local.remediation_eligibility[key] == "blocked" ? "The effective effect requires an identity but no role definitions were supplied." : "The effective effect does not support remediation."
        governance              = local.governance_decisions[key]
        resolution_rationale    = "Effect precedence: applicable effect override, member-scoped assignment effect, initiative member effect, definition capability default, policy-rule default. Version precedence: assignment intent, member intent, definition intent. Initiative content version is provenance metadata and does not select a policy deployment version. Initiative set identity and role decisions aggregate all members. Enforcement mode remains assignment intent and is not an effect."
      }
      assignment = {
        id   = null
        name = null
      }
    }
  }

  resolution_summary = {
    total_assignments = length(local.resolved_assignments)
    definition_keys   = sort(keys(local.definition_entries))
    initiative_keys   = sort(keys(local.initiative_entries))
    assignment_keys   = sort(keys(local.resolved_assignments))
  }
}
