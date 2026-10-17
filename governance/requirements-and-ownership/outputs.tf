output "requirements" {
  description = "Normalised governance requirement and ownership records."
  value       = local.requirement_records
  depends_on  = [terraform_data.contract_guard]
}

output "traceability" {
  description = "Requirement-to-control-to-assignment records with verified internal, declared external, unknown and blocking missing-reference states."
  value       = local.traceability
  depends_on  = [terraform_data.contract_guard]
}
