module "catalogue" {
  source = "../../../modules/catalogue"

  custom_definition_directory  = "../../../modules/catalogue/tests/fixtures/json_ingestion/custom"
  built_in_reference_directory = "../../../modules/catalogue/tests/fixtures/json_ingestion/built-in"
  initiative_directory         = "../../../modules/catalogue/tests/fixtures/initiative_ingestion/valid"
}

output "definitions" {
  description = "Canonical definitions emitted by catalogue for modules/definitions."
  value       = module.catalogue.definitions
}

output "initiatives" {
  description = "Canonical initiatives emitted by catalogue for modules/initiatives."
  value       = module.catalogue.initiatives
}
