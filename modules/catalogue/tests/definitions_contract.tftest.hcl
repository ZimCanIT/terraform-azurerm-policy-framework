run "hands_native_hcl_to_definitions_without_catalogue_fields" {
  command = plan

  variables {
    native_definitions = {
      allowed_locations = {
        source_type          = "built_in"
        display_name         = "Allowed locations"
        policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c"
        version_constraint   = "1.*.*"
        supported_effects    = ["Audit", "Deny", "Disabled"]
      }
    }
  }

  assert {
    condition     = output.definitions["allowed_locations"].policy_definition_id == "/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c"
    error_message = "Catalogue must preserve the definition ID required by modules/definitions."
  }

  assert {
    condition     = output.definitions["allowed_locations"].version_constraint == "1.*.*"
    error_message = "Catalogue must preserve explicit built-in version intent."
  }
}

run "merges_json_and_native_entries_for_definitions" {
  command = plan

  variables {
    native_definitions = {
      allowed_locations = {
        source_type          = "built_in"
        display_name         = "Allowed locations"
        policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c"
        version_constraint   = "1.*.*"
      }
    }

    custom_definition_directory = "tests/fixtures/json_ingestion/custom"
  }

  assert {
    condition     = keys(output.definitions) == ["allowed_locations", "require_cost_centre_tag"]
    error_message = "The definitions hand-off must combine native HCL and JSON entries under their stable keys."
  }

  assert {
    condition     = output.definitions["require_cost_centre_tag"].policy_rule.then.effect == "audit"
    error_message = "The definitions hand-off must retain structured JSON policy rules."
  }
}

run "preserves_native_capability_and_governance_declarations" {
  command = plan

  variables {
    native_definitions = {
      governed_control = {
        source_type  = "custom"
        display_name = "Governed control"
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
          default = "The control is not compliant."
        }

        capabilities = {
          supportsIdentity    = true
          supportsRemediation = false
        }

        governance = {
          requirement_id = "REQ-001"
          owner          = "platform-team"
          rationale      = "Synthetic governance declaration."
          review_date    = "2026-12-31"
        }

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
    condition     = output.definitions["governed_control"].supported_effects == ["Audit", "Disabled"]
    error_message = "Supported effects must be preserved for downstream definitions validation."
  }

  assert {
    condition     = output.definitions["governed_control"].supported_overrides == [{ kind = "policyEffect", value = "Disabled" }]
    error_message = "Supported overrides must be preserved verbatim on the definitions hand-off."
  }

  assert {
    condition     = output.definitions["governed_control"].selectors == [{ kind = "resourceLocation", in = ["eastus"] }]
    error_message = "Selectors must be preserved verbatim on the definitions hand-off."
  }

  assert {
    condition     = output.definitions["governed_control"].non_compliance_messages.default == "The control is not compliant."
    error_message = "Non-compliance message declarations must be preserved verbatim."
  }

  assert {
    condition     = output.definitions["governed_control"].capabilities.supportsIdentity == true && output.definitions["governed_control"].capabilities.supportsRemediation == false
    error_message = "Capability declarations must be preserved verbatim, including false values."
  }

  assert {
    condition     = output.definitions["governed_control"].governance.requirement_id == "REQ-001" && output.definitions["governed_control"].governance.review_date == "2026-12-31"
    error_message = "Governance declarations must be preserved verbatim."
  }
}

run "distinguishes_unknown_from_verified_absence" {
  command = plan

  variables {
    native_definitions = {
      unknown_capability = {
        source_type  = "custom"
        display_name = "Unknown capability"
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

      verified_absent = {
        source_type             = "custom"
        display_name            = "Verified absence"
        version                 = "1.0.0"
        supported_overrides     = []
        selectors               = []
        non_compliance_messages = {}
        capabilities            = {}
        governance              = {}
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
      output.definitions["unknown_capability"].supported_overrides == null &&
      output.definitions["unknown_capability"].selectors == null &&
      output.definitions["unknown_capability"].non_compliance_messages == null &&
      output.definitions["unknown_capability"].capabilities == null &&
      output.definitions["unknown_capability"].governance == null
    )
    error_message = "Absent capability declarations must remain null to mean unknown."
  }

  assert {
    condition = (
      output.definitions["verified_absent"].capabilities != null &&
      length(keys(output.definitions["verified_absent"].capabilities)) == 0 &&
      output.definitions["verified_absent"].governance != null &&
      length(keys(output.definitions["verified_absent"].governance)) == 0 &&
      length(output.definitions["verified_absent"].supported_overrides) == 0 &&
      length(output.definitions["verified_absent"].selectors) == 0
    )
    error_message = "Explicitly empty capability declarations must remain empty collections to mean verified absence."
  }
}

run "rejects_case_insensitive_cross_source_key_collisions" {
  command = plan

  variables {
    native_definitions = {
      ALLOWED_LOCATIONS = {
        source_type          = "built_in"
        display_name         = "Allowed locations"
        policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c"
        version_constraint   = "1.*.*"
      }
    }

    built_in_reference_directory = "tests/fixtures/json_ingestion/built-in"
  }

  expect_failures = [output.definitions]
}
