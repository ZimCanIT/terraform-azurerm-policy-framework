run "catalogue_emits_downstream_contract_envelopes" {
  command = plan

  assert {
    condition     = output.definitions["allowed_locations"].source_type == "built_in"
    error_message = "Catalogue must emit built-in definitions in the definitions contract envelope."
  }

  assert {
    condition     = output.definitions["require_cost_centre_tag"].source_type == "custom"
    error_message = "Catalogue must emit custom definitions in the definitions contract envelope."
  }

  assert {
    condition     = output.definitions["require_cost_centre_tag"].version == "1.0.0"
    error_message = "Catalogue must preserve custom definition version intent for modules/definitions."
  }

  assert {
    condition     = output.initiatives["security_baseline"].policy_definition_references[0].definition_key == "allowed_locations"
    error_message = "Catalogue must preserve definition-key references for modules/initiatives."
  }
}
