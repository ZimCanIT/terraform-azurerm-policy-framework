run "ingests_multiple_sources_in_one_call_with_deterministic_keys" {
  command = plan

  variables {
    custom_definition_directory  = "tests/fixtures/json_ingestion/custom"
    built_in_reference_directory = "tests/fixtures/json_ingestion/built-in"
    initiative_directory         = "tests/fixtures/initiative_ingestion/valid"

    native_definitions = {
      native_built_in = {
        source_type          = "built_in"
        display_name         = "Native built-in"
        policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
        version_constraint   = "1.*.*"
      }

      native_custom = {
        source_type  = "custom"
        display_name = "Native custom"
        version      = "1.0.0"
        policy_rule = {
          if = {
            field  = "type"
            equals = "Microsoft.Resources/subscriptions"
          }
          then = {
            effect = "audit"
          }
        }
      }
    }

    native_initiatives = {
      native_security = {
        display_name = "Native security"

        policy_definition_references = [
          {
            reference_id   = "native_custom"
            definition_key = "native_custom"
          }
        ]
      }
    }
  }

  assert {
    condition     = keys(output.definitions) == ["allowed_locations", "native_built_in", "native_custom", "require_cost_centre_tag"]
    error_message = "Bulk ingestion must merge every definition source under deterministic stable keys."
  }

  assert {
    condition     = keys(output.initiatives) == ["native_security", "security_baseline"]
    error_message = "Bulk ingestion must merge every initiative source under deterministic stable keys."
  }

  assert {
    condition     = length(output.source_summary) == 6
    error_message = "Bulk ingestion must report one provenance record per entry, excluding companions."
  }

  assert {
    condition = (
      output.definitions["native_custom"].version == "1.0.0" &&
      output.definitions["require_cost_centre_tag"].parameters.tagName.defaultValue == "costCentre" &&
      output.definitions["allowed_locations"].version_constraint == "1.*.*"
    )
    error_message = "Bulk ingestion must preserve native and JSON definition values."
  }

  assert {
    condition     = output.initiatives["security_baseline"].policy_definition_references[0].definition_key == "allowed_locations" && output.initiatives["native_security"].policy_definition_references[0].definition_key == "native_custom"
    error_message = "Bulk ingestion must preserve each initiative's member references."
  }
}
