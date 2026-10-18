# Terraform outputs record request intent and resource identity. Compliance
# results and remediation task status are external operational records that
# Azure holds, never Terraform state.

output "requested_operations" {
  description = "Remediation requests with the derived assignment ID, eligibility and blocked reasons."
  value       = module.operations.requested_operations
}

output "status_contract" {
  description = "Exemption lifecycle classification keyed by request key."
  value       = module.operations.status_contract
}
