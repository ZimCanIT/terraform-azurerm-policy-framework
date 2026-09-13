mock_provider "azurerm" {
  override_during = plan

  mock_resource "azurerm_policy_definition" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyDefinitions/mock"
    }
  }
}

run "normalizes_mixed_definitions" {
  command = plan

  variables {
    definitions = {
      allowed_locations = {
        source_type          = "built_in"
        policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c"
        display_name         = "Allowed locations"
        mode                 = "Indexed"
        supported_effects    = ["Audit", "Deny", "Disabled"]
        version_constraint   = "1.*.*"
      }

      require_cost_centre_tag = {
        source_type  = "custom"
        display_name = "Require cost centre tag"
        metadata = {
          category = "Tags"
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
        supported_effects = ["Audit", "Disabled"]
        version           = "1.0.0"
      }
    }
  }

  assert {
    condition     = output.definitions["allowed_locations"].id == "/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c"
    error_message = "Built-in definition IDs must pass through unchanged."
  }

  assert {
    condition     = output.definitions["require_cost_centre_tag"].metadata.version == "1.0.0"
    error_message = "Custom versions must be synchronized into metadata."
  }

  assert {
    condition     = output.definitions["require_cost_centre_tag"].name == "require_cost_centre_tag"
    error_message = "A custom definition without name must use its stable catalogue key."
  }

  assert {
    condition     = output.definitions["require_cost_centre_tag"].mode == "All"
    error_message = "A custom definition without mode must use the canonical All default."
  }

  assert {
    condition = (
      length(keys(output.definitions["require_cost_centre_tag"].parameters)) == 0 &&
      length(output.definitions["require_cost_centre_tag"].role_definition_ids) == 0
    )
    error_message = "A custom definition without parameters or role IDs must keep the {} and [] resource defaults."
  }

  assert {
    condition     = keys(output.custom_definition_ids) == ["require_cost_centre_tag"] && keys(output.built_in_definition_ids) == ["allowed_locations"]
    error_message = "Filtered ID outputs must preserve the custom/built-in boundary."
  }
}

run "preserves_capability_and_governance_fields" {
  command = plan

  variables {
    definitions = {
      allowed_locations = {
        source_type          = "built_in"
        policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c"
        display_name         = "Allowed locations"
        version_constraint   = "1.*.*"

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
        }
      }

      require_cost_centre_tag = {
        source_type  = "custom"
        display_name = "Require cost centre tag"

        capabilities = {
          supportsRemediation = false
        }

        governance = {
          requirement_id = "REQ-002"
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

        version = "1.0.0"
      }
    }
  }

  assert {
    condition = (
      output.definitions["allowed_locations"].supported_overrides == [{ kind = "policyEffect", value = "Disabled" }] &&
      output.definitions["allowed_locations"].selectors == [{ kind = "resourceLocation", in = ["eastus"] }] &&
      output.definitions["allowed_locations"].non_compliance_messages.default == "The control is not compliant."
    )
    error_message = "Built-in capability declarations must pass through the definitions output unchanged."
  }

  assert {
    condition = (
      output.definitions["allowed_locations"].capabilities.supportsIdentity == true &&
      output.definitions["allowed_locations"].capabilities.supportsRemediation == false &&
      output.definitions["allowed_locations"].governance.requirement_id == "REQ-001"
    )
    error_message = "Built-in capability and governance declarations must be preserved verbatim."
  }

  assert {
    condition = (
      output.definitions["require_cost_centre_tag"].capabilities.supportsRemediation == false &&
      output.definitions["require_cost_centre_tag"].governance.requirement_id == "REQ-002"
    )
    error_message = "Custom capability and governance declarations must be preserved verbatim."
  }

  assert {
    condition = (
      output.definitions["require_cost_centre_tag"].supported_effects == null &&
      output.definitions["require_cost_centre_tag"].supported_overrides == null &&
      output.definitions["require_cost_centre_tag"].selectors == null &&
      output.definitions["require_cost_centre_tag"].non_compliance_messages == null
    )
    error_message = "Absent capability declarations must remain null on the definitions output."
  }
}

run "preserves_supported_effects_unknown_state" {
  command = plan

  variables {
    definitions = {
      unknown_effects = {
        source_type          = "built_in"
        policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c"
        display_name         = "Unknown effects"
        version_constraint   = "1.*.*"
      }

      verified_no_effects = {
        source_type          = "built_in"
        policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c"
        display_name         = "Verified no effects"
        supported_effects    = []
        version_constraint   = "1.*.*"
      }

      supplied_effects = {
        source_type          = "built_in"
        policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c"
        display_name         = "Supplied effects"
        supported_effects    = ["Audit", "Deny"]
        version_constraint   = "1.*.*"
      }
    }
  }

  assert {
    condition     = output.definitions["unknown_effects"].supported_effects == null
    error_message = "An absent supported_effects declaration must remain null (unknown) on the definitions output."
  }

  assert {
    condition = (
      output.definitions["verified_no_effects"].supported_effects != null &&
      length(output.definitions["verified_no_effects"].supported_effects) == 0
    )
    error_message = "An explicitly empty supported_effects list must remain an empty list (verified absence), not null."
  }

  assert {
    condition     = join(",", output.definitions["supplied_effects"].supported_effects) == "Audit,Deny"
    error_message = "A supplied supported_effects list must pass through unchanged."
  }
}

run "preserves_built_in_capability_unknown_state" {
  command = plan

  variables {
    definitions = {
      unknown_capability = {
        source_type          = "built_in"
        policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c"
        display_name         = "Unknown capability"
        version_constraint   = "1.*.*"
      }

      verified_empty_capability = {
        source_type          = "built_in"
        policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c"
        display_name         = "Verified empty capability"
        parameters           = {}
        role_definition_ids  = []
        version_constraint   = "1.*.*"
      }

      supplied_capability = {
        source_type          = "built_in"
        policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c"
        display_name         = "Supplied capability"
        mode                 = "Indexed"
        parameters = {
          listOfAllowedLocations = {
            type = "Array"
          }
        }
        role_definition_ids = ["/providers/Microsoft.Authorization/roleDefinitions/33333333-3333-3333-3333-333333333333"]
        version_constraint  = "1.*.*"
      }
    }
  }

  assert {
    condition = (
      output.definitions["unknown_capability"].mode == null &&
      output.definitions["unknown_capability"].parameters == null &&
      output.definitions["unknown_capability"].role_definition_ids == null
    )
    error_message = "Omitted built-in mode, parameters and role IDs must remain null (unknown), not the custom resource defaults."
  }

  assert {
    condition = (
      output.definitions["verified_empty_capability"].parameters != null &&
      length(keys(output.definitions["verified_empty_capability"].parameters)) == 0 &&
      output.definitions["verified_empty_capability"].role_definition_ids != null &&
      length(output.definitions["verified_empty_capability"].role_definition_ids) == 0
    )
    error_message = "Explicitly empty built-in parameters and role IDs must remain verified absence, not null."
  }

  assert {
    condition = (
      output.definitions["supplied_capability"].mode == "Indexed" &&
      output.definitions["supplied_capability"].parameters.listOfAllowedLocations.type == "Array" &&
      join(",", output.definitions["supplied_capability"].role_definition_ids) == "/providers/Microsoft.Authorization/roleDefinitions/33333333-3333-3333-3333-333333333333"
    )
    error_message = "Supplied built-in mode, parameters and role IDs must be preserved."
  }
}

run "rejects_invalid_declaration_container_shapes" {
  command = plan

  variables {
    definitions = {
      invalid_custom = {
        source_type         = "custom"
        display_name        = "Invalid custom"
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

  expect_failures = [var.definitions]
}

run "rejects_invalid_version_wildcard" {
  command = plan

  variables {
    definitions = {
      invalid_version = {
        source_type          = "built_in"
        policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c"
        display_name         = "Invalid version"
        version_constraint   = "1.*.3"
      }
    }
  }

  expect_failures = [var.definitions]
}

run "rejects_unknown_or_misplaced_fields" {
  command = plan

  variables {
    definitions = {
      invalid_custom = {
        source_type          = "custom"
        policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c"
        display_name         = "Invalid custom"
        version              = "1.0.0"
        unexpected           = true
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

  expect_failures = [var.definitions]
}

run "rejects_invalid_custom_scope_and_missing_version" {
  command = plan

  variables {
    definitions = {
      invalid_custom = {
        source_type         = "custom"
        display_name        = "Invalid custom"
        management_group_id = "/managementGroups/not-an-arm-id"
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

  expect_failures = [var.definitions]
}
