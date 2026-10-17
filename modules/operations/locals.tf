locals {
  # Grammar constants. Variable validations read these, so they must stay
  # independent of every variable. The scope pattern map is the only definition
  # of Azure scope grammar in this module.
  scope_types = ["management_group", "subscription", "resource_group", "resource"]

  scope_patterns = {
    management_group = "^/providers/Microsoft\\.Management/managementGroups/[^/]+$"
    subscription     = "^/subscriptions/[0-9a-fA-F-]{36}$"
    resource_group   = "^/subscriptions/[0-9a-fA-F-]{36}/resourceGroups/[^/]+$"
    resource         = "^/subscriptions/[0-9a-fA-F-]{36}/resourceGroups/[^/]+/providers/[^/]+/.+$"
  }

  # Any single scope, built from the map above so that the role scope and policy
  # assignment ID patterns cannot drift from the typed scope patterns.
  any_scope_pattern            = "(${join("|", [for type in local.scope_types : trimsuffix(trimprefix(local.scope_patterns[type], "^"), "$")])})"
  role_scope_pattern           = "^${local.any_scope_pattern}$"
  policy_assignment_id_pattern = "^${local.any_scope_pattern}/providers/Microsoft\\.Authorization/policyAssignments/[^/]+$"

  # One view of the resolved assignment records for both operation families. A
  # blank value means the producer did not supply it; consumers treat blank as
  # unknown and never as a match.
  resolved_assignment_entries = {
    for key, assignment in var.resolved_assignments :
    key => {
      assignment_key       = key
      assignment_id        = try(trimspace(assignment.assignment.id), "")
      scope_type           = try(lower(trimspace(assignment.intent.scope.type)), "")
      scope_id             = try(trimspace(assignment.intent.scope.id), "")
      policy_definition_id = try(trimspace(assignment.resolved.policy_definition_id), "")
      members              = try(assignment.resolved.members, null)
      effective_effect     = try(assignment.resolved.effective_effect, null)
      member_reference_ids = try(assignment.resolved.member_reference_ids, null)
      # A blank eligibility value is an absent producer decision, never an eligibility state.
      remediation_eligibility = try(trimspace(assignment.resolved.remediation_eligibility), "") != "" ? trimspace(assignment.resolved.remediation_eligibility) : null
      remediation_reason      = try(trimspace(assignment.resolved.remediation_reason), "")
      required_roles          = try(assignment.resolved.required_roles, null)
    }
  }

  # policy_assignment_id here is the caller's value, or null when omitted.
  # request_views takes an omitted value from the resolved assignment.
  request_entries = {
    for key, request in var.requests :
    key => {
      mode                           = lower(trimspace(request.mode))
      assignment_key                 = trimspace(request.assignment_key)
      member_reference_id            = try(trimspace(request.member_reference_id), "") != "" ? trimspace(request.member_reference_id) : null
      scope_type                     = lower(trimspace(request.scope_type))
      scope_id                       = trimspace(request.scope_id)
      policy_assignment_id           = try(trimspace(request.policy_assignment_id), "") != "" ? trimspace(request.policy_assignment_id) : null
      policy_definition_reference_id = try(trimspace(request.policy_definition_reference_id), "") != "" ? trimspace(request.policy_definition_reference_id) : null
      resource_discovery_mode        = try(trimspace(request.resource_discovery_mode), "") != "" ? trimspace(request.resource_discovery_mode) : null
      location_filters               = try(request.location_filters == null ? null : [for location in tolist(request.location_filters) : trimspace(location)], null)
      resource_count                 = try(request.resource_count, null)
      parallel_deployments           = try(request.parallel_deployments, null)
      failure_percentage             = try(request.failure_percentage, null)
      role_scope                     = try(trimspace(request.role_scope), "") != "" ? trimspace(request.role_scope) : null
      approval_reference             = try(trimspace(request.approval_reference), "") != "" ? trimspace(request.approval_reference) : null
      evidence_status                = try(trimspace(request.evidence_status), "") != "" ? trimspace(request.evidence_status) : null
      expected_evidence_status       = try(trimspace(request.expected_evidence_status), "") != "" ? trimspace(request.expected_evidence_status) : null
      discovery_targets              = try([for target in var.discovery_evidence[key].targets : { resource_id = trimspace(target.resource_id), location = trimspace(target.location) }], null)
    }
  }

  assignment_entries_by_id = {
    for entry in values(local.resolved_assignment_entries) : entry.assignment_id => entry
    if entry.assignment_id != ""
  }

  assignment_members_by_reference_id = {
    for key, assignment in local.resolved_assignment_entries :
    key => assignment.members == null ? null : {
      for member in assignment.members : member.reference_id => member
    }
  }

  # A member list is verified only when both representations are present. The
  # resolved_assignments variable proves they agree, so no consumer repeats that
  # check.
  assignment_member_inventory_known = {
    for key, assignment in local.resolved_assignment_entries :
    key => assignment.member_reference_ids != null && assignment.members != null
  }

  # One resolved context per request: the referenced assignment, the selected
  # member when the request names one, and the producer decisions that apply
  # to whichever of the two is the remediation target.
  request_context = {
    for key, request in local.request_entries : key => {
      assignment = try(local.resolved_assignment_entries[request.assignment_key], null)
      member     = request.member_reference_id == null ? null : try(local.assignment_members_by_reference_id[request.assignment_key][request.member_reference_id], null)
    }
  }

  request_decisions = {
    for key, context in local.request_context : key => {
      known                   = context.assignment != null
      remediation_eligibility = local.request_entries[key].member_reference_id == null ? try(context.assignment.remediation_eligibility, null) : try(context.member.remediation_eligibility, null)
      remediation_reason      = local.request_entries[key].member_reference_id == null ? try(context.assignment.remediation_reason, "") : try(context.member.remediation_reason, "")
      required_roles          = local.request_entries[key].member_reference_id == null ? try(context.assignment.required_roles, null) : try(context.member.required_roles, null)
      policy_definition_id    = local.request_entries[key].member_reference_id == null ? try(context.assignment.policy_definition_id, "") : try(trimspace(context.member.policy_definition_id), "")
      member_inventory_known  = try(local.assignment_member_inventory_known[local.request_entries[key].assignment_key], false)
    }
  }

  filtered_discovery_targets = {
    for key, request in local.request_entries :
    key => request.discovery_targets == null ? null : [
      for target in request.discovery_targets : target
      if request.mode == "discovery" && (request.location_filters == null || contains(request.location_filters, target.location))
    ]
  }

  # Remediation and exemption requests are checked against the resolved
  # assignment scope by one rule. Keys are prefixed with the request family.
  scoped_operations = merge(
    {
      for key, request in local.request_entries : "remediation/${key}" => {
        scope_type = request.scope_type
        scope_id   = request.scope_id
        assignment = try(local.resolved_assignment_entries[request.assignment_key], null)
      }
    },
    {
      for key, exemption in local.exemption_entries : "exemption/${key}" => {
        scope_type = exemption.scope_type
        scope_id   = exemption.scope_id
        assignment = local.assignment_matches[key]
      }
    }
  )

  # An operation scope matches the resolved assignment scope exactly or sits
  # inside it: resource-group and resource scopes inside a subscription, and
  # resource scopes inside a resource group. A management-group assignment scope
  # has no comparable lineage and still requires an exact match. The trailing
  # separators stop one name from matching as the prefix of another. A request
  # whose scope is absent or unreadable is not contained.
  scope_contained = {
    for id, operation in local.scoped_operations :
    id => try(
      operation.assignment != null && operation.assignment.scope_type != "" && operation.assignment.scope_id != "" && (
        (operation.assignment.scope_type == operation.scope_type && operation.assignment.scope_id == operation.scope_id) ||
        (operation.assignment.scope_type == "subscription" && contains(["resource_group", "resource"], operation.scope_type) && startswith(operation.scope_id, "${operation.assignment.scope_id}/resourceGroups/")) ||
        (operation.assignment.scope_type == "resource_group" && operation.scope_type == "resource" && startswith(operation.scope_id, "${operation.assignment.scope_id}/providers/"))
      ),
      false
    )
  }

  # Every contract rule per request, keyed by the blocked-reason name it
  # produces when false. Rule order in blocked_reason_order is the diagnostic
  # order. Eligibility is handled separately because it carries the producer's
  # reason text.
  blocked_reason_order = [
    "scope_id_malformed", "policy_assignment_id_malformed", "role_scope_malformed",
    "assignment_context_unknown", "assignment_id_unknown", "assignment_id_mismatch", "resolved_scope_unknown",
    "member_inventory_unknown", "member_reference_required", "member_reference_id_mismatch",
    "policy_definition_reference_required", "policy_definition_reference_id_mismatch",
    "operation_scope_mismatch", "resolved_policy_definition_id_blank",
  ]

  post_eligibility_reason_order = [
    "approval_reference_required", "role_scope_required", "role_scope_not_authorised", "resource_count_required",
    "discovery_evidence_unknown", "discovery_limit_exceeded", "evidence_status_mismatch",
    "resource_discovery_mode_unsupported_for_management_group",
  ]

  request_checks = {
    for key, request in local.request_entries : key => {
      scope_id_malformed             = contains(keys(local.scope_patterns), request.scope_type) && can(regex(local.scope_patterns[request.scope_type], request.scope_id))
      policy_assignment_id_malformed = request.policy_assignment_id == null || can(regex(local.policy_assignment_id_pattern, request.policy_assignment_id))
      role_scope_malformed           = request.role_scope == null || can(regex(local.role_scope_pattern, request.role_scope))
      assignment_context_unknown     = local.request_decisions[key].known
      assignment_id_unknown          = local.request_decisions[key].known && local.request_context[key].assignment.assignment_id != ""
      assignment_id_mismatch         = local.request_decisions[key].known && (request.policy_assignment_id == null || local.request_context[key].assignment.assignment_id == request.policy_assignment_id)
      resolved_scope_unknown         = local.request_decisions[key].known && local.request_context[key].assignment.scope_type != "" && local.request_context[key].assignment.scope_id != ""
      member_inventory_unknown       = local.request_decisions[key].member_inventory_known
      member_reference_required      = !local.request_decisions[key].member_inventory_known ? true : length(local.request_context[key].assignment.member_reference_ids) == 0 || request.member_reference_id != null
      member_reference_id_mismatch   = request.member_reference_id == null ? true : local.request_decisions[key].member_inventory_known && local.request_context[key].member != null
      # Member requests must name the same member as policy_definition_reference_id.
      policy_definition_reference_required    = request.member_reference_id == null || request.policy_definition_reference_id != null
      policy_definition_reference_id_mismatch = request.member_reference_id == null ? request.policy_definition_reference_id == null : request.policy_definition_reference_id == request.member_reference_id && (local.request_decisions[key].member_inventory_known && local.request_context[key].member != null)
      operation_scope_mismatch                = local.scope_contained["remediation/${key}"]
      # Execution evidence must include the resolved target definition ID; a
      # blank value means the producer could not resolve the definition or set.
      resolved_policy_definition_id_blank = local.request_decisions[key].known && local.request_decisions[key].policy_definition_id != ""
      approval_reference_required         = request.mode == "disabled" || request.approval_reference != null
      role_scope_required                 = request.mode == "disabled" || request.role_scope != null
      role_scope_not_authorised = request.mode == "disabled" || request.role_scope == null || (local.request_decisions[key].known && try(anytrue([
        for role in local.request_decisions[key].required_roles : try(role.grant_scope == request.role_scope, false)
      ]), false))
      resource_count_required                                  = request.mode == "disabled" || request.resource_count != null
      discovery_evidence_unknown                               = request.mode != "discovery" || request.discovery_targets != null
      discovery_limit_exceeded                                 = request.discovery_targets == null || request.resource_count == null || length(local.filtered_discovery_targets[key]) <= request.resource_count
      evidence_status_mismatch                                 = request.expected_evidence_status == null || request.evidence_status == request.expected_evidence_status
      resource_discovery_mode_unsupported_for_management_group = request.scope_type != "management_group" || request.resource_discovery_mode == null
    }
  }

  # Eligibility failures name the producer decision and, when supplied, the
  # producer's remediation reason for the offending remediation key.
  request_eligibility_blocked_reasons = {
    for key, decision in local.request_decisions :
    key => decision.known && decision.remediation_eligibility == "eligible" ? [] : concat(
      !decision.known || decision.remediation_eligibility == null ? ["eligibility_unknown"] : ["not_eligible"],
      decision.known && decision.remediation_reason != "" ? ["remediation_reason: ${decision.remediation_reason}"] : []
    )
  }

  request_blocked_reasons = {
    for key, checks in local.request_checks :
    key => concat(
      [for reason in local.blocked_reason_order : reason if !checks[reason]],
      local.request_eligibility_blocked_reasons[key],
      [for reason in local.post_eligibility_reason_order : reason if !checks[reason]]
    )
  }

  request_status = {
    for key, request in local.request_entries :
    key => request.mode == "disabled" ? "skipped" : length(local.request_blocked_reasons[key]) > 0 ? "blocked" : request.mode == "discovery" ? "discovery" : "created"
  }

  blocked_request_keys = [
    for key, request in local.request_entries : key
    if request.mode != "disabled" && local.request_status[key] == "blocked"
  ]

  blocked_request_diagnostics = [
    for key in local.blocked_request_keys : "${key}: ${join(", ", local.request_blocked_reasons[key])}"
  ]

  # One output view per request: the normalised request plus status, blocked
  # reasons and the producer decisions. Every public output reads this view.
  request_views = {
    for key, request in local.request_entries :
    key => merge(request, {
      request_key                 = key
      status                      = local.request_status[key]
      blocked_reasons             = local.request_blocked_reasons[key]
      effective_effect            = try(local.request_context[key].assignment.effective_effect, null)
      remediation_eligibility     = local.request_decisions[key].remediation_eligibility
      remediation_reason          = local.request_decisions[key].remediation_reason
      policy_definition_id        = local.request_decisions[key].policy_definition_id
      required_roles              = local.request_decisions[key].required_roles
      member_reference_ids        = try(local.request_context[key].assignment.member_reference_ids, null)
      member_policy_definition_id = try(local.request_context[key].member.policy_definition_id, null)
      # An omitted policy_assignment_id takes the ID of the assignment the request
      # names. While that assignment has no ID the value stays null, and the
      # assignment_id_unknown rule blocks an execute or discovery request.
      policy_assignment_id = request.policy_assignment_id != null ? request.policy_assignment_id : (
        try(local.request_context[key].assignment.assignment_id, "") != "" ? local.request_context[key].assignment.assignment_id : null
      )
    })
  }

  # Execute requests partitioned by scope type. Operation keys and scope
  # families come from caller intent and are known before apply; resolved IDs
  # and eligibility may stay unknown until then, and the contract guard
  # rejects known-invalid execute requests.
  remediation_by_scope = {
    for scope_type in local.scope_types : scope_type => {
      for key, request in local.request_views : key => request
      if request.mode == "execute" && request.scope_type == scope_type
    }
  }

  created_operations = merge([
    for scope_type, resources in {
      management_group = azurerm_management_group_policy_remediation.this
      subscription     = azurerm_subscription_policy_remediation.this
      resource_group   = azurerm_resource_group_policy_remediation.this
      resource         = azurerm_resource_policy_remediation.this
    } : { for key, resource in resources : key => merge(local.request_views[key], { id = resource.id }) }
  ]...)
}
