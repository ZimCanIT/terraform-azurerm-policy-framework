output "requested_operations" {
  description = "Normalised remediation requests keyed by operation key, including mode, scope, approval reference, role scope, evidence metadata, status, blocked reasons, the resolved remediation eligibility with its producer reason, the policy definition ID, the full member inventory and the required-role decision for the selected target."
  value       = local.request_views
}

output "discovered_operations" {
  description = "Discovery-mode requests keyed by operation key, with the filtered caller-supplied discovery targets and their count."
  value = {
    for key, request in local.request_views :
    key => merge(request, {
      discovered_count   = local.filtered_discovery_targets[key] == null ? null : length(local.filtered_discovery_targets[key])
      discovered_targets = local.filtered_discovery_targets[key]
    }) if request.status == "discovery"
  }
}

output "skipped_operations" {
  description = "Disabled requests keyed by operation key."
  value       = { for key, request in local.request_views : key => request if request.status == "skipped" }
}

output "blocked_operations" {
  description = "Execute or discovery requests blocked by unknown, malformed or inconsistent context or controls, including the producer reason, keyed by operation key."
  value       = { for key, request in local.request_views : key => request if request.status == "blocked" }
}

output "created_operations" {
  description = "Explicit remediation operations created by this module, keyed by operation key, with the Azure remediation resource ID."
  value       = local.created_operations
}

output "requested_exemptions" {
  description = "Normalised exemption requests keyed by stable request key."
  value       = local.requested_exemptions
}

output "approved_exemptions" {
  description = "Requests that carry an approval or ticket reference and are eligible for creation or renewal."
  value       = local.approved_exemptions
}

output "active_exemptions" {
  description = "Approved, unexpired create, update or renew intent with separate Azure execution status."
  value       = local.active_exemptions
}

output "status_contract" {
  description = "Canonical exemption lifecycle views keyed by request key; Azure status is reported separately from request intent."
  value = {
    requested = local.requested_exemptions
    approved  = local.approved_exemptions
    active    = local.active_exemptions
    expired   = local.expired_exemptions
    blocked   = local.blocked_exemptions
    rejected  = local.rejected_exemptions
  }
}

output "expired_exemptions" {
  description = "Requests in expire mode, and reject, blocked or disabled requests whose expiry has elapsed at the evaluation time. An elapsed create, update or renew request blocks the plan instead."
  value       = local.expired_exemptions
}

output "blocked_exemptions" {
  description = "Requests explicitly blocked or disabled."
  value       = local.blocked_exemptions
}

output "rejected_exemptions" {
  description = "Requests explicitly rejected."
  value       = local.rejected_exemptions
}

output "created_exemption_ids" {
  description = "Azure exemption resource ids created by this module, keyed by stable request key."
  value       = local.exemption_resource_ids
}
