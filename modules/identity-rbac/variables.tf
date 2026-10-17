variable "assignments" {
  description = "Canonical resolved assignment records keyed by stable assignment key."
  type        = any
  default     = {}

  validation {
    condition     = can(keys(var.assignments)) && !can(tolist(var.assignments))
    error_message = "assignments must be a keyed object or map of resolved assignment records."
  }

  validation {
    condition = try(alltrue([
      for key, assignment in var.assignments :
      trimspace(key) != "" && can(keys(assignment)) && can(keys(assignment.intent)) && can(keys(assignment.intent.scope)) && can(keys(assignment.resolved)) && can(keys(assignment.resolved.identity))
    ]), false)
    error_message = "Assignment records must identify a non-blank assignment key, intent scope and resolved identity decision. Invalid assignment keys: ${try(join(", ", [for key, assignment in var.assignments : key if !try(trimspace(key) != "" && can(keys(assignment)) && can(keys(assignment.intent)) && can(keys(assignment.intent.scope)) && can(keys(assignment.resolved)) && can(keys(assignment.resolved.identity)), false)]), "assignments (invalid container)")}."
  }

  validation {
    condition = try(alltrue([
      for key, assignment in var.assignments :
      length(setsubtract(toset(keys(assignment)), toset(["assignment_key", "intent", "resolved", "assignment"]))) == 0
    ]), false)
    error_message = "Assignments may contain only fields from the shared resolved-assignment contract."
  }

  validation {
    condition = try(alltrue([
      for key, assignment in var.assignments :
      contains(["management_group", "subscription", "resource_group", "resource"], assignment.intent.scope.type) && can(regex(
        assignment.intent.scope.type == "management_group" ? "^/providers/Microsoft\\.Management/managementGroups/[^/]+$" :
        assignment.intent.scope.type == "subscription" ? "^/subscriptions/[0-9a-fA-F-]{36}$" :
        assignment.intent.scope.type == "resource_group" ? "^/subscriptions/[0-9a-fA-F-]{36}/resourceGroups/[^/]+$" :
        "^/subscriptions/[0-9a-fA-F-]{36}/resourceGroups/[^/]+/providers/[^/]+/[^/]+/[^/]+(/[^/]+)*$",
        trimspace(assignment.intent.scope.id)
      ))
    ]), false)
    error_message = "Assignment ${try(join(", ", [for key, assignment in var.assignments : key if !can(regex(
      try(assignment.intent.scope.type, "") == "management_group" ? "^/providers/Microsoft\\.Management/managementGroups/[^/]+$" :
      try(assignment.intent.scope.type, "") == "subscription" ? "^/subscriptions/[0-9a-fA-F-]{36}$" :
      try(assignment.intent.scope.type, "") == "resource_group" ? "^/subscriptions/[0-9a-fA-F-]{36}/resourceGroups/[^/]+$" :
      "^/subscriptions/[0-9a-fA-F-]{36}/resourceGroups/[^/]+/providers/[^/]+/[^/]+/[^/]+(/[^/]+)*$",
      trimspace(try(assignment.intent.scope.id, ""))
    ))]), "assignments (invalid container)")} must declare a valid management group, subscription, resource group or resource scope; resource scopes must name a resource and reject a bare provider namespace or resource type."
  }

  validation {
    condition = try(alltrue([
      for key, assignment in var.assignments :
      contains([true, false], assignment.resolved.identity.required) && contains(["none", "user_assigned"], assignment.resolved.identity.strategy) && (assignment.resolved.identity.required ? assignment.resolved.identity.strategy == "user_assigned" : assignment.resolved.identity.strategy == "none")
    ]), false)
    error_message = "Identity decisions must use only the resolved none or user_assigned strategies, matching required. Invalid assignment keys: ${try(join(", ", [for key, assignment in var.assignments : key if !try(contains([true, false], assignment.resolved.identity.required) && contains(["none", "user_assigned"], assignment.resolved.identity.strategy) && (assignment.resolved.identity.required ? assignment.resolved.identity.strategy == "user_assigned" : assignment.resolved.identity.strategy == "none"), false)]), "assignments (invalid container)")}."
  }

  validation {
    condition = try(alltrue([
      for key, assignment in var.assignments :
      !assignment.resolved.identity.required || (
        can(regex("^\\\".*\\\"$", jsonencode(assignment.resolved.identity.name_basis))) && trimspace(assignment.resolved.identity.name_basis) != "" &&
        can(regex("^\\\".*\\\"$", jsonencode(assignment.resolved.identity.location))) && trimspace(assignment.resolved.identity.location) != "" &&
        can(regex("^\\\".*\\\"$", jsonencode(assignment.resolved.identity.resource_group_name))) && trimspace(assignment.resolved.identity.resource_group_name) != ""
      )
    ]), false)
    error_message = "Identity-required assignments need non-blank name_basis, location and resource_group_name."
  }

  validation {
    condition = try(alltrue([
      for key, assignment in var.assignments :
      can(tolist(assignment.resolved.required_roles)) && assignment.resolved.required_roles != null && (assignment.resolved.identity.required ? length(assignment.resolved.required_roles) > 0 : length(assignment.resolved.required_roles) == 0)
    ]), false)
    error_message = "Resolved required_roles must be known and non-empty for an identity, or explicitly empty without one. Invalid assignment keys: ${try(join(", ", [for key, assignment in var.assignments : key if !try(can(tolist(assignment.resolved.required_roles)) && assignment.resolved.required_roles != null && (assignment.resolved.identity.required ? length(assignment.resolved.required_roles) > 0 : length(assignment.resolved.required_roles) == 0), false)]), "assignments (invalid container)")}."
  }

  validation {
    condition = try(alltrue([
      for key, assignment in var.assignments :
      alltrue([
        for role_index, role in try(tolist(assignment.resolved.required_roles) == null ? [] : tolist(assignment.resolved.required_roles), []) :
        can(keys(role)) && length(setsubtract(toset(keys(role)), toset(["role_definition_id", "purpose", "grant_scope"]))) == 0
      ])
    ]), false)
    error_message = "Each required role must be an object containing only role_definition_id, purpose and grant_scope. Malformed grant entries: ${try(join(", ", flatten([for key, assignment in var.assignments : [for role_index, role in try(tolist(assignment.resolved.required_roles) == null ? [] : tolist(assignment.resolved.required_roles), []) : "${key}[${role_index}]" if !try(can(keys(role)) && length(setsubtract(toset(keys(role)), toset(["role_definition_id", "purpose", "grant_scope"]))) == 0, false)]])), "assignments (invalid container)")}. Blank or malformed role fields are rejected by the named grant preconditions with the assignment and grant key."
  }

  validation {
    condition = try(alltrue([
      for key, assignment in var.assignments :
      length(distinct([
        for role in try(tolist(assignment.resolved.required_roles) == null ? [] : tolist(assignment.resolved.required_roles), []) :
        "${lower(try(trimspace(role.role_definition_id), ""))}|${try(trimspace(role.grant_scope), "")}"
      ])) == length(try(tolist(assignment.resolved.required_roles) == null ? [] : tolist(assignment.resolved.required_roles), []))
    ]), false)
    error_message = "Each assignment must have unique role-definition and grant-scope pairs."
  }

  validation {
    condition = try(alltrue([
      for key, assignment in var.assignments :
      can(tolist(assignment.resolved.list_fields.role_definition_ids)) &&
      assignment.resolved.list_fields.role_definition_ids != null &&
      alltrue([
        for candidate in assignment.resolved.list_fields.role_definition_ids : can(regex("^/(subscriptions/[0-9a-fA-F-]{36}/)?providers/Microsoft\\.Authorization/roleDefinitions/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", trimspace(candidate)))
      ]) &&
      (assignment.resolved.identity.required ? length(assignment.resolved.list_fields.role_definition_ids) > 0 : length(assignment.resolved.list_fields.role_definition_ids) == 0)
    ]), false)
    error_message = "Each assignment must provide a verified candidate role list with valid role-definition resource IDs, non-empty for an identity and explicitly empty without one."
  }
}
