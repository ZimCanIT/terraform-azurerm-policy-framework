run "normalizes_native_and_json_initiatives" {
  command = plan

  variables {
    initiative_directory = "tests/fixtures/initiative_ingestion/valid"

    native_initiatives = {
      native_security = {
        display_name = "Native security"

        policy_definition_references = [
          {
            reference_id   = "require_cost_centre_tag"
            definition_key = "require_cost_centre_tag"
          }
        ]

        version = "1.0.0"
      }
    }
  }

  assert {
    condition     = output.initiatives["native_security"].policy_definition_references[0].definition_key == "require_cost_centre_tag"
    error_message = "Native HCL initiatives must preserve stable definition-key member references."
  }

  assert {
    condition     = output.initiatives["security_baseline"].policy_definition_references[0].definition_key == "allowed_locations"
    error_message = "JSON initiatives must preserve catalogue member references for modules/initiatives."
  }

  assert {
    condition     = output.initiatives["security_baseline"].parameters.allowedLocations.type == "Array"
    error_message = "JSON initiative parameter companion files must be attached to their initiative envelope."
  }

  assert {
    condition     = output.initiatives["security_baseline"].policy_definition_references[1].pinned_version == "2.0.0"
    error_message = "JSON initiatives must preserve explicit member version intent."
  }

  assert {
    condition = (
      length(output.initiatives["security_baseline"].policy_definition_references) == 2 &&
      output.initiatives["security_baseline"].policy_definition_references[0].definition_key == "allowed_locations" &&
      output.initiatives["security_baseline"].policy_definition_references[1].policy_definition_id == "/providers/Microsoft.Authorization/policyDefinitions/cccccccc-cccc-cccc-cccc-cccccccccccc"
    )
    error_message = "Heterogeneous member shapes must be validated and preserved without tuple-to-list conversion."
  }
}

run "accepts_heterogeneous_native_member_shapes" {
  command = plan

  variables {
    native_initiatives = {
      mixed_members = {
        display_name = "Mixed members"

        policy_definition_references = [
          {
            reference_id   = "keyed_member"
            definition_key = "allowed_locations"
          },
          {
            reference_id         = "direct_member"
            policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/cccccccc-cccc-cccc-cccc-cccccccccccc"
            version_constraint   = "1.*.*"
          }
        ]

        version = "1.0.0"
      }
    }
  }

  assert {
    condition = (
      output.initiatives["mixed_members"].policy_definition_references[0].definition_key == "allowed_locations" &&
      output.initiatives["mixed_members"].policy_definition_references[1].version_constraint == "1.*.*"
    )
    error_message = "Native HCL initiatives must accept heterogeneous keyed and direct member records."
  }
}

run "accepts_external_subscription_and_management_group_ids" {
  command = plan

  variables {
    initiative_directory = "tests/fixtures/initiative_ingestion/external-ids"
  }

  assert {
    condition = (
      output.initiatives["external_ids"].policy_definition_references[0].policy_definition_id == "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyDefinitions/custom-tag" &&
      output.initiatives["external_ids"].policy_definition_references[0].version_constraint == "1.*.*"
    )
    error_message = "Subscription-scoped custom definition IDs must be accepted with explicit version intent."
  }

  assert {
    condition = (
      output.initiatives["external_ids"].policy_definition_references[1].policy_definition_id == "/providers/Microsoft.Management/managementGroups/platform/providers/Microsoft.Authorization/policyDefinitions/custom-location" &&
      output.initiatives["external_ids"].policy_definition_references[1].pinned_version == "2.1.0"
    )
    error_message = "Management-group-scoped custom definition IDs must be accepted with explicit version intent."
  }
}

run "rejects_invalid_initiative_reference" {
  command = plan

  variables {
    initiative_directory = "tests/fixtures/initiative_ingestion/invalid-reference"
  }

  expect_failures = [terraform_data.initiative_ingestion_contract]
}

run "rejects_malformed_group_record" {
  command = plan

  variables {
    initiative_directory = "tests/fixtures/initiative_ingestion/invalid-group"
  }

  expect_failures = [terraform_data.initiative_ingestion_contract]
}

run "rejects_duplicate_member_reference_ids" {
  command = plan

  variables {
    initiative_directory = "tests/fixtures/initiative_ingestion/duplicate-reference"
  }

  expect_failures = [terraform_data.initiative_ingestion_contract]
}

run "rejects_malformed_reference_container_from_json" {
  command = plan

  variables {
    initiative_directory = "tests/fixtures/initiative_ingestion/malformed-references"
  }

  expect_failures = [terraform_data.initiative_ingestion_contract]
}

run "rejects_malformed_reference_container_from_hcl" {
  command = plan

  variables {
    native_initiatives = {
      malformed_members = {
        display_name                 = "Malformed members"
        policy_definition_references = "not-a-list"
      }
    }
  }

  expect_failures = [terraform_data.initiative_ingestion_contract]
}

run "rejects_non_object_native_initiative_parameters" {
  command = plan

  variables {
    native_initiatives = {
      malformed_parameters = {
        display_name = "Malformed parameters"
        parameters   = "not-an-object"

        policy_definition_references = [
          {
            reference_id   = "allowed_locations"
            definition_key = "allowed_locations"
          }
        ]
      }
    }
  }

  expect_failures = [terraform_data.initiative_ingestion_contract]
}

run "rejects_direct_reference_without_version_intent" {
  command = plan

  variables {
    initiative_directory = "tests/fixtures/initiative_ingestion/missing-version-direct"
  }

  expect_failures = [terraform_data.initiative_ingestion_contract]
}

run "rejects_direct_reference_with_conflicting_version_intent" {
  command = plan

  variables {
    initiative_directory = "tests/fixtures/initiative_ingestion/conflicting-version-direct"
  }

  expect_failures = [terraform_data.initiative_ingestion_contract]
}

run "rejects_initiative_envelope_missing_required_fields" {
  command = plan

  variables {
    initiative_directory = "tests/fixtures/initiative_ingestion/missing-fields"
  }

  expect_failures = [terraform_data.initiative_ingestion_contract]
}

run "ignores_parameter_companion_reference_keys" {
  command = plan

  variables {
    initiative_directory = "tests/fixtures/initiative_ingestion/parameter-reference-key"
  }

  assert {
    condition     = output.initiatives["security_baseline"].parameters.policy_definition_references.type == "Object"
    error_message = "Initiative parameter companion files must not be validated as initiative reference envelopes."
  }
}

run "rejects_unsupported_initiative_files" {
  command = plan

  variables {
    initiative_directory = "tests/fixtures/initiative_ingestion/unsupported"
  }

  expect_failures = [terraform_data.initiative_ingestion_contract]
}

run "rejects_orphan_initiative_parameter_file" {
  command = plan

  variables {
    initiative_directory = "tests/fixtures/initiative_ingestion/orphan"
  }

  expect_failures = [terraform_data.initiative_ingestion_contract]
}

run "rejects_initiative_inline_and_companion_parameters_conflict" {
  command = plan

  variables {
    initiative_directory = "tests/fixtures/initiative_ingestion/parameters-conflict"
  }

  expect_failures = [terraform_data.initiative_ingestion_contract]
}

run "rejects_malformed_initiative_json" {
  command = plan

  variables {
    initiative_directory = "tests/fixtures/initiative_ingestion/malformed"
  }

  expect_failures = [terraform_data.initiative_ingestion_contract]
}

run "rejects_non_object_initiative_json" {
  command = plan

  variables {
    initiative_directory = "tests/fixtures/initiative_ingestion/non-object-array"
  }

  expect_failures = [terraform_data.initiative_ingestion_contract]
}

run "rejects_array_initiative_parameter_companion" {
  command = plan

  variables {
    initiative_directory = "tests/fixtures/initiative_ingestion/companion-array"
  }

  expect_failures = [terraform_data.initiative_ingestion_contract]
}

run "rejects_null_initiative_parameter_companion" {
  command = plan

  variables {
    initiative_directory = "tests/fixtures/initiative_ingestion/companion-null"
  }

  expect_failures = [terraform_data.initiative_ingestion_contract]
}

run "rejects_number_initiative_parameter_companion" {
  command = plan

  variables {
    initiative_directory = "tests/fixtures/initiative_ingestion/companion-number"
  }

  expect_failures = [terraform_data.initiative_ingestion_contract]
}

run "keeps_object_initiative_parameter_companion" {
  command = plan

  variables {
    initiative_directory = "tests/fixtures/initiative_ingestion/valid"
  }

  assert {
    condition     = output.initiatives["security_baseline"].parameters.allowedLocations.type == "Array"
    error_message = "A valid object parameter companion must still reach the canonical initiative parameters output."
  }
}

run "rejects_duplicate_json_initiative_keys" {
  command = plan

  variables {
    initiative_directory = "tests/fixtures/initiative_ingestion/duplicate-json"
  }

  expect_failures = [terraform_data.initiative_ingestion_contract]
}

run "rejects_case_insensitive_initiative_key_collisions" {
  command = plan

  variables {
    initiative_directory = "tests/fixtures/initiative_ingestion/valid"

    native_initiatives = {
      SECURITY_BASELINE = {
        display_name = "Security baseline"

        policy_definition_references = [
          {
            reference_id   = "allowed_locations"
            definition_key = "allowed_locations"
          }
        ]
      }
    }
  }

  expect_failures = [output.initiatives]
}

run "rejects_repeated_suffix_non_object_companion" {
  command = plan

  variables {
    initiative_directory = "tests/fixtures/initiative_ingestion/repeated-suffix"
  }

  expect_failures = [terraform_data.initiative_ingestion_contract]
}

run "rejects_repeated_suffix_orphan_companion" {
  command = plan

  variables {
    initiative_directory = "tests/fixtures/initiative_ingestion/repeated-suffix-orphan"
  }

  expect_failures = [terraform_data.initiative_ingestion_contract]
}

run "rejects_object_shaped_native_member_container" {
  command = plan

  variables {
    native_initiatives = {
      object_members = {
        display_name = "Object members"

        policy_definition_references = {
          member = {
            reference_id   = "member"
            definition_key = "allowed_locations"
          }
        }
      }
    }
  }

  expect_failures = [terraform_data.initiative_ingestion_contract]
}

run "rejects_object_shaped_json_member_container" {
  command = plan

  variables {
    initiative_directory = "tests/fixtures/initiative_ingestion/object-members"
  }

  expect_failures = [terraform_data.initiative_ingestion_contract]
}

run "rejects_string_native_group_names_container" {
  command = plan

  variables {
    native_initiatives = {
      group_names_string = {
        display_name = "Group names string"

        policy_definition_references = [
          {
            reference_id   = "member"
            definition_key = "allowed_locations"
            group_names    = "bad"
          }
        ]
      }
    }
  }

  expect_failures = [terraform_data.initiative_ingestion_contract]
}

run "rejects_number_native_group_names_container" {
  command = plan

  variables {
    native_initiatives = {
      group_names_number = {
        display_name = "Group names number"

        policy_definition_references = [
          {
            reference_id   = "member"
            definition_key = "allowed_locations"
            group_names    = 5
          }
        ]
      }
    }
  }

  expect_failures = [terraform_data.initiative_ingestion_contract]
}

run "rejects_boolean_native_group_names_container" {
  command = plan

  variables {
    native_initiatives = {
      group_names_boolean = {
        display_name = "Group names boolean"

        policy_definition_references = [
          {
            reference_id   = "member"
            definition_key = "allowed_locations"
            group_names    = true
          }
        ]
      }
    }
  }

  expect_failures = [terraform_data.initiative_ingestion_contract]
}

run "rejects_object_native_group_names_container" {
  command = plan

  variables {
    native_initiatives = {
      group_names_object = {
        display_name = "Group names object"

        policy_definition_references = [
          {
            reference_id   = "member"
            definition_key = "allowed_locations"
            group_names    = { location_governance = "declared" }
          }
        ]
      }
    }
  }

  expect_failures = [terraform_data.initiative_ingestion_contract]
}

run "rejects_string_json_group_names_container" {
  command = plan

  variables {
    initiative_directory = "tests/fixtures/initiative_ingestion/malformed-group-names-string"
  }

  expect_failures = [terraform_data.initiative_ingestion_contract]
}

run "rejects_number_json_group_names_container" {
  command = plan

  variables {
    initiative_directory = "tests/fixtures/initiative_ingestion/malformed-group-names-number"
  }

  expect_failures = [terraform_data.initiative_ingestion_contract]
}

run "rejects_boolean_json_group_names_container" {
  command = plan

  variables {
    initiative_directory = "tests/fixtures/initiative_ingestion/malformed-group-names-boolean"
  }

  expect_failures = [terraform_data.initiative_ingestion_contract]
}

run "rejects_object_json_group_names_container" {
  command = plan

  variables {
    initiative_directory = "tests/fixtures/initiative_ingestion/malformed-group-names-object"
  }

  expect_failures = [terraform_data.initiative_ingestion_contract]
}

run "rejects_malformed_native_group_names_element" {
  command = plan

  variables {
    native_initiatives = {
      group_names_element = {
        display_name = "Group names element"

        policy_definition_references = [
          {
            reference_id   = "member"
            definition_key = "allowed_locations"
            group_names    = [42]
          }
        ]

        policy_definition_groups = [
          {
            name         = "location_governance"
            display_name = "Location governance"
          }
        ]
      }
    }
  }

  expect_failures = [terraform_data.initiative_ingestion_contract]
}

run "rejects_malformed_json_group_names_element" {
  command = plan

  variables {
    initiative_directory = "tests/fixtures/initiative_ingestion/malformed-group-names-elements"
  }

  expect_failures = [terraform_data.initiative_ingestion_contract]
}

run "accepts_native_group_names_states" {
  command = plan

  variables {
    native_initiatives = {
      group_names_states = {
        display_name = "Group names states"

        policy_definition_references = [
          {
            reference_id   = "omitted_group_names"
            definition_key = "allowed_locations"
          },
          {
            reference_id   = "null_group_names"
            definition_key = "allowed_locations"
            group_names    = null
          },
          {
            reference_id   = "empty_group_names"
            definition_key = "allowed_locations"
            group_names    = []
          },
          {
            reference_id   = "valid_group_names"
            definition_key = "allowed_locations"
            group_names    = ["location_governance"]
          }
        ]

        policy_definition_groups = [
          {
            name         = "location_governance"
            display_name = "Location governance"
          }
        ]
      }
    }
  }

  assert {
    condition = (
      try(output.initiatives["group_names_states"].policy_definition_references[0].group_names, "absent") == "absent" &&
      output.initiatives["group_names_states"].policy_definition_references[1].group_names == null &&
      length(output.initiatives["group_names_states"].policy_definition_references[2].group_names) == 0 &&
      output.initiatives["group_names_states"].policy_definition_references[3].group_names == ["location_governance"]
    )
    error_message = "Omitted, null, empty and valid group_names states must be accepted and preserved without coercion."
  }
}

run "accepts_json_group_names_states" {
  command = plan

  variables {
    initiative_directory = "tests/fixtures/initiative_ingestion/group-names-states"
  }

  assert {
    condition = (
      try(output.initiatives["group_names_states"].policy_definition_references[0].group_names, "absent") == "absent" &&
      output.initiatives["group_names_states"].policy_definition_references[1].group_names == null &&
      length(output.initiatives["group_names_states"].policy_definition_references[2].group_names) == 0 &&
      output.initiatives["group_names_states"].policy_definition_references[3].group_names == ["location_governance"]
    )
    error_message = "Omitted, null, empty and valid group_names states must round-trip from JSON without normalisation."
  }
}

run "accepts_null_native_initiative_optional_scalars" {
  command = plan

  variables {
    native_initiatives = {
      null_optional_scalars = {
        name                = null
        display_name        = "Null optional scalars"
        description         = null
        management_group_id = null
        version             = null

        policy_definition_references = [
          {
            reference_id       = "keyed_member"
            definition_key     = "allowed_locations"
            group_names        = null
            version_constraint = null
            pinned_version     = null
          }
        ]

        policy_definition_groups = [
          {
            name         = "location_governance"
            display_name = "Location governance"
            description  = null
          }
        ]
      }
    }
  }

  assert {
    condition = (
      output.initiatives["null_optional_scalars"].name == null &&
      output.initiatives["null_optional_scalars"].description == null &&
      output.initiatives["null_optional_scalars"].management_group_id == null &&
      output.initiatives["null_optional_scalars"].version == null &&
      output.initiatives["null_optional_scalars"].policy_definition_references[0].group_names == null &&
      output.initiatives["null_optional_scalars"].policy_definition_groups[0].description == null
    )
    error_message = "Supplied null optional scalars must be preserved as null rather than defaulted."
  }
}

run "accepts_null_json_initiative_optional_scalars" {
  command = plan

  variables {
    initiative_directory = "tests/fixtures/initiative_ingestion/null-optional-scalars"
  }

  assert {
    condition = (
      output.initiatives["null_optional_scalars"].name == null &&
      output.initiatives["null_optional_scalars"].description == null &&
      output.initiatives["null_optional_scalars"].management_group_id == null &&
      output.initiatives["null_optional_scalars"].version == null &&
      output.initiatives["null_optional_scalars"].policy_definition_references[0].group_names == null &&
      output.initiatives["null_optional_scalars"].policy_definition_groups[0].description == null
    )
    error_message = "Supplied null optional scalars must round-trip from JSON as null rather than being defaulted."
  }
}

run "rejects_whitespace_native_initiative_key" {
  command = plan

  variables {
    native_initiatives = {
      " whitespace_key " = {
        display_name = "Whitespace key"

        policy_definition_references = [
          {
            reference_id   = "member"
            definition_key = "allowed_locations"
          }
        ]
      }
    }
  }

  expect_failures = [terraform_data.initiative_ingestion_contract]
}

run "rejects_whitespace_json_initiative_key" {
  command = plan

  variables {
    initiative_directory = "tests/fixtures/initiative_ingestion/whitespace-key"
  }

  expect_failures = [terraform_data.initiative_ingestion_contract]
}

run "rejects_numeric_json_initiative_key" {
  command = plan

  variables {
    initiative_directory = "tests/fixtures/initiative_ingestion/numeric-key"
  }

  expect_failures = [terraform_data.initiative_ingestion_contract]
}

run "rejects_cross_source_whitespace_key_variant" {
  command = plan

  variables {
    initiative_directory = "tests/fixtures/initiative_ingestion/valid"

    native_initiatives = {
      "security_baseline " = {
        display_name = "Whitespace-padded collision"

        policy_definition_references = [
          {
            reference_id   = "allowed_locations"
            definition_key = "allowed_locations"
          }
        ]
      }
    }
  }

  expect_failures = [terraform_data.initiative_ingestion_contract]
}
