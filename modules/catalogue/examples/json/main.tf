terraform {
  required_version = ">= 1.12.0"
}

module "catalogue" {
  source = "../.."

  custom_definition_directory  = "${path.module}/catalogue/custom-definitions"
  built_in_reference_directory = "${path.module}/catalogue/built-in-references"
  initiative_directory         = "${path.module}/catalogue/initiatives"
}

output "definitions" {
  description = "Canonical definitions for modules/definitions."
  value       = module.catalogue.definitions
}

output "initiatives" {
  description = "Canonical initiative envelopes for the future modules/initiatives."
  value       = module.catalogue.initiatives
}

output "source_summary" {
  description = "Non-sensitive provenance for review."
  value       = module.catalogue.source_summary
}
