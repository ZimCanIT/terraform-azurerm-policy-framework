variable "identity_bindings" {
  description = "Identity-RBAC output records keyed by stable assignment key."
  type        = any
  default     = {}

  validation {
    condition     = can(keys(var.identity_bindings)) && !can(tolist(var.identity_bindings))
    error_message = "identity_bindings must be a keyed object or map."
  }

  validation {
    condition = try(alltrue([
      for key, binding in var.identity_bindings :
      trimspace(key) != "" && can(keys(binding)) &&
      length(setsubtract(toset(keys(binding)), toset(["assignment_key", "id", "identity_id", "principal_id", "identity_strategy"]))) == 0 &&
      contains(["none", "user_assigned"], try(binding.identity_strategy, null)) &&
      try(binding.assignment_key, null) == key &&
      (binding.identity_strategy == "none" ? try(binding.id, null) == null && try(binding.identity_id, null) == null && try(binding.principal_id, null) == null :
        can(regex("^/.*$", trimspace(binding.id))) && trimspace(binding.id) != "" &&
      can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", trimspace(binding.principal_id))))
    ]), false)
    error_message = "Each identity binding must match the resolver-owned none or user_assigned decision and contain the correct principal fields."
  }
}

variable "assignments" {
  description = "Typed Azure Policy assignment intent keyed by stable assignment key. Each entry consumes resolved behaviour and canonical catalogue objects, and the module does not read source files."
  type        = any
  default     = {}

  validation {
    condition     = can(keys(var.assignments)) && !can(tolist(var.assignments))
    error_message = "assignments must be a keyed object or map of assignment objects with non-blank string keys."
  }

  validation {
    condition = try(alltrue([
      for key, assignment in var.assignments :
      trimspace(key) != "" && can(keys(assignment))
    ]), false)
    error_message = "Each assignment must be an object with a non-blank assignment key."
  }

  validation {
    # Contract boundary: flattened legacy control fields are rejected here, so
    # the nested rules below can read assignment.intent only.
    condition = try(alltrue([
      for _, assignment in var.assignments :
      length(setsubtract(toset(keys(assignment)), toset([
        "assignment_key", "intent", "resolved", "assignment"
      ]))) == 0
    ]), false)
    error_message = "Assignments may contain only fields from the canonical assignments contract."
  }

  validation {
    condition = try(alltrue([
      for _, assignment in var.assignments :
      can(keys(assignment.intent)) && can(keys(assignment.resolved)) &&
      length(setsubtract(toset(keys(assignment.intent)), toset([
        "target", "scope", "parameters", "selectors", "overrides", "exclusions", "enforcement_mode", "non_compliance_messages", "rollout", "governance", "version_constraint", "pinned_version", "version_binding"
      ]))) == 0 &&
      length(setsubtract(toset(keys(assignment.resolved)), toset([
        "policy_definition_id", "definition_key", "initiative_key", "member_reference_id", "member_reference_ids", "requested_effect", "effective_effect", "definition_default_effect", "member_effect", "member_required", "requested_version", "inherited_version", "selected_version", "source_version", "initiative_content_version", "parameter_schema", "parameter_values", "parameter_mappings", "capabilities", "list_fields", "members", "selectors", "overrides", "exclusions", "identity", "required_roles", "remediation_eligibility", "remediation_reason", "governance", "resolution_rationale"
      ]))) == 0 &&
      can(keys(assignment.intent.target)) && can(keys(assignment.intent.scope)) &&
      length(setsubtract(toset(keys(assignment.intent.target)), toset(["reference_id", "definition_key", "initiative_key", "policy_definition_id"]))) == 0 &&
      length(setsubtract(toset(keys(assignment.intent.scope)), toset(["type", "id"]))) == 0 &&
      trimspace(try(assignment.intent.target.reference_id, "")) != "" &&
      contains(["management_group", "subscription", "resource_group", "resource"], try(assignment.intent.scope.type, "")) &&
      trimspace(try(assignment.intent.scope.id, "")) != "" &&
      (try(assignment.intent.parameters, null) == null || can(keys(assignment.intent.parameters))) &&
      (try(assignment.intent.selectors, null) == null || can(regex("^\\[", jsonencode(assignment.intent.selectors)))) &&
      (try(assignment.intent.overrides, null) == null || (can(regex("^\\[", jsonencode(assignment.intent.overrides))) && alltrue([for override in assignment.intent.overrides : can(keys(override))]))) &&
      (try(assignment.intent.exclusions, null) == null || can(regex("^\\[", jsonencode(assignment.intent.exclusions)))) &&
      (try(assignment.intent.non_compliance_messages, null) == null || (can(regex("^\\[", jsonencode(assignment.intent.non_compliance_messages))) && alltrue([for message in assignment.intent.non_compliance_messages : can(keys(message))]))) &&
      (try(assignment.intent.rollout, null) == null || can(keys(assignment.intent.rollout))) &&
      (try(assignment.intent.governance, null) == null || can(keys(assignment.intent.governance)))
    ]), false)
    error_message = "Each assignment must contain only the documented nested intent and resolved fields with valid container shapes."
  }

  validation {
    condition = try(alltrue([
      for _, assignment in var.assignments :
      contains(["management_group", "subscription", "resource_group", "resource"], assignment.intent.scope.type) &&
      can(regex(
        assignment.intent.scope.type == "management_group" ? "^/providers/Microsoft\\.Management/managementGroups/[^/]+$" :
        assignment.intent.scope.type == "subscription" ? "^/subscriptions/[0-9a-fA-F-]{36}$" :
        assignment.intent.scope.type == "resource_group" ? "^/subscriptions/[0-9a-fA-F-]{36}/resourceGroups/[^/]+$" :
        "^/subscriptions/[0-9a-fA-F-]{36}/resourceGroups/[^/]+/providers/.+/.+$",
        trimspace(assignment.intent.scope.id)
      ))
    ]), false)
    error_message = "Each assignment scope must declare a supported type and a matching Azure scope ID."
  }

  validation {
    condition = try(alltrue([
      for _, assignment in var.assignments :
      trimspace(try(assignment.intent.target.reference_id, "")) != "" &&
      trimspace(try(assignment.resolved.policy_definition_id, "")) != ""
    ]), false)
    error_message = "Each resolved assignment must declare a non-blank target reference_id and resolved policy_definition_id."
  }

  validation {
    condition = try(alltrue([
      for _, assignment in var.assignments :
      try(assignment.intent.version_binding, null) == null || assignment.intent.version_binding == "unversioned"
    ]), false)
    error_message = "Assignment version_binding must be omitted or set to unversioned."
  }

  validation {
    condition = try(alltrue([
      for _, assignment in var.assignments :
      try(assignment.intent.version_binding, null) != "unversioned" || (
        try(assignment.intent.target.initiative_key, null) == null &&
        try(assignment.intent.pinned_version, null) == null &&
        try(assignment.intent.version_constraint, null) == null &&
        try(assignment.resolved.selected_version, null) == null
      )
    ]), false)
    error_message = "Assignment ${try(join(", ", [for key, assignment in var.assignments : key if try(assignment.intent.version_binding, null) == "unversioned" && (try(assignment.intent.target.initiative_key, null) != null || try(assignment.intent.pinned_version, null) != null || try(assignment.intent.version_constraint, null) != null || try(assignment.resolved.selected_version, null) != null)]), "<invalid assignments container>")} may use version_binding unversioned only for a direct target with no assignment version request and no selected deployment version."
  }

  validation {
    condition = try(alltrue([
      for _, assignment in var.assignments :
      try(assignment.resolved == null, true) || (
        (try(assignment.resolved.effective_effect == null, true) || can(regex("^\".*\"$", jsonencode(assignment.resolved.effective_effect)))) &&
        (try(assignment.resolved.definition_default_effect == null, true) || can(regex("^\".*\"$", jsonencode(assignment.resolved.definition_default_effect)))) &&
        // Resolver emits pinned x.y.z or wildcard x.y.* / x.*.* member intents; all must pass through.
        (try(assignment.resolved.selected_version == null, true) || can(regex("^[0-9]+\\.([0-9]+|\\*)(\\.\\*|\\.[0-9]+)?$", trimspace(assignment.resolved.selected_version)))) &&
        (try(assignment.resolved.source_version == null, true) || can(regex("^[0-9]+\\.([0-9]+|\\*)(\\.\\*|\\.[0-9]+)?$", trimspace(assignment.resolved.source_version)))) &&
        (try(assignment.resolved.parameter_schema == null, true) || can(keys(assignment.resolved.parameter_schema))) &&
        (try(assignment.resolved.members == null, true) || (can(regex("^\\[", jsonencode(assignment.resolved.members))) && alltrue([for member in assignment.resolved.members : can(keys(member))]))) &&
        (try(assignment.resolved.required_roles == null, true) || (can(regex("^\\[", jsonencode(assignment.resolved.required_roles))) && alltrue([for role in assignment.resolved.required_roles : can(keys(role))]))) &&
        (try(assignment.resolved.capabilities == null, true) || can(keys(assignment.resolved.capabilities))) &&
        (try(assignment.resolved.governance == null, true) || can(keys(assignment.resolved.governance))) &&
        (try(assignment.resolved.list_fields == null, true) || can(keys(assignment.resolved.list_fields)))
      )
    ]), false)
    error_message = "Resolved behaviour, when supplied, must preserve capability, governance and list-field objects with their native container shapes."
  }

  validation {
    condition = try(alltrue([
      for _, assignment in var.assignments :
      try(assignment.resolved.members, null) == null || alltrue([
        for member in assignment.resolved.members : can(keys(member)) &&
        length(setsubtract(toset(keys(member)), toset([
          "reference_id", "definition_key", "policy_definition_id", "source_type", "created_by_module",
          "requested_effect", "member_effect", "effective_effect", "possible_effects", "override_conflict", "identity_required",
          "selected_version", "parameter_schema", "parameter_values", "parameter_mappings", "capabilities",
          "list_fields", "role_definition_ids", "required_roles", "remediation_eligibility", "remediation_reason", "governance"
        ]))) == 0 && trimspace(try(member.reference_id, "")) != "" &&
        (try(member.parameter_schema, null) == null || can(keys(member.parameter_schema))) &&
        (try(member.capabilities, null) == null || can(keys(member.capabilities))) &&
        (try(member.list_fields, null) == null || can(keys(member.list_fields))) &&
        (try(member.role_definition_ids, null) == null || can(tolist(member.role_definition_ids))) &&
        (try(member.possible_effects, null) == null || can(tolist(member.possible_effects)))
      ])
    ]), false)
    error_message = "Resolved initiative members must preserve unique non-blank reference IDs and the documented effect, version, schema, capability and role containers."
  }

  validation {
    condition = try(alltrue([
      for _, assignment in var.assignments :
      try(assignment.intent.parameters == null, true) || can(keys(assignment.intent.parameters))
    ]), false)
    error_message = "Assignment parameters, when supplied, must be an object keyed by parameter name."
  }

  validation {
    condition = try(alltrue([
      for _, assignment in var.assignments :
      try(assignment.intent.selectors == null, true) || alltrue([
        for selector in assignment.intent.selectors :
        can(keys(selector)) && (
          trimspace(try(selector.kind, "")) != "" ||
          (can(regex("^\\[", jsonencode(selector.selectors))) && alltrue([
            for nested in selector.selectors : can(keys(nested)) && trimspace(try(nested.kind, "")) != ""
          ]))
        )
      ])
    ]), false)
    error_message = "Assignment selectors must be a list of selector objects with a non-blank kind."
  }

  validation {
    condition = try(alltrue([
      for _, assignment in var.assignments :
      try(assignment.intent.overrides == null, true) || alltrue([
        for override in assignment.intent.overrides :
        can(keys(override)) && trimspace(override.value) != ""
      ])
    ]), false)
    error_message = "Assignment overrides must be a list of override objects with a non-blank value."
  }

  validation {
    condition = try(alltrue([
      for _, assignment in var.assignments :
      try(assignment.intent.exclusions == null, true) || alltrue([
        for exclusion in assignment.intent.exclusions :
        can(regex("^/.*$", trimspace(exclusion)))
      ])
    ]), false)
    error_message = "Assignment exclusions must be a list of non-blank Azure scope IDs."
  }

  validation {
    condition = try(alltrue([
      for _, assignment in var.assignments :
      try(assignment.intent.non_compliance_messages == null, true) || alltrue([
        for message in assignment.intent.non_compliance_messages :
        can(keys(message)) && trimspace(message.content) != ""
      ])
    ]), false)
    error_message = "Assignment non_compliance_messages must be a list of message objects with non-blank content."
  }

  validation {
    condition = try(alltrue([
      for _, assignment in var.assignments :
      try(assignment.intent.enforcement_mode == null, true) || contains(["Default", "DoNotEnforce", "Enforce"], assignment.intent.enforcement_mode)
    ]), false)
    error_message = "Assignment enforcement_mode must be null, Default, DoNotEnforce or Enforce."
  }

  validation {
    condition = try(alltrue([
      for _, assignment in var.assignments :
      try(assignment.intent.rollout == null, true) || (
        try(assignment.intent.rollout.stage == null, true) || trimspace(assignment.intent.rollout.stage) != ""
        ) && (
        try(assignment.intent.rollout.intent == null, true) || trimspace(assignment.intent.rollout.intent) != ""
        ) && (
        try(assignment.intent.rollout.approval_reference == null, true) || trimspace(assignment.intent.rollout.approval_reference) != ""
      )
    ]), false)
    error_message = "Assignment rollout objects may only contain non-blank stage, intent and approval_reference strings when supplied."
  }
}
