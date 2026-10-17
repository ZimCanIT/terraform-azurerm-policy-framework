variable "definitions" {
  description = "Canonical policy definition resource outputs keyed by stable catalogue key."
  type        = any
  default     = {}

  validation {
    condition     = can(keys(var.definitions)) && !can(tolist(var.definitions))
    error_message = "definitions must be a keyed object or map of definition resource outputs."
  }
}

variable "initiatives" {
  description = "Canonical policy initiative resource outputs keyed by stable catalogue key."
  type        = any
  default     = {}

  validation {
    condition     = can(keys(var.initiatives)) && !can(tolist(var.initiatives))
    error_message = "initiatives must be a keyed object or map of initiative resource outputs."
  }

  validation {
    condition = try(alltrue([
      for _, initiative in var.initiatives : length(setsubtract(toset(keys(initiative)), toset([
        "catalogue_key", "id", "name", "display_name", "description", "management_group_id", "metadata",
        "parameters", "parameter_schema", "policy_definition_groups", "policy_definition_references", "governance", "version", "created_by_module"
      ]))) == 0
    ]), false)
    error_message = "Initiative resource outputs may contain only fields from the shared composition contract."
  }

  validation {
    condition = try(alltrue([
      for key, initiative in var.initiatives :
      trimspace(try(initiative.id, "")) != "" && try(initiative.created_by_module, null) != null
    ]), false)
    error_message = "Initiative resource output ${try(join(", ", [for key, initiative in var.initiatives : key if !try(trimspace(initiative.id) != "" && initiative.created_by_module != null, false)]), "<invalid input container>")} must preserve a non-blank id and created_by_module marker."
  }

  validation {
    condition = try(alltrue([
      for _, initiative in var.initiatives : alltrue([
        for member in try(initiative.policy_definition_references, []) : length(setsubtract(toset(keys(member)), toset([
          "reference_id", "definition_key", "initiative_key", "policy_definition_id", "parameter_values", "parameter_schema", "source_type", "created_by_module", "role_definition_ids",
          "group_names", "effect", "required", "version_constraint", "pinned_version", "inherited_version", "selected_version",
          "parameter_mappings", "capabilities", "list_fields", "governance", "resource_version", "provider_version", "target"
        ]))) == 0
      ])
    ]), false)
    error_message = "Initiative resource member outputs may contain only fields from the shared composition contract."
  }
}

variable "assignments" {
  description = "Assignment intent keyed by stable assignment key. Resolved decisions are produced by this module and must not be supplied by callers."
  type        = any
  default     = {}

  validation {
    condition     = can(keys(var.assignments)) && !can(tolist(var.assignments))
    error_message = "assignments must be a keyed object or map of assignment intent objects."
  }

  validation {
    condition = try(alltrue([
      for key, assignment in var.assignments : trimspace(key) != "" && can(keys(assignment))
    ]), false)
    error_message = "Each assignment must use a non-blank key and an object value."
  }

  validation {
    condition = try(alltrue([
      for key, assignment in var.assignments : length(setsubtract(toset(keys(assignment)), toset([
        "target", "scope", "parameters", "selectors", "overrides", "exclusions", "enforcement_mode",
        "non_compliance_messages", "rollout", "governance", "effect", "version_constraint", "pinned_version", "version_binding",
        "identity", "role_grant_scopes"
      ]))) == 0
    ]), false)
    error_message = "Assignment ${try(join(", ", [for key, assignment in var.assignments : key if !try(length(setsubtract(toset(keys(assignment)), toset(["target", "scope", "parameters", "selectors", "overrides", "exclusions", "enforcement_mode", "non_compliance_messages", "rollout", "governance", "effect", "version_constraint", "pinned_version", "version_binding", "identity", "role_grant_scopes"]))) == 0, false)]), "<invalid input container>")} must be an object containing only fields from the behaviour-resolution intent contract."
  }

  validation {
    condition = try(alltrue([
      for _, assignment in var.assignments : try(assignment.role_grant_scopes == null, true) || (
        can(keys(assignment.role_grant_scopes)) &&
        alltrue([
          for role_id, grant_scope in assignment.role_grant_scopes :
          can(regex("^\\\".*\\\"$", jsonencode(role_id))) && trimspace(role_id) != "" &&
          can(regex(local.role_grant_scope_pattern, trimspace(grant_scope)))
        ])
      )
    ]), false)
    error_message = "Assignment role_grant_scopes must be null or a map of role definition ID to a supported Azure scope ID; keys must be non-blank strings."
  }

  validation {
    condition = try(alltrue([
      for _, assignment in var.assignments : can(keys(assignment.target)) && can(keys(assignment.scope)) && trimspace(assignment.target.reference_id) != "" && contains(local.scope_types, assignment.scope.type) && trimspace(assignment.scope.id) != ""
    ]), false)
    error_message = "Each assignment requires a target reference_id and a supported non-blank scope."
  }

  validation {
    condition = try(alltrue([
      for _, assignment in var.assignments : length([
        for field in ["definition_key", "initiative_key", "policy_definition_id"] : field
        if try(trimspace(assignment.target[field]), "") != ""
      ]) == 1
    ]), false)
    error_message = "Each assignment target must declare exactly one of definition_key, initiative_key or policy_definition_id."
  }

  validation {
    condition = try(alltrue([
      for _, assignment in var.assignments : try(assignment.parameters == null, true) || can(keys(assignment.parameters))
    ]), false)
    error_message = "Assignment parameters must be null or an object keyed by parameter name."
  }

  validation {
    condition = try(alltrue([
      for _, assignment in var.assignments : try(assignment.overrides == null, true) || (
        can(regex("^\\[", jsonencode(assignment.overrides))) && alltrue([for override in assignment.overrides : can(keys(override))])
      )
    ]), false)
    error_message = "Assignment overrides must be null or a list of override objects."
  }

  validation {
    condition = try(alltrue([
      for _, assignment in var.assignments : try(assignment.effect == null, true) || can(regex("^[[:print:]]+$", assignment.effect))
    ]), false)
    error_message = "Assignment effect must be null or a printable string."
  }

  validation {
    condition = try(alltrue([
      for _, assignment in var.assignments : try(assignment.version_constraint == null, true) || can(regex("^[[:print:]]+$", assignment.version_constraint))
    ]), false)
    error_message = "Assignment version_constraint must be null or a printable string."
  }

  validation {
    condition = try(alltrue([
      for _, assignment in var.assignments : try(assignment.pinned_version == null, true) || can(regex("^[[:print:]]+$", assignment.pinned_version))
    ]), false)
    error_message = "Assignment pinned_version must be null or a printable string."
  }

  validation {
    condition = try(alltrue([
      for _, assignment in var.assignments : try(assignment.version_binding == null, true) || assignment.version_binding == "unversioned"
    ]), false)
    error_message = "Assignment version_binding must be omitted or set to unversioned."
  }

  validation {
    condition = try(alltrue([
      for _, assignment in var.assignments : try(assignment.version_binding, null) != "unversioned" || (
        try(assignment.target.initiative_key, null) == null &&
        try(assignment.pinned_version, null) == null &&
        try(assignment.version_constraint, null) == null
      )
    ]), false)
    error_message = "Assignment ${try(join(", ", [for key, assignment in var.assignments : key if try(assignment.version_binding, null) == "unversioned" && (try(assignment.target.initiative_key, null) != null || try(assignment.pinned_version, null) != null || try(assignment.version_constraint, null) != null)]), "<invalid input container>")} may use version_binding unversioned only for a direct target with no assignment version request."
  }
}
