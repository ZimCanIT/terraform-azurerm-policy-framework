mock_provider "azurerm" {
  override_during = plan

  mock_resource "azurerm_policy_definition" {
    defaults = {
      id = "/providers/Microsoft.Management/managementGroups/platform/providers/Microsoft.Authorization/policyDefinitions/scoped"
    }
  }

  mock_resource "azurerm_policy_set_definition" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policySetDefinitions/mock"
    }
  }

  mock_resource "azurerm_management_group_policy_set_definition" {
    defaults = {
      id = "/providers/Microsoft.Management/managementGroups/example/providers/Microsoft.Authorization/policySetDefinitions/mock"
    }
  }
}

run "preserves_member_version_and_empty_state" {
  command = plan

  variables {
    definitions = {
      allowed = {
        source_type          = "built_in"
        display_name         = "Allowed"
        policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
        parameters           = { memberSetting = { type = "String" } }
        role_definition_ids  = []
        version_constraint   = "1.0.*"
      }
    }
    initiatives = {
      baseline = {
        name                     = "baseline"
        display_name             = "Baseline"
        description              = "Baseline"
        version                  = "9.0.0"
        metadata                 = {}
        parameters               = { setSetting = { type = "String" } }
        policy_definition_groups = []
        management_group_id      = null
        policy_definition_references = [{
          reference_id       = "allowed"
          definition_key     = "allowed"
          parameter_values   = { memberSetting = { value = "setSetting" } }
          group_names        = []
          version_constraint = "1.0.*"
        }]
      }
    }
  }

  assert {
    condition     = output.initiatives["baseline"].policy_definition_references[0].reference_id == "allowed" && output.initiatives["baseline"].policy_definition_references[0].resource_version == "1.0.*" && output.initiatives["baseline"].policy_definition_references[0].parameter_values == { memberSetting = { value = "setSetting" } }
    error_message = "Initiative outputs must preserve member identity, exact version intent and explicit parameter mappings."
  }

  assert {
    condition = (
      output.initiatives["baseline"].parameters == { setSetting = { type = "String" } } &&
      output.initiatives["baseline"].parameter_schema == { setSetting = { type = "String" } } &&
      output.initiatives["baseline"].version == "9.0.0" &&
      output.initiatives["baseline"].policy_definition_references[0].parameter_schema == { memberSetting = { type = "String" } } &&
      output.initiatives["baseline"].policy_definition_references[0].selected_version == "1.0.*" &&
      output.initiatives["baseline"].policy_definition_references[0].source_type == "built_in" &&
      output.initiatives["baseline"].policy_definition_references[0].created_by_module == false &&
      length(output.initiatives["baseline"].policy_definition_references[0].role_definition_ids) == 0
    )
    error_message = "Initiative outputs must distinguish set-level parameters from member schemas and preserve member source, ownership and role metadata."
  }
}

run "rejects_missing_member_container" {
  command = plan

  variables {
    definitions = {}
    initiatives = {
      malformed = {
        name         = "malformed"
        display_name = "Malformed"
        description  = "Malformed"
      }
    }
  }

  expect_failures = [terraform_data.initiative_ingestion_contract]
}

run "rejects_null_member_container" {
  command = plan

  variables {
    definitions = {}
    initiatives = {
      malformed = {
        name                         = "malformed"
        display_name                 = "Malformed"
        description                  = "Malformed"
        policy_definition_references = null
      }
    }
  }

  expect_failures = [terraform_data.initiative_ingestion_contract]
}

run "rejects_exact_direct_pin" {
  command = plan

  variables {
    definitions = {}
    initiatives = {
      pinned = {
        name         = "pinned"
        display_name = "Pinned"
        policy_definition_references = [{
          reference_id         = "pinned"
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
          pinned_version       = "2.0.0"
        }]
      }
    }
  }

  # AzureRM cannot represent an exact member pin (major.minor[.*] only), so an
  # exact pin is deliberately rejected instead of being silently widened or dropped.
  expect_failures = [terraform_data.initiative_ingestion_contract]
}

run "rejects_missing_definition" {
  command = plan

  variables {
    definitions = {}
    initiatives = {
      missing = {
        name         = "missing"
        display_name = "Missing"
        description  = "Missing"
        policy_definition_references = [{
          reference_id   = "missing"
          definition_key = "absent"
        }]
      }
    }
  }

  expect_failures = [terraform_data.initiative_ingestion_contract]
}

run "rejects_case_insensitive_duplicate_member_references" {
  command = plan

  variables {
    definitions = {
      allowed = {
        source_type          = "built_in"
        display_name         = "Allowed"
        policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
        version_constraint   = "1.0.*"
      }
    }
    initiatives = {
      duplicate = {
        display_name = "Duplicate references"
        policy_definition_references = [
          { reference_id = "member", definition_key = "allowed" },
          { reference_id = "MEMBER", definition_key = "allowed" },
        ]
      }
    }
  }

  expect_failures = [terraform_data.initiative_ingestion_contract]
}

run "rejects_member_reference_to_unknown_group" {
  command = plan

  variables {
    definitions = {
      allowed = {
        source_type          = "built_in"
        display_name         = "Allowed"
        policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
        version_constraint   = "1.0.*"
      }
    }
    initiatives = {
      unknown_group = {
        display_name = "Unknown group"
        policy_definition_groups = [{
          name         = "declared"
          display_name = "Declared"
        }]
        policy_definition_references = [{
          reference_id   = "member"
          definition_key = "allowed"
          group_names    = ["missing"]
        }]
      }
    }
  }

  expect_failures = [terraform_data.initiative_ingestion_contract]
}

run "rejects_set_and_member_parameter_name_collision" {
  command = plan

  variables {
    definitions = {
      allowed = {
        source_type          = "built_in"
        display_name         = "Allowed"
        policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
        version_constraint   = "1.0.*"
        parameters           = { shared = { type = "String" } }
      }
    }
    initiatives = {
      collision = {
        display_name = "Parameter collision"
        parameters   = { shared = { type = "String" } }
        policy_definition_references = [{
          reference_id     = "member"
          definition_key   = "allowed"
          parameter_values = { shared = { value = "value" } }
        }]
      }
    }
  }

  expect_failures = [terraform_data.initiative_ingestion_contract]
}

run "rejects_definition_scope_mismatch" {
  command = plan

  variables {
    definitions = {
      scoped = {
        source_type         = "custom"
        display_name        = "Scoped"
        version             = "1.0.0"
        management_group_id = "/providers/Microsoft.Management/managementGroups/platform"
        policy_rule = {
          if   = { field = "type", equals = "Microsoft.Resources/subscriptions" }
          then = { effect = "audit" }
        }
      }
    }
    initiatives = {
      subscription = {
        display_name = "Subscription initiative"
        policy_definition_references = [{
          reference_id   = "member"
          definition_key = "scoped"
        }]
      }
    }
  }

  expect_failures = [terraform_data.initiative_ingestion_contract]
}

run "preserves_management_group_resource_and_member_contract" {
  command = plan

  variables {
    definitions = {
      scoped = {
        source_type         = "custom"
        display_name        = "Scoped"
        version             = "1.0.0"
        management_group_id = "/providers/Microsoft.Management/managementGroups/platform"
        parameters          = { location = { type = "String" } }
        role_definition_ids = ["/providers/Microsoft.Authorization/roleDefinitions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"]
        policy_rule = {
          if   = { field = "type", equals = "Microsoft.Resources/subscriptions" }
          then = { effect = "audit" }
        }
      }
    }
    initiatives = {
      platform = {
        display_name        = "Platform initiative"
        management_group_id = "/providers/Microsoft.Management/managementGroups/platform"
        parameters          = { locations = { type = "Array" } }
        policy_definition_references = [{
          reference_id     = "location_member"
          definition_key   = "scoped"
          parameter_values = { location = { value = "locations" } }
        }]
      }
    }
  }

  assert {
    condition = (
      output.initiatives["platform"].management_group_id == "/providers/Microsoft.Management/managementGroups/platform" &&
      output.initiatives["platform"].parameter_schema == { locations = { type = "Array" } } &&
      output.initiatives["platform"].policy_definition_references[0].parameter_schema == { location = { type = "String" } } &&
      output.initiatives["platform"].policy_definition_references[0].source_type == "custom" &&
      output.initiatives["platform"].policy_definition_references[0].created_by_module == true &&
      [for id in output.initiatives["platform"].policy_definition_references[0].role_definition_ids : id] == ["/providers/Microsoft.Authorization/roleDefinitions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"]
    )
    error_message = "Management-group initiative output must preserve its resource scope and the distinct member/set contract fields."
  }
}

# Container boundary diagnostics: null and scalar inputs must fail at the variable boundary with the contract message.
run "definitions_null" {
  command = plan
  variables {
    definitions = null
  }
  expect_failures = [var.definitions]
}

run "definitions_scalar" {
  command = plan
  variables {
    definitions = 42
  }
  expect_failures = [var.definitions]
}

run "initiatives_null" {
  command = plan
  variables {
    initiatives = null
  }
  expect_failures = [var.initiatives]
}

run "initiatives_scalar" {
  command = plan
  variables {
    initiatives = 42
  }
  expect_failures = [var.initiatives]
}
