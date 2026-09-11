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
    condition     = keys(output.custom_definition_ids) == ["require_cost_centre_tag"] && keys(output.built_in_definition_ids) == ["allowed_locations"]
    error_message = "Filtered ID outputs must preserve the custom/built-in boundary."
  }
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
