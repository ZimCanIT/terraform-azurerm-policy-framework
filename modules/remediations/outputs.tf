output "requested_operations" {
  description = "Normalised remediation requests keyed by operation key, including mode, scope, approval reference, role scope, evidence metadata, status, blocked reasons and the resolved remediation eligibility decision with its producer reason."
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
  description = "Execute or discovery requests that were not eligible for resource creation, keyed by operation key."
  value       = { for key, request in local.request_views : key => request if request.status == "blocked" }
}

output "created_operations" {
  description = "Explicit remediation operations created by this module, keyed by operation key, with the Azure remediation resource ID."
  value       = local.created_operations
}
