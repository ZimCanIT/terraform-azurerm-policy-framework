run "accepts_equivalent_native_and_json_definition_shapes" {
  command = plan

  variables {
    custom_definition_directory = "tests/fixtures/json_ingestion/companion-types"

    native_definitions = {
      native_typed = {
        source_type  = "custom"
        name         = "native-typed"
        display_name = "Native typed"
        version      = "1.0.0"

        supported_effects = ["Audit", "Disabled"]

        supported_overrides = [
          {
            kind  = "policyEffect"
            value = "Disabled"
          }
        ]

        selectors = [
          {
            kind = "resourceLocation"
            in   = ["eastus"]
          }
        ]

        non_compliance_messages = {
          default = "The synthetic control is not compliant."
        }

        capabilities = {
          supportsIdentity    = true
          supportsRemediation = false
        }

        governance = {
          requirement_id = "REQ-TAGS-001"
          owner          = "platform-team"
          rationale      = "Cost allocation for synthetic resources."
          review_date    = "2026-12-31"
        }

        policy_rule = {
          if = {
            field  = "tags['costCentre']"
            exists = "false"
          }
          then = {
            effect = "audit"
          }
        }
      }
    }
  }

  assert {
    condition = (
      output.definitions["native_typed"].capabilities == output.definitions["typed_definition"].capabilities &&
      output.definitions["native_typed"].governance == output.definitions["typed_definition"].governance &&
      output.definitions["native_typed"].supported_overrides == output.definitions["typed_definition"].supported_overrides &&
      output.definitions["native_typed"].selectors == output.definitions["typed_definition"].selectors &&
      output.definitions["native_typed"].non_compliance_messages == output.definitions["typed_definition"].non_compliance_messages
    )
    error_message = "HCL and JSON definition capability declarations must normalize to equivalent envelopes."
  }
}

run "rejects_invalid_capability_shape_from_native_definition" {
  command = plan

  variables {
    native_definitions = {
      invalid_native = {
        source_type         = "custom"
        display_name        = "Invalid native"
        version             = "1.0.0"
        supported_overrides = "not-a-list"
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
  }

  expect_failures = [terraform_data.json_ingestion_contract]
}

run "rejects_invalid_capability_shape_from_json_definition" {
  command = plan

  variables {
    custom_definition_directory = "tests/fixtures/json_ingestion/capability-shape-invalid"
  }

  expect_failures = [terraform_data.json_ingestion_contract]
}

run "rejects_unknown_json_definition_field" {
  command = plan

  variables {
    custom_definition_directory = "tests/fixtures/json_ingestion/unknown-field"
  }

  expect_failures = [terraform_data.json_ingestion_contract]
}

run "accepts_equivalent_native_and_json_initiative_shapes" {
  command = plan

  variables {
    initiative_directory = "tests/fixtures/initiative_ingestion/valid"

    native_initiatives = {
      native_security_baseline = {
        display_name = "Native security baseline"

        metadata = {
          category = "Security"
          version  = "1.0.0"
        }

        policy_definition_references = [
          {
            reference_id   = "allowed_locations"
            definition_key = "allowed_locations"

            parameter_values = {
              listOfAllowedLocations = {
                value = "[parameters('allowedLocations')]"
              }
            }

            group_names        = ["location_governance"]
            version_constraint = "1.*.*"
          },
          {
            reference_id         = "allowed_vm_skus"
            policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/cccccccc-cccc-cccc-cccc-cccccccccccc"
            pinned_version       = "2.0.0"
          }
        ]

        policy_definition_groups = [
          {
            name         = "location_governance"
            display_name = "Location governance"
          }
        ]

        version = "1.0.0"
      }
    }
  }

  assert {
    condition = (
      length(output.initiatives["native_security_baseline"].policy_definition_references) == 2 &&
      output.initiatives["native_security_baseline"].policy_definition_references[0].group_names == ["location_governance"] &&
      output.initiatives["native_security_baseline"].policy_definition_references[1].pinned_version == "2.0.0"
    )
    error_message = "Native HCL initiatives must accept the same valid member shapes as JSON initiatives."
  }

  assert {
    condition     = output.initiatives["native_security_baseline"].policy_definition_groups[0].name == output.initiatives["security_baseline"].policy_definition_groups[0].name
    error_message = "Native and JSON initiatives must normalize equivalent group records."
  }
}

run "rejects_invalid_reference_from_native_initiative" {
  command = plan

  variables {
    native_initiatives = {
      invalid_native = {
        display_name = "Invalid native"

        policy_definition_references = [
          {
            reference_id         = "ambiguous_member"
            definition_key       = "allowed_locations"
            policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/cccccccc-cccc-cccc-cccc-cccccccccccc"
          }
        ]
      }
    }
  }

  expect_failures = [terraform_data.initiative_ingestion_contract]
}

run "rejects_invalid_reference_from_json_initiative" {
  command = plan

  variables {
    initiative_directory = "tests/fixtures/initiative_ingestion/invalid-reference"
  }

  expect_failures = [terraform_data.initiative_ingestion_contract]
}

run "rejects_unknown_native_definition_field" {
  command = plan

  variables {
    native_definitions = {
      invalid_native = {
        source_type  = "custom"
        display_name = "Invalid native"
        version      = "1.0.0"
        unexpected   = true
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
  }

  expect_failures = [var.native_definitions]
}

run "rejects_empty_native_definition_envelope" {
  command = plan

  variables {
    native_definitions = {
      invalid = {}
    }
  }

  expect_failures = [terraform_data.json_ingestion_contract]
}

run "rejects_native_custom_definition_without_version" {
  command = plan

  variables {
    native_definitions = {
      missing_version = {
        source_type  = "custom"
        display_name = "Missing version"
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

run "rejects_native_custom_definition_without_policy_rule" {
  command = plan

  variables {
    native_definitions = {
      missing_rule = {
        source_type  = "custom"
        display_name = "Missing rule"
        version      = "1.0.0"
      }
    }
  }

  expect_failures = [terraform_data.json_ingestion_contract]
}

run "rejects_native_built_in_definition_without_policy_definition_id" {
  command = plan

  variables {
    native_definitions = {
      missing_id = {
        source_type        = "built_in"
        display_name       = "Missing ID"
        version_constraint = "1.*.*"
      }
    }
  }

  expect_failures = [terraform_data.json_ingestion_contract]
}

run "rejects_native_built_in_definition_with_both_version_intents" {
  command = plan

  variables {
    native_definitions = {
      dual_intent = {
        source_type          = "built_in"
        display_name         = "Dual intent"
        policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c"
        version_constraint   = "1.*.*"
        pinned_version       = "1.0.0"
      }
    }
  }

  expect_failures = [terraform_data.json_ingestion_contract]
}

run "rejects_native_definition_mixing_custom_and_built_in_fields" {
  command = plan

  variables {
    native_definitions = {
      mixed_fields = {
        source_type          = "custom"
        display_name         = "Mixed fields"
        version              = "1.0.0"
        policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c"
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

run "rejects_native_custom_definition_with_mismatched_versions" {
  command = plan

  variables {
    native_definitions = {
      mismatched_versions = {
        source_type  = "custom"
        display_name = "Mismatched versions"
        version      = "1.0.0"
        metadata = {
          version = "2.0.0"
        }
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

run "accepts_valid_native_custom_definition_envelope" {
  command = plan

  variables {
    native_definitions = {
      valid_native_custom = {
        source_type  = "custom"
        display_name = "Valid native custom"
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
  }

  assert {
    condition = (
      output.definitions["valid_native_custom"].source_type == "custom" &&
      output.definitions["valid_native_custom"].version == "1.0.0" &&
      output.definitions["valid_native_custom"].policy_rule.then.effect == "audit"
    )
    error_message = "A native custom definition with the required envelope fields must be accepted unchanged."
  }
}

run "accepts_valid_native_built_in_definition_envelope" {
  command = plan

  variables {
    native_definitions = {
      valid_native_built_in = {
        source_type          = "built_in"
        display_name         = "Valid native built-in"
        policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c"
        version_constraint   = "1.*.*"
      }
    }
  }

  assert {
    condition = (
      output.definitions["valid_native_built_in"].source_type == "built_in" &&
      output.definitions["valid_native_built_in"].policy_definition_id == "/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c" &&
      output.definitions["valid_native_built_in"].version_constraint == "1.*.*"
    )
    error_message = "A native built-in reference with the required envelope fields must be accepted unchanged."
  }
}

run "rejects_native_non_string_initiative_entry_scalars" {
  command = plan

  variables {
    native_initiatives = {
      scalar_entry_name = {
        name         = 42
        display_name = "Scalar entry name"

        policy_definition_references = [
          {
            reference_id   = "member"
            definition_key = "allowed_locations"
          }
        ]
      }

      scalar_entry_display_name = {
        display_name = 42

        policy_definition_references = [
          {
            reference_id   = "member"
            definition_key = "allowed_locations"
          }
        ]
      }

      scalar_entry_description = {
        display_name = "Scalar entry description"
        description  = true

        policy_definition_references = [
          {
            reference_id   = "member"
            definition_key = "allowed_locations"
          }
        ]
      }

      scalar_entry_version = {
        display_name = "Scalar entry version"
        version      = 1.2

        policy_definition_references = [
          {
            reference_id   = "member"
            definition_key = "allowed_locations"
          }
        ]
      }

      scalar_entry_management_group_id = {
        display_name        = "Scalar entry management group id"
        management_group_id = ["/providers/Microsoft.Management/managementGroups/example-platform"]

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

run "rejects_json_non_string_initiative_entry_scalars" {
  command = plan

  variables {
    initiative_directory = "tests/fixtures/initiative_ingestion/scalar-entry-negatives"
  }

  expect_failures = [terraform_data.initiative_ingestion_contract]
}

run "rejects_native_non_string_initiative_member_scalars" {
  command = plan

  variables {
    native_initiatives = {
      scalar_member_reference_id = {
        display_name = "Scalar member reference id"

        policy_definition_references = [
          {
            reference_id   = 42
            definition_key = "allowed_locations"
          }
        ]
      }

      scalar_member_definition_key = {
        display_name = "Scalar member definition key"

        policy_definition_references = [
          {
            reference_id   = "member"
            definition_key = true
          }
        ]
      }

      scalar_member_policy_definition_id = {
        display_name = "Scalar member policy definition id"

        policy_definition_references = [
          {
            reference_id         = "member"
            policy_definition_id = 42
            version_constraint   = "1.*.*"
          }
        ]
      }

      scalar_member_version_constraint = {
        display_name = "Scalar member version constraint"

        policy_definition_references = [
          {
            reference_id       = "member"
            definition_key     = "allowed_locations"
            version_constraint = 1
          }
        ]
      }

      scalar_member_pinned_version = {
        display_name = "Scalar member pinned version"

        policy_definition_references = [
          {
            reference_id   = "member"
            definition_key = "allowed_locations"
            pinned_version = ["2.0.0"]
          }
        ]
      }
    }
  }

  expect_failures = [terraform_data.initiative_ingestion_contract]
}

run "rejects_json_non_string_initiative_member_scalars" {
  command = plan

  variables {
    initiative_directory = "tests/fixtures/initiative_ingestion/scalar-member-negatives"
  }

  expect_failures = [terraform_data.initiative_ingestion_contract]
}

run "rejects_native_non_string_initiative_group_scalars" {
  command = plan

  variables {
    native_initiatives = {
      scalar_group_name = {
        display_name = "Scalar group name"

        policy_definition_references = [
          {
            reference_id   = "member"
            definition_key = "allowed_locations"
          }
        ]

        policy_definition_groups = [
          {
            name         = 42
            display_name = "Scalar group name"
          }
        ]
      }

      scalar_group_display_name = {
        display_name = "Scalar group display name"

        policy_definition_references = [
          {
            reference_id   = "member"
            definition_key = "allowed_locations"
          }
        ]

        policy_definition_groups = [
          {
            name         = "location_governance"
            display_name = 42
          }
        ]
      }

      scalar_group_description = {
        display_name = "Scalar group description"

        policy_definition_references = [
          {
            reference_id   = "member"
            definition_key = "allowed_locations"
          }
        ]

        policy_definition_groups = [
          {
            name         = "location_governance"
            display_name = "Location governance"
            description  = true
          }
        ]
      }
    }
  }

  expect_failures = [terraform_data.initiative_ingestion_contract]
}

run "rejects_native_set_capability_lists" {
  command = plan

  variables {
    native_definitions = {
      set_capabilities = {
        source_type       = "custom"
        display_name      = "Set capabilities"
        version           = "1.0.0"
        supported_effects = toset(["Audit"])
        supported_overrides = toset([{
          kind = "policyEffect"
        }])
        selectors = toset([{
          kind = "resourceLocation"
        }])

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

run "rejects_native_set_initiative_lists" {
  command = plan

  variables {
    native_initiatives = {
      set_groups = {
        display_name = "Set groups"

        policy_definition_references = [
          {
            reference_id   = "member"
            definition_key = "allowed_locations"
            group_names    = toset(["location_governance"])
          }
        ]

        policy_definition_groups = toset([{
          name         = "location_governance"
          display_name = "Location governance"
        }])
      }
    }
  }

  expect_failures = [terraform_data.initiative_ingestion_contract]
}

run "rejects_json_non_string_initiative_group_scalars" {
  command = plan

  variables {
    initiative_directory = "tests/fixtures/initiative_ingestion/scalar-group-negatives"
  }

  expect_failures = [terraform_data.initiative_ingestion_contract]
}
