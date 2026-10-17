locals {
  raw_reference_lists = {
    for key, exemption in var.exemptions :
    key => try(exemption.policy_definition_reference_ids, null)
  }

  reference_list_valid = {
    for key, references in local.raw_reference_lists :
    key => references == null || (
      can(tolist(references)) &&
      (length(references) == 0 || can(references[0])) &&
      alltrue([
        for reference_id in tolist(references) :
        try(
          can(regex("^\"[^\"]*\"$", jsonencode(reference_id))) &&
          jsonencode(reference_id) == format("\"%s\"", reference_id) &&
          can(regex("^\\S(.*\\S)?$", reference_id)),
          false
        )
      ]) &&
      length(tolist(references)) == length(toset(tolist(references)))
    )
  }

  raw_selectors = {
    for key, exemption in var.exemptions :
    key => try(exemption.selectors, null)
  }

  selector_valid = {
    for key, selectors in local.raw_selectors :
    key => selectors == null || (
      can(tolist(selectors)) &&
      alltrue([for selector in tolist(selectors) : can(keys(selector)) && length(setsubtract(toset(keys(selector)), toset(["kind", "in", "not_in"]))) == 0])
    )
  }

  exemption_entries = {
    for key, exemption in var.exemptions :
    key => {
      request_mode                    = try(lower(exemption.request_mode), null)
      assignment_id                   = try(exemption.assignment_id, null)
      scope_type                      = try(lower(exemption.scope.type), null)
      scope_id                        = try(exemption.scope.id, null)
      owner                           = try(exemption.owner, null)
      reason                          = try(exemption.reason, null)
      approval_reference              = try(exemption.approval_reference, null)
      ticket_reference                = try(exemption.ticket_reference, null)
      category                        = try(exemption.category, null)
      compensating_control            = try(exemption.compensating_control, null)
      expires_on                      = try(exemption.expires_on, null)
      policy_definition_reference_ids = local.reference_list_valid[key] && local.raw_reference_lists[key] != null ? tolist(local.raw_reference_lists[key]) : null
      selectors                       = local.selector_valid[key] && local.raw_selectors[key] != null ? tolist(local.raw_selectors[key]) : null
      display_name                    = try(exemption.display_name, null)
      description                     = try(exemption.description, null)
    }
  }

  request_modes = ["create", "update", "renew", "expire", "reject", "blocked", "disabled"]
  active_modes  = ["create", "update", "renew"]

  assignment_matches = {
    for key, exemption in local.exemption_entries :
    key => try(local.assignment_entries_by_id[exemption.assignment_id], null)
  }

  governance_fields = [
    "owner", "reason", "category", "compensating_control", "approval_reference",
    "ticket_reference", "display_name", "description", "expires_on"
  ]

  # A supplied governance string passes only when it is a JSON-quoted string
  # whose quoting round trip is unchanged (jsonencode escapes newlines, tabs,
  # quotes, backslashes and control characters, so any escape breaks the
  # equality) and whose content is non-blank without surrounding whitespace.
  strict_governance_strings_valid = {
    for key, exemption in local.exemption_entries :
    key => {
      for field in local.governance_fields :
      field => exemption[field] != null && try(alltrue([
        can(regex("^\"[^\"]*\"$", jsonencode(exemption[field]))),
        jsonencode(exemption[field]) == format("\"%s\"", exemption[field]),
        can(regex("^\\S(.*\\S)?$", exemption[field])),
      ]), false)
    }
  }

  strict_governance_field_failures = {
    for key, fields in local.strict_governance_strings_valid :
    key => [for field, valid in fields : field if !valid && local.exemption_entries[key][field] != null]
  }

  strict_governance_failures = {
    for key, fields in local.strict_governance_field_failures :
    key => fields if length(fields) > 0
  }

  valid_expiry = {
    for key, exemption in local.exemption_entries :
    key => exemption.expires_on != null && can(formatdate("YYYY-MM-DD'T'hh:mm:ss'Z'", exemption.expires_on))
  }

  expiry_elapsed = {
    for key, exemption in local.exemption_entries :
    key => local.valid_expiry[key] && timecmp(var.evaluation_time != null ? var.evaluation_time : timestamp(), exemption.expires_on) >= 0
  }

  invalid_request_mode_keys   = [for key, exemption in local.exemption_entries : key if !contains(local.request_modes, exemption.request_mode)]
  invalid_reference_list_keys = [for key in keys(local.exemption_entries) : key if !local.reference_list_valid[key]]
  invalid_selector_keys       = [for key in keys(local.exemption_entries) : key if !local.selector_valid[key]]

  missing_governance_keys = [
    for key, exemption in local.exemption_entries : key
    if exemption.owner == null || exemption.reason == null || exemption.category == null ||
    exemption.compensating_control == null || (exemption.approval_reference == null && exemption.ticket_reference == null)
  ]

  invalid_expiry_keys = [for key in keys(local.exemption_entries) : key if !local.valid_expiry[key]]
  invalid_active_expiry_keys = [
    for key, exemption in local.exemption_entries : key
    if contains(local.active_modes, exemption.request_mode) && local.expiry_elapsed[key]
  ]
  invalid_category_keys   = [for key, exemption in local.exemption_entries : key if !try(contains(["Waiver", "Mitigated"], exemption.category), false)]
  invalid_scope_type_keys = [for key, exemption in local.exemption_entries : key if !try(contains(local.scope_types, exemption.scope_type), false)]

  invalid_scope_id_keys = [
    for key, exemption in local.exemption_entries : key
    if !can(regex(local.scope_patterns[exemption.scope_type], exemption.scope_id))
  ]

  invalid_assignment_reference_keys = [
    for key, exemption in local.exemption_entries : key
    if local.assignment_matches[key] == null || !can(regex(local.policy_assignment_id_pattern, exemption.assignment_id))
  ]

  invalid_assignment_scope_keys = [
    for key in keys(local.exemption_entries) : key
    if !local.scope_contained["exemption/${key}"]
  ]

  invalid_member_reference_keys = [
    for key, exemption in local.exemption_entries : key
    if local.reference_list_valid[key] && exemption.policy_definition_reference_ids != null && !try(
      local.assignment_member_inventory_known[local.assignment_matches[key].assignment_key] &&
      alltrue([
        for reference_id in exemption.policy_definition_reference_ids :
        contains(keys(local.assignment_members_by_reference_id[local.assignment_matches[key].assignment_key]), reference_id)
      ]),
      false
    )
  ]

  invalid_target_selectors_keys = [for key, exemption in local.exemption_entries : key if exemption.selectors != null]

  requested_exemptions = {
    for key, exemption in local.exemption_entries : key => merge(exemption, {
      request_key   = key
      intent_status = exemption.request_mode
    })
  }

  approved_exemptions = {
    for key, exemption in local.requested_exemptions : key => merge(exemption, {
      approval_status = "approved"
      approved        = true
    })
    if contains(local.active_modes, exemption.request_mode) && (local.strict_governance_strings_valid[key].approval_reference || local.strict_governance_strings_valid[key].ticket_reference)
  }

  expired_exemptions = {
    for key, exemption in local.requested_exemptions : key => merge(exemption, {
      lifecycle_status = "expired"
      expired          = true
      azure_status     = contains(keys(local.exemption_resource_ids), key) ? "created_by_module" : "not_created"
    })
    if exemption.request_mode == "expire" || local.expiry_elapsed[key]
  }

  blocked_exemptions = {
    for key, exemption in local.requested_exemptions : key => merge(exemption, {
      lifecycle_status = exemption.request_mode
      blocked          = true
    })
    if contains(["disabled", "blocked"], exemption.request_mode)
  }

  rejected_exemptions = {
    for key, exemption in local.requested_exemptions : key => merge(exemption, {
      lifecycle_status = "rejected"
      rejected         = true
    })
    if exemption.request_mode == "reject"
  }

  active_exemptions = {
    for key, exemption in local.approved_exemptions : key => merge(exemption, {
      lifecycle_status = "active"
      active           = true
      azure_status     = contains(keys(local.exemption_resource_ids), key) ? "created_by_module" : "not_created"
    })
    if contains(local.active_modes, exemption.request_mode) && !local.expiry_elapsed[key]
  }

  # Create, update and renew requests partitioned by scope type; each scope
  # resource iterates its own partition under the stable request keys.
  exemption_by_scope = {
    for scope_type in local.scope_types : scope_type => {
      for key, exemption in local.exemption_entries : key => exemption
      if try(contains(local.active_modes, exemption.request_mode) && exemption.scope_type == scope_type, false)
    }
  }

  # Common exemption resource arguments are projected once per request key; the
  # scope resources below add only their own scope ID argument.
  exemption_common_fields = {
    for key, exemption in local.exemption_entries :
    key => {
      policy_assignment_id            = exemption.assignment_id
      exemption_category              = exemption.category
      description                     = exemption.description != null ? exemption.description : exemption.reason
      display_name                    = exemption.display_name != null ? exemption.display_name : key
      expires_on                      = exemption.expires_on
      policy_definition_reference_ids = exemption.policy_definition_reference_ids
      metadata = jsonencode({
        assignment_id        = exemption.assignment_id
        approval_reference   = exemption.approval_reference
        category             = exemption.category
        compensating_control = exemption.compensating_control
        expires_on           = exemption.expires_on
        owner                = exemption.owner
        reason               = exemption.reason
        request_mode         = exemption.request_mode
        scope_type           = exemption.scope_type
        scope_id             = exemption.scope_id
        ticket_reference     = exemption.ticket_reference
      })
    }
  }

  exemption_resource_ids = merge([
    for resources in [
      azurerm_management_group_policy_exemption.this,
      azurerm_subscription_policy_exemption.this,
      azurerm_resource_group_policy_exemption.this,
      azurerm_resource_policy_exemption.this,
    ] : { for key, resource in resources : key => resource.id }
  ]...)
}
