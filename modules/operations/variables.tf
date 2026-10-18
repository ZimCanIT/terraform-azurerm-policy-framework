variable "resolved_assignments" {
  description = "Canonical resolved assignment records keyed by stable assignment key, read by both remediation and exemption requests."
  type        = any
  default     = {}

  validation {
    condition     = can(keys(var.resolved_assignments)) && !can(tolist(var.resolved_assignments))
    error_message = "resolved_assignments must be a keyed object or map of resolved assignment records."
  }

  validation {
    condition = try(alltrue([
      for key, assignment in var.resolved_assignments :
      trimspace(key) != "" && can(keys(assignment))
    ]), false)
    error_message = "Each resolved assignment must use a non-blank assignment key and an object value. Offending assignment keys: ${try(join(", ", sort([for key, assignment in var.resolved_assignments : key if !try(trimspace(key) != "" && can(keys(assignment)), false)])), "<invalid input container>")}."
  }

  # A record without a created assignment carries a null or absent binding. Any
  # other non-object binding reads as no ID, so it is rejected here.
  validation {
    condition = try(alltrue([
      for key, assignment in var.resolved_assignments :
      try(assignment.assignment == null, true) || can(keys(assignment.assignment))
    ]), false)
    error_message = "Each resolved assignment binding must be absent, null or an object. Offending assignment keys: ${try(join(", ", sort([for key, assignment in var.resolved_assignments : key if !try(try(assignment.assignment == null, true) || can(keys(assignment.assignment)), false)])), "<invalid input container>")}."
  }

  # The binding ID is null, unknown until apply, or a strict policy assignment
  # ID. The inner try keeps an absent ID from failing the whole condition, and
  # an unknown ID yields an unknown result, so the check is deferred, not failed.
  validation {
    condition = try(alltrue([
      for key, assignment in var.resolved_assignments :
      try(assignment.assignment.id == null, true) || try(
        can(regex("^\"[^\"]*\"$", jsonencode(assignment.assignment.id))) &&
        jsonencode(assignment.assignment.id) == format("\"%s\"", assignment.assignment.id) &&
        can(regex(local.policy_assignment_id_pattern, assignment.assignment.id)),
        false
      )
    ]), false)
    error_message = "Each resolved assignment ID must be null, unknown until apply, or a strict management-group, subscription, resource-group or resource policy assignment ID. Offending assignment keys: ${try(join(", ", sort([for key, assignment in var.resolved_assignments : key if !try(try(assignment.assignment.id == null, true) || try(can(regex("^\"[^\"]*\"$", jsonencode(assignment.assignment.id))) && jsonencode(assignment.assignment.id) == format("\"%s\"", assignment.assignment.id) && can(regex(local.policy_assignment_id_pattern, assignment.assignment.id)), false), false)])), "<invalid input container>")}."
  }

  validation {
    condition = try(alltrue([
      for key, assignment in var.resolved_assignments :
      try(assignment.resolved.member_reference_ids == null, true) || try(length(assignment.resolved.member_reference_ids) == 0, false) || (
        can(tolist(assignment.resolved.member_reference_ids)) &&
        alltrue([
          for reference_id in tolist(assignment.resolved.member_reference_ids) :
          can(regex("^\"[^\"]*\"$", jsonencode(reference_id))) &&
          jsonencode(reference_id) == format("\"%s\"", reference_id) &&
          can(regex("^\\S(.*\\S)?$", reference_id))
        ]) &&
        length(tolist(assignment.resolved.member_reference_ids)) == length(toset(tolist(assignment.resolved.member_reference_ids)))
      )
    ]), false)
    error_message = "Each resolved member_reference_ids value must be null or a unique list of strict, non-blank strings. Offending assignment keys: ${try(join(", ", sort([for key, assignment in var.resolved_assignments : key if !try(try(assignment.resolved.member_reference_ids == null, true) || try(length(assignment.resolved.member_reference_ids) == 0, false) || (can(tolist(assignment.resolved.member_reference_ids)) && alltrue([for reference_id in tolist(assignment.resolved.member_reference_ids) : can(regex("^\"[^\"]*\"$", jsonencode(reference_id))) && jsonencode(reference_id) == format("\"%s\"", reference_id) && can(regex("^\\S(.*\\S)?$", reference_id))]) && length(tolist(assignment.resolved.member_reference_ids)) == length(toset(tolist(assignment.resolved.member_reference_ids)))), false)])), "<invalid input container>")}."
  }

  validation {
    condition = try(alltrue([
      for key, assignment in var.resolved_assignments :
      try(assignment.resolved.members == null, true) || (
        try(length(assignment.resolved.members) == 0, false) ? try(assignment.resolved.member_reference_ids == null || length(assignment.resolved.member_reference_ids) == 0, false) : (
          can(tolist(assignment.resolved.members)) &&
          alltrue([
            for member in tolist(assignment.resolved.members) :
            can(keys(member)) &&
            can(regex("^\"[^\"]*\"$", jsonencode(member.reference_id))) &&
            jsonencode(member.reference_id) == format("\"%s\"", member.reference_id) &&
            can(regex("^\\S(.*\\S)?$", member.reference_id))
          ]) &&
          length([for member in tolist(assignment.resolved.members) : member.reference_id]) == length(toset([for member in tolist(assignment.resolved.members) : member.reference_id])) &&
          (try(assignment.resolved.member_reference_ids == null, true) || tolist([for member in tolist(assignment.resolved.members) : member.reference_id]) == tolist(assignment.resolved.member_reference_ids))
        )
      )
    ]), false)
    error_message = "Each resolved members value must be an ordered list of uniquely identified records matching member_reference_ids when both are known. Offending assignment keys: ${try(join(", ", sort([for key, assignment in var.resolved_assignments : key if !try(try(assignment.resolved.members == null, true) || (try(length(assignment.resolved.members) == 0, false) ? try(assignment.resolved.member_reference_ids == null || length(assignment.resolved.member_reference_ids) == 0, false) : (can(tolist(assignment.resolved.members)) && alltrue([for member in tolist(assignment.resolved.members) : can(keys(member)) && can(regex("^\"[^\"]*\"$", jsonencode(member.reference_id))) && jsonencode(member.reference_id) == format("\"%s\"", member.reference_id) && can(regex("^\\S(.*\\S)?$", member.reference_id))]) && length([for member in tolist(assignment.resolved.members) : member.reference_id]) == length(toset([for member in tolist(assignment.resolved.members) : member.reference_id])) && (try(assignment.resolved.member_reference_ids == null, true) || tolist([for member in tolist(assignment.resolved.members) : member.reference_id]) == tolist(assignment.resolved.member_reference_ids)))), false)])), "<invalid input container>")}."
  }

  # The producer emits null or one of three tokens. Null is the only absent
  # decision, so a blank or unlisted token is rejected rather than read as unknown.
  validation {
    condition = try(alltrue([
      for key, assignment in var.resolved_assignments :
      try(assignment.resolved.remediation_eligibility == null, true) || try(
        can(regex("^\"[^\"]*\"$", jsonencode(assignment.resolved.remediation_eligibility))) &&
        jsonencode(assignment.resolved.remediation_eligibility) == format("\"%s\"", assignment.resolved.remediation_eligibility) &&
        contains(["eligible", "not_eligible", "blocked"], assignment.resolved.remediation_eligibility),
        false
      )
    ]), false)
    error_message = "Each resolved remediation_eligibility must be null, unknown until apply, or one of eligible, not_eligible or blocked. Offending assignment keys: ${try(join(", ", sort([for key, assignment in var.resolved_assignments : key if !try(try(assignment.resolved.remediation_eligibility == null, true) || try(can(regex("^\"[^\"]*\"$", jsonencode(assignment.resolved.remediation_eligibility))) && jsonencode(assignment.resolved.remediation_eligibility) == format("\"%s\"", assignment.resolved.remediation_eligibility) && contains(["eligible", "not_eligible", "blocked"], assignment.resolved.remediation_eligibility), false), false)])), "<invalid input container>")}."
  }

  # Exemption requests find their assignment by ID, so two keys must not share
  # one. Null or absent IDs are left to the checks that consume them, and an ID
  # that is unknown until apply makes the condition unknown, which defers it. A
  # non-object assignment or a non-string ID is rejected by its own binding rule;
  # the inner try skips an unreadable ID, and the default applies only to a container
  # that cannot be iterated, which the container rule rejects.
  validation {
    condition = try(
      length(distinct([for _, assignment in var.resolved_assignments : trimspace(assignment.assignment.id) if try(trimspace(assignment.assignment.id), "") != ""])) ==
      length([for _, assignment in var.resolved_assignments : trimspace(assignment.assignment.id) if try(trimspace(assignment.assignment.id), "") != ""]),
      true
    )
    error_message = "Each resolved assignment ID must be unique across assignment keys."
  }
}

variable "discovery_evidence" {
  description = "Caller-supplied, non-authoritative discovery results keyed by remediation request key."
  type        = any
  default     = {}

  validation {
    condition     = can(keys(var.discovery_evidence)) && !can(tolist(var.discovery_evidence))
    error_message = "discovery_evidence must be a keyed object or map."
  }

  validation {
    condition = try(alltrue([
      for key, evidence in var.discovery_evidence :
      trimspace(key) != "" && can(keys(evidence)) && contains(keys(evidence), "targets") && can(tolist(evidence.targets)) && alltrue([
        for target in tolist(evidence.targets) :
        can(keys(target)) &&
        can(regex("^\"[^\"]*\"$", jsonencode(target.resource_id))) &&
        jsonencode(target.resource_id) == format("\"%s\"", target.resource_id) &&
        can(regex(local.scope_patterns.resource, trimspace(target.resource_id))) &&
        can(regex("^\"[^\"]*\"$", jsonencode(target.location))) &&
        jsonencode(target.location) == format("\"%s\"", target.location) &&
        can(regex("^\\S(.*\\S)?$", target.location))

      ])
    ]), false)
    error_message = "Each discovery evidence entry requires a targets list of objects with non-blank resource_id and location strings. Offending evidence keys: ${try(join(", ", sort([for key, evidence in var.discovery_evidence : key if !try(trimspace(key) != "" && can(keys(evidence)) && contains(keys(evidence), "targets") && can(tolist(evidence.targets)) && alltrue([for target in tolist(evidence.targets) : can(keys(target)) && can(regex("^\"[^\"]*\"$", jsonencode(target.resource_id))) && jsonencode(target.resource_id) == format("\"%s\"", target.resource_id) && can(regex(local.scope_patterns.resource, trimspace(target.resource_id))) && can(regex("^\"[^\"]*\"$", jsonencode(target.location))) && jsonencode(target.location) == format("\"%s\"", target.location) && can(regex("^\\S(.*\\S)?$", target.location))]), false)])), "<invalid input container>")}."
  }
}

variable "requests" {
  description = "Explicit remediation requests keyed by stable operation key."
  type        = any
  default     = {}

  validation {
    condition     = can(keys(var.requests)) && !can(tolist(var.requests))
    error_message = "requests must be a keyed object or map of remediation request objects."
  }

  validation {
    condition = try(alltrue([
      for key, request in var.requests :
      trimspace(key) != "" && can(keys(request))
    ]), false)
    error_message = "Each remediation request must be an object with a non-blank request key. Offending request keys: ${try(join(", ", sort([for key, request in var.requests : key if !try(trimspace(key) != "" && can(keys(request)), false)])), "<invalid input container>")}."
  }

  validation {
    condition = try(alltrue([
      for key, request in var.requests :
      length(setsubtract(toset(keys(request)), toset([
        "mode", "assignment_key", "member_reference_id", "scope_type", "scope_id", "policy_assignment_id",
        "policy_definition_reference_id", "resource_discovery_mode", "location_filters", "resource_count",
        "parallel_deployments", "failure_percentage", "role_scope", "approval_reference", "evidence_status", "expected_evidence_status"
      ]))) == 0
    ]), false)
    error_message = "Requests may contain only fields from the canonical remediations contract. Offending request keys: ${try(join(", ", sort([for key, request in var.requests : key if !try(length(setsubtract(toset(keys(request)), toset(["mode", "assignment_key", "member_reference_id", "scope_type", "scope_id", "policy_assignment_id", "policy_definition_reference_id", "resource_discovery_mode", "location_filters", "resource_count", "parallel_deployments", "failure_percentage", "role_scope", "approval_reference", "evidence_status", "expected_evidence_status"]))) == 0, false)])), "<invalid input container>")}."
  }

  validation {
    condition = try(alltrue([
      for key, request in var.requests :
      can(regex("^\"[^\"]*\"$", jsonencode(request.mode))) &&
      jsonencode(request.mode) == format("\"%s\"", request.mode) &&
      contains(["discovery", "execute", "disabled"], lower(trimspace(request.mode)))
    ]), false)
    error_message = "Each remediation request mode must be discovery, execute or disabled. Offending request keys: ${try(join(", ", sort([for key, request in var.requests : key if !try(can(regex("^\"[^\"]*\"$", jsonencode(request.mode))) && jsonencode(request.mode) == format("\"%s\"", request.mode) && contains(["discovery", "execute", "disabled"], lower(trimspace(request.mode))), false)])), "<invalid input container>")}."
  }

  validation {
    condition = try(alltrue([
      for key, request in var.requests :
      can(regex("^\"[^\"]*\"$", jsonencode(request.scope_type))) &&
      jsonencode(request.scope_type) == format("\"%s\"", request.scope_type) &&
      contains(local.scope_types, lower(trimspace(request.scope_type)))
    ]), false)
    error_message = "Each remediation request scope_type must be a supported Azure scope type. Offending request keys: ${try(join(", ", sort([for key, request in var.requests : key if !try(can(regex("^\"[^\"]*\"$", jsonencode(request.scope_type))) && jsonencode(request.scope_type) == format("\"%s\"", request.scope_type) && contains(local.scope_types, lower(trimspace(request.scope_type))), false)])), "<invalid input container>")}."
  }

  validation {
    condition = try(alltrue([
      for key, request in var.requests :
      can(regex("^\"[^\"]*\"$", jsonencode(request.assignment_key))) && jsonencode(request.assignment_key) == format("\"%s\"", request.assignment_key) && can(regex("^\\S(.*\\S)?$", request.assignment_key)) &&
      can(regex("^\"[^\"]*\"$", jsonencode(request.scope_id))) && jsonencode(request.scope_id) == format("\"%s\"", request.scope_id) && can(regex("^\\S(.*\\S)?$", request.scope_id))
    ]), false)
    error_message = "Each remediation request requires strict, non-blank assignment_key and scope_id strings. Offending request keys: ${try(join(", ", sort([for key, request in var.requests : key if !try(can(regex("^\"[^\"]*\"$", jsonencode(request.assignment_key))) && jsonencode(request.assignment_key) == format("\"%s\"", request.assignment_key) && can(regex("^\\S(.*\\S)?$", request.assignment_key)) && can(regex("^\"[^\"]*\"$", jsonencode(request.scope_id))) && jsonencode(request.scope_id) == format("\"%s\"", request.scope_id) && can(regex("^\\S(.*\\S)?$", request.scope_id)), false)])), "<invalid input container>")}."
  }

  validation {
    condition = try(alltrue([
      for key, request in var.requests :
      try(request.policy_assignment_id == null, true) || (can(regex("^\"[^\"]*\"$", jsonencode(request.policy_assignment_id))) && jsonencode(request.policy_assignment_id) == format("\"%s\"", request.policy_assignment_id) && can(regex("^\\S(.*\\S)?$", request.policy_assignment_id)))
    ]), false)
    error_message = "policy_assignment_id must be null or a strict, non-blank string when supplied. Offending request keys: ${try(join(", ", sort([for key, request in var.requests : key if !try(try(request.policy_assignment_id == null, true) || (can(regex("^\"[^\"]*\"$", jsonencode(request.policy_assignment_id))) && jsonencode(request.policy_assignment_id) == format("\"%s\"", request.policy_assignment_id) && can(regex("^\\S(.*\\S)?$", request.policy_assignment_id))), false)])), "<invalid input container>")}."
  }

  validation {
    condition = try(alltrue([
      for key, request in var.requests :
      try(request.policy_assignment_id == null, true) || can(regex(local.policy_assignment_id_pattern, trimspace(request.policy_assignment_id)))
    ]), false)
    error_message = "A supplied policy_assignment_id must be a valid management-group, subscription, resource-group or resource policy assignment ID. Offending request keys: ${try(join(", ", sort([for key, request in var.requests : key if !try(try(request.policy_assignment_id == null, true) || can(regex(local.policy_assignment_id_pattern, trimspace(request.policy_assignment_id))), false)])), "<invalid input container>")}."
  }

  validation {
    condition = try(alltrue([
      for key, request in var.requests :
      try(request.member_reference_id == null, true) || (can(regex("^\"[^\"]*\"$", jsonencode(request.member_reference_id))) && jsonencode(request.member_reference_id) == format("\"%s\"", request.member_reference_id) && can(regex("^\\S(.*\\S)?$", request.member_reference_id)))
    ]), false)
    error_message = "member_reference_id must be null or a strict, non-blank string when supplied. Offending request keys: ${try(join(", ", sort([for key, request in var.requests : key if !try(try(request.member_reference_id == null, true) || (can(regex("^\"[^\"]*\"$", jsonencode(request.member_reference_id))) && jsonencode(request.member_reference_id) == format("\"%s\"", request.member_reference_id) && can(regex("^\\S(.*\\S)?$", request.member_reference_id))), false)])), "<invalid input container>")}."
  }

  validation {
    condition = try(alltrue([
      for key, request in var.requests :
      try(request.policy_definition_reference_id == null, true) || (can(regex("^\"[^\"]*\"$", jsonencode(request.policy_definition_reference_id))) && jsonencode(request.policy_definition_reference_id) == format("\"%s\"", request.policy_definition_reference_id) && can(regex("^\\S(.*\\S)?$", request.policy_definition_reference_id)))
    ]), false)
    error_message = "policy_definition_reference_id must be null or a strict, non-blank string when supplied. Offending request keys: ${try(join(", ", sort([for key, request in var.requests : key if !try(try(request.policy_definition_reference_id == null, true) || (can(regex("^\"[^\"]*\"$", jsonencode(request.policy_definition_reference_id))) && jsonencode(request.policy_definition_reference_id) == format("\"%s\"", request.policy_definition_reference_id) && can(regex("^\\S(.*\\S)?$", request.policy_definition_reference_id))), false)])), "<invalid input container>")}."
  }

  validation {
    condition = try(alltrue([
      for key, request in var.requests :
      try(request.role_scope == null, true) || (can(regex("^\"[^\"]*\"$", jsonencode(request.role_scope))) && jsonencode(request.role_scope) == format("\"%s\"", request.role_scope) && can(regex("^\\S(.*\\S)?$", request.role_scope)))
    ]), false)
    error_message = "role_scope must be null or a strict, non-blank string when supplied. Offending request keys: ${try(join(", ", sort([for key, request in var.requests : key if !try(try(request.role_scope == null, true) || (can(regex("^\"[^\"]*\"$", jsonencode(request.role_scope))) && jsonencode(request.role_scope) == format("\"%s\"", request.role_scope) && can(regex("^\\S(.*\\S)?$", request.role_scope))), false)])), "<invalid input container>")}."
  }

  validation {
    condition = try(alltrue([
      for key, request in var.requests :
      try(request.approval_reference == null, true) || (can(regex("^\"[^\"]*\"$", jsonencode(request.approval_reference))) && jsonencode(request.approval_reference) == format("\"%s\"", request.approval_reference) && can(regex("^\\S(.*\\S)?$", request.approval_reference)))
    ]), false)
    error_message = "approval_reference must be null or a strict, non-blank string when supplied. Offending request keys: ${try(join(", ", sort([for key, request in var.requests : key if !try(try(request.approval_reference == null, true) || (can(regex("^\"[^\"]*\"$", jsonencode(request.approval_reference))) && jsonencode(request.approval_reference) == format("\"%s\"", request.approval_reference) && can(regex("^\\S(.*\\S)?$", request.approval_reference))), false)])), "<invalid input container>")}."
  }

  validation {
    condition = try(alltrue([
      for key, request in var.requests :
      try(request.evidence_status == null, true) || (can(regex("^\"[^\"]*\"$", jsonencode(request.evidence_status))) && jsonencode(request.evidence_status) == format("\"%s\"", request.evidence_status) && can(regex("^\\S(.*\\S)?$", request.evidence_status)))
    ]), false)
    error_message = "evidence_status must be null or a strict, non-blank string when supplied. Offending request keys: ${try(join(", ", sort([for key, request in var.requests : key if !try(try(request.evidence_status == null, true) || (can(regex("^\"[^\"]*\"$", jsonencode(request.evidence_status))) && jsonencode(request.evidence_status) == format("\"%s\"", request.evidence_status) && can(regex("^\\S(.*\\S)?$", request.evidence_status))), false)])), "<invalid input container>")}."
  }

  validation {
    condition = try(alltrue([
      for key, request in var.requests :
      try(request.expected_evidence_status == null, true) || (can(regex("^\"[^\"]*\"$", jsonencode(request.expected_evidence_status))) && jsonencode(request.expected_evidence_status) == format("\"%s\"", request.expected_evidence_status) && can(regex("^\\S(.*\\S)?$", request.expected_evidence_status)))
    ]), false)
    error_message = "expected_evidence_status must be null or a strict, non-blank string when supplied. Offending request keys: ${try(join(", ", sort([for key, request in var.requests : key if !try(try(request.expected_evidence_status == null, true) || (can(regex("^\"[^\"]*\"$", jsonencode(request.expected_evidence_status))) && jsonencode(request.expected_evidence_status) == format("\"%s\"", request.expected_evidence_status) && can(regex("^\\S(.*\\S)?$", request.expected_evidence_status))), false)])), "<invalid input container>")}."
  }

  validation {
    condition = try(alltrue([
      for key, request in var.requests :
      try(request.resource_discovery_mode == null, true) || (
        can(regex("^\"[^\"]*\"$", jsonencode(request.resource_discovery_mode))) &&
        jsonencode(request.resource_discovery_mode) == format("\"%s\"", request.resource_discovery_mode) &&
        contains(["ExistingNonCompliant", "ReEvaluateCompliance"], request.resource_discovery_mode)
      )
    ]), false)
    error_message = "resource_discovery_mode must be null or one of ExistingNonCompliant or ReEvaluateCompliance. Offending request keys: ${try(join(", ", sort([for key, request in var.requests : key if !try(try(request.resource_discovery_mode == null, true) || (can(regex("^\"[^\"]*\"$", jsonencode(request.resource_discovery_mode))) && jsonencode(request.resource_discovery_mode) == format("\"%s\"", request.resource_discovery_mode) && contains(["ExistingNonCompliant", "ReEvaluateCompliance"], request.resource_discovery_mode)), false)])), "<invalid input container>")}."
  }

  validation {
    condition = try(alltrue([
      for key, request in var.requests :
      try(request.location_filters == null, true) || (can(tolist(request.location_filters)) && alltrue([
        for location in tolist(request.location_filters) :
        can(regex("^\"[^\"]*\"$", jsonencode(location))) &&
        jsonencode(location) == format("\"%s\"", location) &&
        can(regex("^\\S(.*\\S)?$", location))
      ]))
    ]), false)
    error_message = "location_filters must be null or a list of non-blank location strings. Offending request keys: ${try(join(", ", sort([for key, request in var.requests : key if !try(try(request.location_filters == null, true) || (can(tolist(request.location_filters)) && alltrue([for location in tolist(request.location_filters) : can(regex("^\"[^\"]*\"$", jsonencode(location))) && jsonencode(location) == format("\"%s\"", location) && can(regex("^\\S(.*\\S)?$", location))])), false)])), "<invalid input container>")}."
  }

  validation {
    condition = try(alltrue([
      for key, request in var.requests :
      try(request.resource_count == null, true) || (
        can(regex("^[0-9]+$", jsonencode(request.resource_count))) &&
        try(request.resource_count >= 1 && request.resource_count <= 50000, false)
      )
    ]), false)
    error_message = "resource_count must be null or a numeric integer from 1 through 50000. Offending request keys: ${try(join(", ", sort([for key, request in var.requests : key if !try(try(request.resource_count == null, true) || (can(regex("^[0-9]+$", jsonencode(request.resource_count))) && try(request.resource_count >= 1 && request.resource_count <= 50000, false)), false)])), "<invalid input container>")}."
  }

  validation {
    condition = try(alltrue([
      for key, request in var.requests :
      try(request.parallel_deployments == null, true) || (
        can(regex("^[0-9]+$", jsonencode(request.parallel_deployments))) &&
        try(request.parallel_deployments >= 1 && request.parallel_deployments <= 30, false)
      )
    ]), false)
    error_message = "parallel_deployments must be null or a numeric integer from 1 through 30. Offending request keys: ${try(join(", ", sort([for key, request in var.requests : key if !try(try(request.parallel_deployments == null, true) || (can(regex("^[0-9]+$", jsonencode(request.parallel_deployments))) && try(request.parallel_deployments >= 1 && request.parallel_deployments <= 30, false)), false)])), "<invalid input container>")}."
  }

  validation {
    condition = try(alltrue([
      for key, request in var.requests :
      try(request.failure_percentage == null, true) || (
        can(regex("^-?[0-9]+(\\.[0-9]+)?$", jsonencode(request.failure_percentage))) &&
        try(request.failure_percentage >= 0 && request.failure_percentage <= 1, false)
      )
    ]), false)
    error_message = "failure_percentage must be null or a numeric value between 0 and 1. Offending request keys: ${try(join(", ", sort([for key, request in var.requests : key if !try(try(request.failure_percentage == null, true) || (can(regex("^-?[0-9]+(\\.[0-9]+)?$", jsonencode(request.failure_percentage))) && try(request.failure_percentage >= 0 && request.failure_percentage <= 1, false)), false)])), "<invalid input container>")}."
  }
}

variable "exemptions" {
  description = "Governed exemption requests keyed by stable request key."
  type        = any
  default     = {}

  validation {
    condition     = can(keys(var.exemptions)) && !can(tolist(var.exemptions))
    error_message = "exemptions must be a keyed object or map of exemption request objects."
  }

  validation {
    condition = try(alltrue([
      for key, exemption in var.exemptions :
      trimspace(key) != "" && can(keys(exemption))
    ]), false)
    error_message = "Each exemption request must use a non-blank key and an object value. Offending exemption keys: ${try(join(", ", sort([for key, exemption in var.exemptions : key if !try(trimspace(key) != "" && can(keys(exemption)), false)])), "<invalid input container>")}."
  }

  validation {
    condition = try(alltrue([
      for key, exemption in var.exemptions :
      length(setsubtract(toset(keys(exemption)), toset([
        "request_mode", "assignment_id", "scope", "owner", "reason", "approval_reference",
        "ticket_reference", "category", "compensating_control", "expires_on",
        "policy_definition_reference_ids", "selectors", "display_name", "description"
      ]))) == 0
    ]), false)
    error_message = "Exemption requests may contain only fields from the governed exemption contract. Offending exemption keys: ${try(join(", ", sort([for key, exemption in var.exemptions : key if !try(length(setsubtract(toset(keys(exemption)), toset(["request_mode", "assignment_id", "scope", "owner", "reason", "approval_reference", "ticket_reference", "category", "compensating_control", "expires_on", "policy_definition_reference_ids", "selectors", "display_name", "description"]))) == 0, false)])), "<invalid input container>")}."
  }
}

variable "evaluation_time" {
  description = "Optional RFC3339 instant used to classify exemption expiry. When omitted, Terraform evaluation time is used."
  type        = string
  default     = null

  validation {
    condition     = var.evaluation_time == null || can(formatdate("YYYY-MM-DD'T'hh:mm:ss'Z'", var.evaluation_time))
    error_message = "evaluation_time must be null or a valid RFC3339 timestamp."
  }
}
