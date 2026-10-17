locals {
  # Shared grammar for the fail-closed grant preconditions; resource scopes must name a resource.
  grant_scope_pattern     = "^/providers/Microsoft\\.Management/managementGroups/[^/]+$|^/subscriptions/[0-9a-fA-F-]{36}$|^/subscriptions/[0-9a-fA-F-]{36}/resourceGroups/[^/]+$|^/subscriptions/[0-9a-fA-F-]{36}/resourceGroups/[^/]+/providers/[^/]+/[^/]+/[^/]+(/[^/]+)*$"
  role_definition_pattern = "^/(subscriptions/[0-9a-fA-F-]{36}/)?providers/Microsoft\\.Authorization/roleDefinitions/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"

  assignment_entries = {
    for key, assignment in var.assignments :
    key => {
      assignment_scope             = trimspace(assignment.intent.scope.id)
      effective_effect             = try(assignment.resolved.effective_effect, null)
      identity_required            = assignment.resolved.identity.required
      identity_strategy            = assignment.resolved.identity.strategy
      identity_name_basis          = assignment.resolved.identity.required ? trimspace(assignment.resolved.identity.name_basis) : null
      identity_location            = assignment.resolved.identity.required ? trimspace(assignment.resolved.identity.location) : null
      identity_resource_group_name = assignment.resolved.identity.required ? trimspace(assignment.resolved.identity.resource_group_name) : null
      # Each required role is normalised once here; the two digests fix the grant
      # key and the role-assignment name so no sha1 is re-evaluated downstream.
      required_role_entries = [
        for role in try(tolist(assignment.resolved.required_roles) == null ? [] : tolist(assignment.resolved.required_roles), []) : {
          grant_scope        = try(trimspace(role.grant_scope), "")
          role_definition_id = try(trimspace(role.role_definition_id), "")
          purpose            = try(trimspace(role.purpose), "")
          grant_key_digest   = sha1("${try(trimspace(role.grant_scope), "")}|${lower(try(trimspace(role.role_definition_id), ""))}")
          name_digest        = sha1("${key}|${try(trimspace(role.grant_scope), "")}|${lower(try(trimspace(role.role_definition_id), ""))}")
        }
      ]
      # Candidate IDs normalise once per assignment instead of once per required role.
      candidate_roles = [
        for candidate in try(tolist(assignment.resolved.list_fields.role_definition_ids) == null ? [] : tolist(assignment.resolved.list_fields.role_definition_ids), []) :
        lower(try(trimspace(candidate), ""))
      ]
      governance         = try(assignment.resolved.governance, try(assignment.intent.governance, null))
      members            = try(assignment.resolved.members, null)
      replacement_intent = try(assignment.resolved.replacement_intent, null)
      rationale          = try(assignment.resolved.identity.rationale, null)
    }
  }

  identity_entries = {
    for key, assignment in local.assignment_entries :
    key => merge(assignment, {
      identity_name = substr("irb-${sha1("${key}|${assignment.identity_name_basis}|${assignment.identity_strategy}")}", 0, 24)
    })
    if assignment.identity_required && assignment.identity_strategy == "user_assigned"
  }

  role_grant_entries = merge([
    for key, assignment in local.assignment_entries : {
      # Grant scopes pass through try at the resolved boundary and never widen to the assignment scope.
      for role in assignment.required_role_entries :
      "${key}|${role.grant_key_digest}" => {
        assignment_key        = key
        assignment_scope      = assignment.assignment_scope
        effective_effect      = assignment.effective_effect
        grant_scope           = role.grant_scope
        role_definition_id    = role.role_definition_id
        purpose               = role.purpose
        grant_scope_valid     = can(regex(local.grant_scope_pattern, role.grant_scope))
        role_definition_valid = can(regex(local.role_definition_pattern, role.role_definition_id))
        # Broad roles are identified by terminal role GUID so subscription-prefixed IDs cannot bypass the exclusion.
        # b24988ac-6180-42a0-ab88-20f7382dd24c is the real Contributor terminal GUID, confirmed against Azure RBAC.
        broad_role_excluded  = !contains(["8e3af657-a8ff-443c-a75c-2fe8c4bcb635", "b24988ac-6180-42a0-ab88-20f7382dd24c"], lower(try(regex("[^/]+$", role.role_definition_id), "")))
        purpose_supplied     = role.purpose != ""
        role_declared        = contains(assignment.candidate_roles, lower(role.role_definition_id))
        role_assignment_name = format("%s-%s-%s-%s-%s", substr(role.name_digest, 0, 8), substr(role.name_digest, 8, 4), substr(role.name_digest, 12, 4), substr(role.name_digest, 16, 4), substr(role.name_digest, 20, 12))
      }
      if assignment.identity_required
    }
  ]...)

  outputs = {
    for key, assignment in local.assignment_entries :
    key => {
      assignment_key    = key
      assignment_scope  = assignment.assignment_scope
      effective_effect  = assignment.effective_effect
      identity_required = assignment.identity_required
      identity_strategy = assignment.identity_strategy
      identity_name     = try(local.identity_entries[key].identity_name, null)
      identity_id       = try(azurerm_user_assigned_identity.this[key].id, null)
      principal_id      = try(azurerm_user_assigned_identity.this[key].principal_id, null)
      assignment_binding = assignment.identity_required ? {
        assignment_key    = key
        id                = try(azurerm_user_assigned_identity.this[key].id, null)
        identity_id       = try(azurerm_user_assigned_identity.this[key].id, null)
        principal_id      = try(azurerm_user_assigned_identity.this[key].principal_id, null)
        identity_strategy = assignment.identity_strategy
      } : null
      role_grants = [
        for role in assignment.required_role_entries : {
          grant_scope        = role.grant_scope
          role_definition_id = role.role_definition_id
          purpose            = role.purpose
          role_assignment_id = try(azurerm_role_assignment.this["${key}|${role.grant_key_digest}"].id, null)
        }
      ]
      governance         = assignment.governance
      members            = assignment.members
      rationale          = assignment.rationale
      replacement_intent = assignment.replacement_intent
      replacement_impact = {
        identity_name_changes_force_replacement     = true
        identity_strategy_changes_force_replacement = true
        grant_scope_changes_change_grant            = true
        role_definition_changes_change_grant        = true
        purpose_changes_do_not_change_grant_address = true
        review_required_for                         = ["identity.name_basis", "identity.strategy", "identity.location", "identity.resource_group_name", "required_roles.role_definition_id", "required_roles.grant_scope"]
        identity_name                               = try(local.identity_entries[key].identity_name, null)
        grant_addresses = [
          for role in assignment.required_role_entries : "${key}|${role.grant_key_digest}"
        ]
      }
    }
  }
}
