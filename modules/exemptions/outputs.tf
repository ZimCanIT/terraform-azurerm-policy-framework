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
  description = "Requests explicitly marked for expiry."
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
