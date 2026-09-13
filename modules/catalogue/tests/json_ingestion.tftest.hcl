run "normalizes_custom_and_built_in_json" {
  command = plan

  variables {
    custom_definition_directory  = "tests/fixtures/json_ingestion/custom"
    built_in_reference_directory = "tests/fixtures/json_ingestion/built-in"
  }

  assert {
    condition     = output.definitions["require_cost_centre_tag"].source_type == "custom"
    error_message = "Custom JSON must normalize into a custom canonical definition."
  }

  assert {
    condition     = output.definitions["require_cost_centre_tag"].parameters.tagName.defaultValue == "costCentre"
    error_message = "A matching parameter companion must be included as structured parameters."
  }

  assert {
    condition     = output.definitions["allowed_locations"].policy_definition_id == "/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c"
    error_message = "Built-in JSON must preserve its policy definition ID."
  }
}

run "preserves_companion_value_types" {
  command = plan

  variables {
    custom_definition_directory = "tests/fixtures/json_ingestion/companion-types"
  }

  assert {
    condition     = jsonencode(output.definitions["typed_definition"].parameters.retryCount.defaultValue) == jsonencode(3)
    error_message = "Integer companion values must remain numbers."
  }

  assert {
    condition     = jsonencode(output.definitions["typed_definition"].parameters.enforce.defaultValue) == jsonencode(true)
    error_message = "Boolean companion values must remain booleans."
  }

  assert {
    condition     = jsonencode(output.definitions["typed_definition"].parameters.locations.defaultValue) == jsonencode(["eastus", "westus"])
    error_message = "Array companion values must remain arrays with element order preserved."
  }

  assert {
    condition     = jsonencode(output.definitions["typed_definition"].parameters.advanced.defaultValue) == jsonencode({ nested = { enabled = false }, threshold = 2.5 })
    error_message = "Nested object companion values must remain structured objects."
  }
}

run "preserves_capability_and_governance_fields_from_json" {
  command = plan

  variables {
    custom_definition_directory = "tests/fixtures/json_ingestion/companion-types"
  }

  assert {
    condition     = output.definitions["typed_definition"].supported_overrides == [{ kind = "policyEffect", value = "Disabled" }]
    error_message = "Supported override declarations must be preserved verbatim."
  }

  assert {
    condition     = output.definitions["typed_definition"].selectors == [{ kind = "resourceLocation", in = ["eastus"] }]
    error_message = "Selector declarations must be preserved verbatim."
  }

  assert {
    condition     = output.definitions["typed_definition"].non_compliance_messages.default == "The synthetic control is not compliant."
    error_message = "Non-compliance message declarations must be preserved verbatim."
  }

  assert {
    condition     = output.definitions["typed_definition"].capabilities.supportsIdentity == true && output.definitions["typed_definition"].capabilities.supportsRemediation == false
    error_message = "Capability declarations must be preserved verbatim, including false values."
  }

  assert {
    condition     = output.definitions["typed_definition"].governance.requirement_id == "REQ-TAGS-001" && output.definitions["typed_definition"].governance.owner == "platform-team"
    error_message = "Governance declarations must be preserved verbatim."
  }
}

run "allows_custom_json_without_parameter_companion" {
  command = plan

  variables {
    custom_definition_directory = "tests/fixtures/json_ingestion/custom-no-companion"
  }

  assert {
    condition     = output.definitions["no_companion_definition"].parameters == null
    error_message = "A custom envelope without a companion must not fabricate parameters."
  }
}

run "rejects_orphan_parameter_file" {
  command = plan

  variables {
    custom_definition_directory = "tests/fixtures/json_ingestion/orphan-parameter"
  }

  expect_failures = [terraform_data.json_ingestion_contract]
}

run "rejects_duplicate_custom_json_keys" {
  command = plan

  variables {
    custom_definition_directory = "tests/fixtures/json_ingestion/duplicate-custom"
  }

  expect_failures = [terraform_data.json_ingestion_contract]
}

run "rejects_duplicate_built_in_json_keys" {
  command = plan

  variables {
    built_in_reference_directory = "tests/fixtures/json_ingestion/duplicate-built-in"
  }

  expect_failures = [terraform_data.json_ingestion_contract]
}

run "rejects_custom_envelope_missing_required_fields" {
  command = plan

  variables {
    custom_definition_directory = "tests/fixtures/json_ingestion/missing-custom-fields"
  }

  expect_failures = [terraform_data.json_ingestion_contract]
}

run "rejects_built_in_envelope_missing_required_fields" {
  command = plan

  variables {
    built_in_reference_directory = "tests/fixtures/json_ingestion/missing-built-in-fields"
  }

  expect_failures = [terraform_data.json_ingestion_contract]
}

run "rejects_custom_inline_and_companion_parameters_conflict" {
  command = plan

  variables {
    custom_definition_directory = "tests/fixtures/json_ingestion/custom-parameters-conflict"
  }

  expect_failures = [terraform_data.json_ingestion_contract]
}

run "rejects_malformed_custom_json" {
  command = plan

  variables {
    custom_definition_directory = "tests/fixtures/json_ingestion/malformed"
  }

  expect_failures = [terraform_data.json_ingestion_contract]
}

run "rejects_non_object_null_custom_json" {
  command = plan

  variables {
    custom_definition_directory = "tests/fixtures/json_ingestion/non-object-null"
  }

  expect_failures = [terraform_data.json_ingestion_contract]
}

run "rejects_non_object_array_custom_json" {
  command = plan

  variables {
    custom_definition_directory = "tests/fixtures/json_ingestion/non-object-array"
  }

  expect_failures = [terraform_data.json_ingestion_contract]
}

run "rejects_non_object_string_custom_json" {
  command = plan

  variables {
    custom_definition_directory = "tests/fixtures/json_ingestion/non-object-string"
  }

  expect_failures = [terraform_data.json_ingestion_contract]
}

run "rejects_non_object_number_custom_json" {
  command = plan

  variables {
    custom_definition_directory = "tests/fixtures/json_ingestion/non-object-number"
  }

  expect_failures = [terraform_data.json_ingestion_contract]
}

run "rejects_non_object_built_in_json" {
  command = plan

  variables {
    built_in_reference_directory = "tests/fixtures/json_ingestion/built-in-non-object"
  }

  expect_failures = [terraform_data.json_ingestion_contract]
}

run "rejects_invalid_capability_container_shape" {
  command = plan

  variables {
    custom_definition_directory = "tests/fixtures/json_ingestion/capability-shape-invalid"
  }

  expect_failures = [terraform_data.json_ingestion_contract]
}

run "rejects_numeric_custom_definition_catalogue_key" {
  command = plan

  variables {
    custom_definition_directory = "tests/fixtures/json_ingestion/scalar-numeric-key"
  }

  expect_failures = [terraform_data.json_ingestion_contract]
}

run "rejects_numeric_custom_definition_display_name" {
  command = plan

  variables {
    custom_definition_directory = "tests/fixtures/json_ingestion/scalar-numeric-display-name"
  }

  expect_failures = [terraform_data.json_ingestion_contract]
}

run "rejects_boolean_custom_definition_display_name" {
  command = plan

  variables {
    custom_definition_directory = "tests/fixtures/json_ingestion/scalar-boolean-display-name"
  }

  expect_failures = [terraform_data.json_ingestion_contract]
}

run "rejects_collection_custom_definition_display_name" {
  command = plan

  variables {
    custom_definition_directory = "tests/fixtures/json_ingestion/scalar-collection-display-name"
  }

  expect_failures = [terraform_data.json_ingestion_contract]
}

run "rejects_non_string_custom_definition_optional_scalars" {
  command = plan

  variables {
    custom_definition_directory = "tests/fixtures/json_ingestion/scalar-optional-types"
  }

  expect_failures = [terraform_data.json_ingestion_contract]
}

run "rejects_whitespace_json_definition_key" {
  command = plan

  variables {
    custom_definition_directory = "tests/fixtures/json_ingestion/whitespace-key"
  }

  expect_failures = [terraform_data.json_ingestion_contract]
}

run "rejects_numeric_native_definition_display_name" {
  command = plan

  variables {
    native_definitions = {
      numeric_display_name = {
        source_type  = "custom"
        display_name = 42
        version      = "1.0.0"

        policy_rule = {
          then = {
            effect = "audit"
          }
        }
      }
    }
  }

  expect_failures = [terraform_data.json_ingestion_contract]
}

run "rejects_boolean_native_definition_display_name" {
  command = plan

  variables {
    native_definitions = {
      boolean_display_name = {
        source_type  = "custom"
        display_name = true
        version      = "1.0.0"

        policy_rule = {
          then = {
            effect = "audit"
          }
        }
      }
    }
  }

  expect_failures = [terraform_data.json_ingestion_contract]
}

run "rejects_collection_native_definition_display_name" {
  command = plan

  variables {
    native_definitions = {
      collection_display_name = {
        source_type  = "custom"
        display_name = ["not", "a", "string"]
        version      = "1.0.0"

        policy_rule = {
          then = {
            effect = "audit"
          }
        }
      }
    }
  }

  expect_failures = [terraform_data.json_ingestion_contract]
}

run "rejects_non_string_native_definition_optional_scalars" {
  command = plan

  variables {
    native_definitions = {
      optional_scalar_types = {
        source_type         = "custom"
        display_name        = "Optional scalar types"
        description         = true
        name                = 42
        mode                = ["Indexed"]
        management_group_id = 7
        version             = "1.0.0"

        policy_rule = {
          then = {
            effect = "audit"
          }
        }
      }
    }
  }

  expect_failures = [terraform_data.json_ingestion_contract]
}

run "rejects_whitespace_native_definition_key" {
  command = plan

  variables {
    native_definitions = {
      " padded_key " = {
        source_type  = "custom"
        display_name = "Padded key"
        version      = "1.0.0"

        policy_rule = {
          then = {
            effect = "audit"
          }
        }
      }
    }
  }

  expect_failures = [terraform_data.json_ingestion_contract]
}

run "rejects_cross_source_definition_key_collision" {
  command = plan

  variables {
    custom_definition_directory = "tests/fixtures/json_ingestion/custom"

    native_definitions = {
      require_cost_centre_tag = {
        source_type          = "built_in"
        display_name         = "Cross-source collision"
        policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
        version_constraint   = "1.*.*"
      }
    }
  }

  expect_failures = [output.definitions]
}

run "rejects_case_insensitive_cross_source_definition_key_collision" {
  command = plan

  variables {
    custom_definition_directory = "tests/fixtures/json_ingestion/custom"

    native_definitions = {
      REQUIRE_COST_CENTRE_TAG = {
        source_type          = "built_in"
        display_name         = "Case-insensitive cross-source collision"
        policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
        version_constraint   = "1.*.*"
      }
    }
  }

  expect_failures = [output.definitions]
}

run "rejects_null_custom_parameter_companion" {
  command = plan

  variables {
    custom_definition_directory = "tests/fixtures/json_ingestion/companion-null"
  }

  expect_failures = [terraform_data.json_ingestion_contract]
}

run "rejects_array_custom_parameter_companion" {
  command = plan

  variables {
    custom_definition_directory = "tests/fixtures/json_ingestion/companion-array"
  }

  expect_failures = [terraform_data.json_ingestion_contract]
}

run "rejects_string_custom_parameter_companion" {
  command = plan

  variables {
    custom_definition_directory = "tests/fixtures/json_ingestion/companion-string"
  }

  expect_failures = [terraform_data.json_ingestion_contract]
}

run "rejects_number_custom_parameter_companion" {
  command = plan

  variables {
    custom_definition_directory = "tests/fixtures/json_ingestion/companion-number"
  }

  expect_failures = [terraform_data.json_ingestion_contract]
}

run "rejects_boolean_custom_parameter_companion" {
  command = plan

  variables {
    custom_definition_directory = "tests/fixtures/json_ingestion/companion-boolean"
  }

  expect_failures = [terraform_data.json_ingestion_contract]
}

run "rejects_malformed_custom_parameter_companion" {
  command = plan

  variables {
    custom_definition_directory = "tests/fixtures/json_ingestion/companion-malformed"
  }

  expect_failures = [terraform_data.json_ingestion_contract]
}
