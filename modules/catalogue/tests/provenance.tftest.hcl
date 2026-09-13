run "summarises_each_entry_once_with_companions_attached" {
  command = plan

  variables {
    custom_definition_directory  = "tests/fixtures/json_ingestion/custom"
    built_in_reference_directory = "tests/fixtures/json_ingestion/built-in"
    initiative_directory         = "tests/fixtures/initiative_ingestion/valid"

    native_definitions = {
      native_definition = {
        source_type          = "built_in"
        display_name         = "Native definition"
        policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
        version_constraint   = "1.*.*"
      }
    }

    native_initiatives = {
      native_initiative = {
        display_name = "Native initiative"

        policy_definition_references = [
          {
            reference_id   = "native_definition"
            definition_key = "native_definition"
          }
        ]
      }
    }
  }

  assert {
    condition     = length(output.source_summary) == 5
    error_message = "source_summary must contain exactly one record per catalogue entry, excluding companions."
  }

  assert {
    condition     = length([for record in output.source_summary : record if record.catalogue_key == ""]) == 0
    error_message = "source_summary must never emit a record with a blank catalogue key."
  }

  assert {
    condition     = length([for record in output.source_summary : record if record.source_path != null && endswith(record.source_path, "-parameters.json")]) == 0
    error_message = "Parameter companions must not appear as independent source_summary entries."
  }

  assert {
    condition = alltrue([
      for record in output.source_summary :
      can(keys(record)) &&
      length(setsubtract(toset(keys(record)), toset(["catalogue_key", "source_type", "authoring_format", "source_path", "companion_source_path"]))) == 0
    ])
    error_message = "Every source_summary record must share the documented schema."
  }

  assert {
    condition = (
      [for record in output.source_summary : record if record.catalogue_key == "require_cost_centre_tag"][0].source_path == "require-cost-centre.json" &&
      [for record in output.source_summary : record if record.catalogue_key == "require_cost_centre_tag"][0].companion_source_path == "require-cost-centre-parameters.json"
    )
    error_message = "A custom definition companion must be associated with its parent record."
  }

  assert {
    condition     = [for record in output.source_summary : record if record.catalogue_key == "allowed_locations"][0].companion_source_path == null
    error_message = "A JSON entry without a companion must report a null companion_source_path."
  }

  assert {
    condition = (
      [for record in output.source_summary : record if record.catalogue_key == "security_baseline"][0].source_path == "security-baseline.json" &&
      [for record in output.source_summary : record if record.catalogue_key == "security_baseline"][0].companion_source_path == "security-baseline-parameters.json"
    )
    error_message = "An initiative companion must be associated with its parent record."
  }

  assert {
    condition = (
      [for record in output.source_summary : record if record.catalogue_key == "native_definition"][0].source_path == null &&
      [for record in output.source_summary : record if record.catalogue_key == "native_definition"][0].companion_source_path == null &&
      [for record in output.source_summary : record if record.catalogue_key == "native_definition"][0].authoring_format == "hcl"
    )
    error_message = "Native HCL entries must report null source and companion paths with the hcl authoring format."
  }

  assert {
    condition     = length([for record in output.source_summary : record if record.catalogue_key == "require_cost_centre_tag"]) == 1
    error_message = "Each catalogue key must appear exactly once in source_summary."
  }
}
