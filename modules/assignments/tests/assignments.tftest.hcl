mock_provider "azurerm" {
  override_during = plan

  mock_resource "azurerm_management_group_policy_assignment" {
    defaults = {
      id = "/providers/Microsoft.Management/managementGroups/example/providers/Microsoft.Authorization/policyAssignments/mock-mg"
    }
  }

  mock_resource "azurerm_subscription_policy_assignment" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000001/providers/Microsoft.Authorization/policyAssignments/mock-sub"
    }
  }

  mock_resource "azurerm_resource_group_policy_assignment" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/example/providers/Microsoft.Authorization/policyAssignments/mock-rg"
    }
  }

  mock_resource "azurerm_resource_policy_assignment" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/example/providers/Microsoft.Storage/storageAccounts/example/providers/Microsoft.Authorization/policyAssignments/mock-resource"
    }
  }
}

run "creates_typed_scopes_and_projects_controls" {
  command = plan

  variables {
    assignments = {
      management_group = {
        intent = {
          target                  = { reference_id = "platform-baseline" }
          scope                   = { type = "management_group", id = "/providers/Microsoft.Management/managementGroups/example" }
          enforcement_mode        = "DoNotEnforce"
          selectors               = [{ kind = "resourceLocation", in = ["westeurope"] }]
          overrides               = [{ value = "Audit", selectors = [{ kind = "resourceLocation", in = ["westeurope"] }] }]
          non_compliance_messages = [{ content = "Review the baseline." }]
        }
        resolved = {
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/platform"
          parameter_schema = {
            effect = { type = "String", defaultValue = "Audit", allowedValues = ["Audit", "Deny"] }
          }
          parameter_values = {}
          identity         = { required = false, strategy = "none" }
          required_roles   = []
          capabilities     = {}
          list_fields      = { selectors = [{ kind = "resourceLocation" }], supported_overrides = [{ kind = "policyEffect", value = "Audit" }], non_compliance_messages = { default = "Review the baseline." } }

        }
      }
      subscription = {
        intent = {
          target     = { reference_id = "subscription-policy" }
          scope      = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000001" }
          exclusions = ["/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/not-scopes"]
        }
        resolved = {
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/subscription"
          parameter_schema     = {}
          parameter_values     = {}
          identity             = { required = false, strategy = "none" }
          required_roles       = []
        }
      }
      resource_group = {
        intent = {
          target = { reference_id = "resource-group-policy" }
          scope  = { type = "resource_group", id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/example" }
        }
        resolved = {
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/resource-group"
          parameter_schema     = {}
          parameter_values     = {}
          identity             = { required = false, strategy = "none" }
          required_roles       = []
        }
      }
      resource = {
        intent = {
          target = { reference_id = "resource-policy" }
          scope  = { type = "resource", id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/example/providers/Microsoft.Storage/storageAccounts/example" }
        }
        resolved = {
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/resource"
          parameter_schema     = {}
          parameter_values     = {}
          identity             = { required = false, strategy = "none" }
          required_roles       = []
        }
      }
    }
  }

  assert {
    condition     = length(output.assignments) == 4 && keys(output.management_group_policy_assignment_ids) == ["management_group"] && keys(output.subscription_policy_assignment_ids) == ["subscription"] && keys(output.resource_group_policy_assignment_ids) == ["resource_group"] && keys(output.resource_policy_assignment_ids) == ["resource"]
    error_message = "Each typed assignment scope must create its matching provider resource and ID output."
  }

  assert {
    condition     = output.assignments["management_group"].target_reference_id == "platform-baseline" && output.assignments["management_group"].target_policy_definition_id == "/providers/Microsoft.Authorization/policyDefinitions/platform" && output.assignments["management_group"].scope.type == "management_group" && output.assignments["management_group"].scope.id == "/providers/Microsoft.Management/managementGroups/example"
    error_message = "Canonical assignment output must preserve the target and typed scope fields."
  }

  assert {
    condition     = output.assignments["management_group"].parameters == {} && output.assignments["management_group"].selectors[0].kind == "resourceLocation" && output.assignments["management_group"].selectors[0].in == ["westeurope"] && output.assignments["management_group"].overrides[0].value == "Audit" && output.assignments["management_group"].overrides[0].selectors[0].kind == "resourceLocation" && output.assignments["management_group"].non_compliance_messages[0].content == "Review the baseline."
    error_message = "Assignment parameters and controls must remain in the canonical output."
  }

  assert {
    condition     = output.assignments["management_group"].enforcement_mode == "DoNotEnforce" && output.assignments["management_group"].exclusions == null && output.assignments["management_group"].identity_binding == null && output.assignments["management_group"].created_by_module
    error_message = "Canonical assignment output must preserve enforcement, null controls and provenance."
  }

  assert {
    condition     = output.assignments["subscription"].exclusions == ["/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/not-scopes"]
    error_message = "Nested intent exclusions must project into the canonical assignment output."
  }

  assert {
    condition = output.assignments["management_group"].replacement_review.name_changes_force_replacement && output.assignments["management_group"].replacement_review.scope_changes_force_replacement && output.assignments["management_group"].replacement_review.target_changes_force_replacement && output.assignments["management_group"].replacement_review.identity_location_changes_force_replacement && output.assignments["management_group"].replacement_review.review_required_for == ["name", "scope", "target.policy_definition_id", "identity.location", "identity.resource_group_name"] && output.assignment_names["management_group"] == output.assignments["management_group"].name && output.assignments["management_group"].assignment.name == output.assignments["management_group"].name

    error_message = "Assignment names and replacement review must be deterministic and consistent."
  }

  assert {
    condition     = output.assignments["subscription"].replacement_review.name_basis == output.assignments["subscription"].name && output.assignment_names["subscription"] == output.assignments["subscription"].name
    error_message = "A short key, scope and reference ID must yield a name equal to its own basis, so the name is reproducible from the inputs alone."
  }

  assert {
    condition     = output.assignments["subscription"].selectors == null && output.assignments["subscription"].overrides == null && output.assignments["subscription"].non_compliance_messages == null && output.assignments["resource"].scope.type == "resource" && output.assignments["resource_group"].scope.type == "resource_group"
    error_message = "Undeclared controls must remain null in the canonical output and every typed scope must survive the resolved-assignment consumer boundary."
  }
}

run "initiative_target_payload_carries_only_intent_parameters" {
  command = plan

  variables {
    assignments = {
      initiative_member = {
        intent = {
          target     = { reference_id = "modify-member", initiative_key = "baseline" }
          scope      = { type = "resource_group", id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/example" }
          parameters = { governedTag = { value = "governed" } }
        }
        resolved = {
          policy_definition_id = "/subscriptions/00000000-0000-0000-0000-000000000001/providers/Microsoft.Authorization/policySetDefinitions/baseline"
          parameter_schema     = { governedTag = { type = "String", allowedValues = ["governed"] } }
          members              = [{ reference_id = "modify-member", parameter_schema = { effect = { type = "String", defaultValue = "Modify" } } }]
          parameter_values     = { governedTag = { value = "governed" } }
          identity             = { required = false, strategy = "none" }
          required_roles       = []
        }
      }
      initiative_member_no_parameters = {
        intent = {
          target = { reference_id = "modify-member", initiative_key = "baseline" }
          scope  = { type = "resource_group", id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/example" }
        }
        resolved = {
          policy_definition_id = "/subscriptions/00000000-0000-0000-0000-000000000001/providers/Microsoft.Authorization/policySetDefinitions/baseline"
          parameter_schema     = {}
          members              = [{ reference_id = "modify-member", parameter_schema = { effect = { type = "String", defaultValue = "Modify" } } }]
          parameter_values     = null
          identity             = { required = false, strategy = "none" }
          required_roles       = []
        }
      }
    }
  }

  assert {
    condition     = azurerm_resource_group_policy_assignment.this["initiative_member"].parameters == jsonencode({ governedTag = { value = "governed" } })
    error_message = "An initiative-target assignment payload must carry only intent parameters, unwrapped into the provider value form."
  }

  assert {
    condition     = azurerm_resource_group_policy_assignment.this["initiative_member_no_parameters"].parameters == null
    error_message = "An initiative-target assignment without intent parameters must carry an empty payload; member-definition defaults are never injected into a set payload."
  }
}

run "initiative_parameters_use_set_schema_and_reject_invalid_values" {
  command = plan

  variables {
    assignments = {
      missing_required = {
        intent = {
          target = { reference_id = "member-a", initiative_key = "set-a" }
          scope  = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000001" }
        }
        resolved = {
          policy_definition_id = "/subscriptions/00000000-0000-0000-0000-000000000001/providers/Microsoft.Authorization/policySetDefinitions/set-a"
          parameter_schema     = { requiredName = { type = "String" } }
          identity             = { required = false, strategy = "none" }
          required_roles       = []
        }
      }
      unknown_key = {
        intent = {
          target     = { reference_id = "member-b", initiative_key = "set-b" }
          scope      = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000001" }
          parameters = { misspelled = "value" }
        }
        resolved = {
          policy_definition_id = "/subscriptions/00000000-0000-0000-0000-000000000001/providers/Microsoft.Authorization/policySetDefinitions/set-b"
          parameter_schema     = { validName = { type = "String" } }
          identity             = { required = false, strategy = "none" }
          required_roles       = []
        }
      }
      invalid_type_and_value = {
        intent = {
          target     = { reference_id = "member-c", initiative_key = "set-c" }
          scope      = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000001" }
          parameters = { count = "not-an-integer" }
        }
        resolved = {
          policy_definition_id = "/subscriptions/00000000-0000-0000-0000-000000000001/providers/Microsoft.Authorization/policySetDefinitions/set-c"
          parameter_schema     = { count = { type = "Integer", allowedValues = [2, 4] } }
          identity             = { required = false, strategy = "none" }
          required_roles       = []
        }
      }
    }
  }

  expect_failures = [terraform_data.contract_guard]
}

run "preserves_all_azure_parameter_types_in_direct_and_initiative_payloads" {
  command = plan

  variables {
    assignments = {
      direct = {
        intent = {
          target = { reference_id = "typed-direct", policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/typed-direct" }
          scope  = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000001" }
          parameters = {
            text    = { value = "hello" }
            enabled = { value = true }
            count   = { value = 5 }
            whole   = { value = 5 }
            ratio   = { value = 5.5 }
            when    = { value = "2027-01-01T00:00:00Z" }
            items   = { value = ["text", 5, { nested = true }] }
            detail  = { value = { nested = ["text", 5], enabled = true } }
          }
        }
        resolved = {
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/typed-direct"
          parameter_schema = {
            text    = { type = "String" }
            enabled = { type = "Boolean" }
            count   = { type = "Integer", allowedValues = [5] }
            whole   = { type = "Float", allowedValues = [5] }
            ratio   = { type = "Float", allowedValues = [5.5] }
            when    = { type = "DateTime", allowedValues = ["2027-01-01T00:00:00Z"] }
            items   = { type = "Array", allowedValues = ["text", 5, { nested = true }] }
            detail  = { type = "Object" }
          }
          identity       = { required = false, strategy = "none" }
          required_roles = []
        }
      }
      initiative = {
        intent = {
          target = { reference_id = "typed-member", initiative_key = "typed-set" }
          scope  = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000001" }
          parameters = {
            count  = { value = 5 }
            ratio  = { value = 5 }
            when   = { value = "2027-01-01T00:00:00+00:00" }
            items  = { value = ["text", 5, { nested = true }] }
            detail = { value = { nested = ["text", 5], enabled = true } }
          }
        }
        resolved = {
          policy_definition_id = "/subscriptions/00000000-0000-0000-0000-000000000001/providers/Microsoft.Authorization/policySetDefinitions/typed-set"
          parameter_schema = {
            count  = { type = "Integer", allowedValues = [5] }
            ratio  = { type = "Float", allowedValues = [5] }
            when   = { type = "DateTime", allowedValues = ["2027-01-01T00:00:00+00:00"] }
            items  = { type = "Array", allowedValues = ["text", 5, { nested = true }] }
            detail = { type = "Object" }
          }
          identity       = { required = false, strategy = "none" }
          required_roles = []
        }
      }
      defaulted_array = {
        intent = {
          target = { reference_id = "default-array", policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/default-array" }
          scope  = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000001" }
        }
        resolved = {
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/default-array"
          parameter_schema = {
            items = { type = "Array", defaultValue = ["text", 5], allowedValues = ["text", 5] }
          }
          identity       = { required = false, strategy = "none" }
          required_roles = []
        }
      }
    }
  }

  assert {
    condition = azurerm_subscription_policy_assignment.this["direct"].parameters == jsonencode({
      text    = { value = "hello" }
      enabled = { value = true }
      count   = { value = 5 }
      whole   = { value = 5 }
      ratio   = { value = 5.5 }
      when    = { value = "2027-01-01T00:00:00Z" }
      items   = { value = ["text", 5, { nested = true }] }
      detail  = { value = { nested = ["text", 5], enabled = true } }
    })
    error_message = "Direct assignment JSON must preserve every Azure Policy parameter type, including heterogeneous array and nested object values."
  }

  assert {
    condition = azurerm_subscription_policy_assignment.this["initiative"].parameters == jsonencode({
      count  = { value = 5 }
      ratio  = { value = 5 }
      when   = { value = "2027-01-01T00:00:00+00:00" }
      items  = { value = ["text", 5, { nested = true }] }
      detail = { value = { nested = ["text", 5], enabled = true } }
    })
    error_message = "Initiative assignment JSON must preserve typed intent values without coercing its set namespace."
  }

  assert {
    condition = azurerm_subscription_policy_assignment.this["defaulted_array"].parameters == jsonencode({
      items = { value = ["text", 5] }
    })
    error_message = "Array defaults must be validated element-wise and projected with native JSON element types."
  }
}

run "rejects_integer_numeric_strings_in_both_parameter_namespaces" {
  command = plan

  variables {
    assignments = {
      direct = {
        intent = {
          target     = { reference_id = "string-integer", policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/string-integer" }
          scope      = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000001" }
          parameters = { count = { value = "5" } }
        }
        resolved = {
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/string-integer"
          parameter_schema     = { count = { type = "Integer", allowedValues = [5] } }
          identity             = { required = false, strategy = "none" }
          required_roles       = []
        }
      }
      initiative = {
        intent = {
          target     = { reference_id = "member", initiative_key = "string-set" }
          scope      = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000001" }
          parameters = { count = { value = "5" } }
        }
        resolved = {
          policy_definition_id = "/subscriptions/00000000-0000-0000-0000-000000000001/providers/Microsoft.Authorization/policySetDefinitions/string-set"
          parameter_schema     = { count = { type = "Integer", allowedValues = [5] } }
          identity             = { required = false, strategy = "none" }
          required_roles       = []
        }
      }
    }
  }

  expect_failures = [terraform_data.contract_guard]
}

run "rejects_invalid_float_datetime_and_malformed_schema_types" {
  command = plan

  variables {
    assignments = {
      invalid_float = {
        intent = {
          target     = { reference_id = "invalid-float", policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/invalid-float" }
          scope      = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000001" }
          parameters = { ratio = { value = "5.5" } }
        }
        resolved = {
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/invalid-float"
          parameter_schema     = { ratio = { type = "Float" } }
          identity             = { required = false, strategy = "none" }
          required_roles       = []
        }
      }
      invalid_datetime = {
        intent = {
          target     = { reference_id = "invalid-date", policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/invalid-date" }
          scope      = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000001" }
          parameters = { when = { value = "2027-02-30T00:00:00Z" } }
        }
        resolved = {
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/invalid-date"
          parameter_schema     = { when = { type = "DateTime" } }
          identity             = { required = false, strategy = "none" }
          required_roles       = []
        }
      }
      null_schema_type = {
        intent = {
          target = { reference_id = "null-type", policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/null-type" }
          scope  = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000001" }
        }
        resolved = {
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/null-type"
          parameter_schema     = { count = { type = null } }
          identity             = { required = false, strategy = "none" }
          required_roles       = []
        }
      }
      null_schema_entry = {
        intent = {
          target = { reference_id = "null-entry", policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/null-entry" }
          scope  = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000001" }
        }
        resolved = {
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/null-entry"
          parameter_schema     = { count = null }
          identity             = { required = false, strategy = "none" }
          required_roles       = []
        }
      }
      missing_schema_type = {
        intent = {
          target = { reference_id = "missing-type", policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/missing-type" }
          scope  = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000001" }
        }
        resolved = {
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/missing-type"
          parameter_schema     = { count = {} }
          identity             = { required = false, strategy = "none" }
          required_roles       = []
        }
      }
      malformed_allowed_values = {
        intent = {
          target = { reference_id = "bad-values", policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/bad-values" }
          scope  = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000001" }
        }
        resolved = {
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/bad-values"
          parameter_schema     = { count = { type = "Integer", allowedValues = "5" } }
          identity             = { required = false, strategy = "none" }
          required_roles       = []
        }
      }
      unsupported_number_alias = {
        intent = {
          target = { reference_id = "number-alias", policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/number-alias" }
          scope  = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000001" }
        }
        resolved = {
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/number-alias"
          parameter_schema     = { count = { type = "Number" } }
          identity             = { required = false, strategy = "none" }
          required_roles       = []
        }
      }
    }
  }

  expect_failures = [terraform_data.contract_guard]
}

run "rejects_allowed_values_that_only_match_after_string_coercion" {
  command = plan

  variables {
    assignments = {
      typed_allowed = {
        intent = {
          target     = { reference_id = "typed-allowed", policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/typed-allowed" }
          scope      = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000001" }
          parameters = { count = { value = 5 } }
        }
        resolved = {
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/typed-allowed"
          parameter_schema     = { count = { type = "Integer", allowedValues = ["5"] } }
          identity             = { required = false, strategy = "none" }
          required_roles       = []
        }
      }
    }
  }

  expect_failures = [terraform_data.contract_guard]
}

run "validates_array_allowed_values_per_element_for_direct_and_initiative_targets" {
  command = plan

  variables {
    assignments = {
      direct_element = {
        intent = {
          target     = { reference_id = "array-element", policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/array-element" }
          scope      = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000001" }
          parameters = { items = { value = ["text", "denied"] } }
        }
        resolved = {
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/array-element"
          parameter_schema = {
            items = { type = "Array", allowedValues = ["text", 5] }
          }
          identity       = { required = false, strategy = "none" }
          required_roles = []
        }
      }
      initiative_default = {
        intent = {
          target = { reference_id = "array-default", initiative_key = "array-default-set" }
          scope  = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000001" }
        }
        resolved = {
          policy_definition_id = "/subscriptions/00000000-0000-0000-0000-000000000001/providers/Microsoft.Authorization/policySetDefinitions/array-default-set"
          parameter_schema = {
            items = { type = "Array", defaultValue = ["text", "denied"], allowedValues = ["text", 5] }
          }
          identity       = { required = false, strategy = "none" }
          required_roles = []
        }
      }
    }
  }

  expect_failures = [terraform_data.contract_guard]
}

run "distinguishes_unknown_and_verified_empty_parameters" {
  command = plan

  variables {
    assignments = {
      unknown = {
        intent = {
          target = { reference_id = "unknown-parameters" }
          scope  = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000001" }
        }
        resolved = {
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/unknown"
          parameter_schema     = null
          parameter_values     = null
          identity             = { required = false, strategy = "none" }
          required_roles       = []
        }
      }
      empty = {
        intent = {
          target = { reference_id = "empty-parameters" }
          scope  = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000001" }
        }
        resolved = {
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/empty"
          parameter_schema     = {}
          parameter_values     = {}
          identity             = { required = false, strategy = "none" }
          required_roles       = []
        }
      }
    }
  }

  assert {
    condition     = output.assignments["unknown"].parameters == null && output.assignments["empty"].parameters != null && length(keys(output.assignments["empty"].parameters)) == 0
    error_message = "Unknown parameter data must remain null while verified empty data remains an empty object."
  }
}

run "rejects_malformed_records_and_typed_scope_boundaries" {
  command = plan

  variables {
    assignments = {
      malformed_scope = {
        intent = {
          target = { reference_id = "malformed" }
          scope  = { type = "subscription", id = "/resourceGroups/not-a-subscription" }
        }
        resolved = {
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/invalid"
          identity             = { required = false, strategy = "none" }
          required_roles       = []
        }
      }
      malformed_selector = {
        intent = {
          target    = { reference_id = "selector" }
          scope     = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000001" }
          selectors = [{ kind = "" }]
        }
        resolved = {
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/invalid"
          identity             = { required = false, strategy = "none" }
          required_roles       = []
        }
      }
    }
  }

  expect_failures = [var.assignments]
}

run "rejects_a_resource_scope_without_a_resource_name" {
  command = plan

  # The first run accepts this assignment with a named resource, so the missing
  # resource name is the only defect.
  variables {
    assignments = {
      bare_resource_type = {
        intent = {
          target = { reference_id = "resource-policy" }
          scope  = { type = "resource", id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/example/providers/Microsoft.Storage/storageAccounts" }
        }
        resolved = {
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/resource"
          parameter_schema     = {}
          parameter_values     = {}
          identity             = { required = false, strategy = "none" }
          required_roles       = []
        }
      }
    }
  }

  expect_failures = [var.assignments]
}

run "rejects_malformed_parameter_values" {
  command = plan

  variables {
    assignments = {
      invalid_parameter = {
        intent = {
          target     = { reference_id = "invalid-parameter" }
          scope      = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000001" }
          parameters = { effect = { value = "Deny" } }
        }
        resolved = {
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/invalid-parameter"
          parameter_schema     = { effect = { type = "String", allowedValues = ["Audit"] } }
          identity             = { required = false, strategy = "none" }
          required_roles       = []
        }
      }
    }
  }

  expect_failures = [terraform_data.contract_guard]
}

run "rejects_malformed_override_values" {
  command = plan

  variables {
    assignments = {
      invalid_override = {
        intent = {
          target    = { reference_id = "invalid-override" }
          scope     = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000001" }
          overrides = [{ value = "NotAnEffect" }]
        }
        resolved = {
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/invalid-override"
          identity             = { required = false, strategy = "none" }
          required_roles       = []
        }
      }
    }
  }

  expect_failures = [terraform_data.contract_guard]
}

run "passes_effect_matching_definition_default" {
  command = plan

  variables {
    assignments = {
      matching_default = {
        intent = {
          target = { reference_id = "matching-default" }
          scope  = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000001" }
        }
        resolved = {
          policy_definition_id      = "/providers/Microsoft.Authorization/policyDefinitions/matching-default"
          effective_effect          = "Audit"
          definition_default_effect = "Audit"
          parameter_schema          = {}
          parameter_values          = {}
          identity                  = { required = false, strategy = "none" }
          required_roles            = []
        }
      }
    }
  }

  assert {
    condition     = output.assignments["matching_default"].effective_effect == "Audit" && output.assignments["matching_default"].selected_version == null
    error_message = "An effective effect equal to the definition default must plan and remain in the canonical output."
  }
}

run "rejects_unenforceable_effect_without_projection" {
  command = plan

  variables {
    assignments = {
      conflicting_effect = {
        intent = {
          target = { reference_id = "conflicting-effect" }
          scope  = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000001" }
        }
        resolved = {
          policy_definition_id      = "/providers/Microsoft.Authorization/policyDefinitions/conflicting"
          effective_effect          = "Deny"
          definition_default_effect = "Audit"
          parameter_schema          = {}
          parameter_values          = {}
          identity                  = { required = false, strategy = "none" }
          required_roles            = []
        }
      }
    }
  }

  expect_failures = [terraform_data.contract_guard]
}

run "rejects_direct_target_version_request" {
  command = plan

  variables {
    assignments = {
      direct_version = {
        intent = {
          target = {
            reference_id         = "direct-version"
            policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/direct-version"
          }
          scope = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000001" }
        }
        resolved = {
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/direct-version"
          selected_version     = "1.*.*"
          parameter_schema     = {}
          parameter_values     = {}
          identity             = { required = false, strategy = "none" }
          required_roles       = []
        }
      }
    }
  }

  expect_failures = [terraform_data.contract_guard]
}

run "rejects_direct_target_exact_pin_not_supported_by_provider_resource" {
  command = plan

  variables {
    assignments = {
      direct_pin = {
        intent = {
          target = {
            reference_id         = "direct-pin"
            policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/direct-pin"
          }
          scope = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000001" }
        }
        resolved = {
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/direct-pin"
          selected_version     = "1.0.0"
          source_version       = "1.0.0"
          parameter_schema     = {}
          parameter_values     = {}
          identity             = { required = false, strategy = "none" }
          required_roles       = []
        }
      }
    }
  }

  expect_failures = [terraform_data.contract_guard]
}

run "allows_explicit_unversioned_direct_policy_id_with_source_provenance" {
  command = plan

  variables {
    assignments = {
      unversioned = {
        intent = {
          target          = { reference_id = "unversioned", policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/unversioned" }
          scope           = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000001" }
          version_binding = "unversioned"
        }
        resolved = {
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/unversioned"
          selected_version     = null
          source_version       = "1.0.0"
          parameter_schema     = {}
          identity             = { required = false, strategy = "none" }
          required_roles       = []
        }
      }
    }
  }

  assert {
    condition     = output.assignments["unversioned"].selected_version == null && output.assignments["unversioned"].source_version == "1.0.0" && output.assignments["unversioned"].version_binding == "unversioned"
    error_message = "An explicit unversioned direct target may use its policy ID while retaining source-version provenance and no deployment claim."
  }
}

run "rejects_unversioned_binding_with_assignment_version_request" {
  command = plan

  variables {
    assignments = {
      conflict = {
        intent = {
          target             = { reference_id = "conflict", policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/conflict" }
          scope              = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000001" }
          version_binding    = "unversioned"
          version_constraint = "1.*.*"
        }
        resolved = {
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/conflict"
          selected_version     = null
          parameter_schema     = {}
          identity             = { required = false, strategy = "none" }
          required_roles       = []
        }
      }
    }
  }

  expect_failures = [var.assignments]
}

run "rejects_non_integral_integer_parameter" {
  command = plan

  variables {
    assignments = {
      fractional_integer = {
        intent = {
          target     = { reference_id = "fractional-integer" }
          scope      = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000001" }
          parameters = { count = { value = 5.5 } }
        }
        resolved = {
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/fractional"
          parameter_schema     = { count = { type = "Integer" } }
          identity             = { required = false, strategy = "none" }
          required_roles       = []
        }
      }
    }
  }

  expect_failures = [terraform_data.contract_guard]
}

run "rejects_unknown_parameter_and_invalid_override" {
  command = plan

  variables {
    assignments = {
      invalid = {
        intent = {
          target     = { reference_id = "invalid" }
          scope      = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000001" }
          parameters = { unexpected = { value = "x" } }
          overrides  = [{ value = "NotAnEffect" }]
        }
        resolved = {
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/invalid"
          parameter_schema     = { expected = { type = "String" } }
          parameter_values     = null
          identity             = { required = false, strategy = "none" }
          required_roles       = []
        }
      }
    }
  }

  expect_failures = [terraform_data.contract_guard]
}

run "rejects_flattened_legacy_parameters" {
  command = plan

  variables {
    assignments = {
      flattened_parameters = {
        intent = {
          target = { reference_id = "flattened-parameters" }
          scope  = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000001" }
        }
        resolved = {
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/flattened-parameters"
          identity             = { required = false, strategy = "none" }
          required_roles       = []
        }
        parameters = { effect = { value = "Audit" } }
      }
    }
  }

  expect_failures = [var.assignments]
}

run "rejects_flattened_legacy_selectors" {
  command = plan

  variables {
    assignments = {
      flattened_selectors = {
        intent = {
          target = { reference_id = "flattened-selectors" }
          scope  = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000001" }
        }
        resolved = {
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/flattened-selectors"
          identity             = { required = false, strategy = "none" }
          required_roles       = []
        }
        selectors = [{ kind = "resourceLocation", in = ["westeurope"] }]
      }
    }
  }

  expect_failures = [var.assignments]
}

run "rejects_flattened_legacy_overrides" {
  command = plan

  variables {
    assignments = {
      flattened_overrides = {
        intent = {
          target = { reference_id = "flattened-overrides" }
          scope  = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000001" }
        }
        resolved = {
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/flattened-overrides"
          identity             = { required = false, strategy = "none" }
          required_roles       = []
        }
        overrides = [{ value = "Audit" }]
      }
    }
  }

  expect_failures = [var.assignments]
}

run "rejects_flattened_legacy_exclusions" {
  command = plan

  variables {
    assignments = {
      flattened_exclusions = {
        intent = {
          target = { reference_id = "flattened-exclusions" }
          scope  = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000001" }
        }
        resolved = {
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/flattened-exclusions"
          identity             = { required = false, strategy = "none" }
          required_roles       = []
        }
        exclusions = ["/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/not-scopes"]
      }
    }
  }

  expect_failures = [var.assignments]
}

run "rejects_flattened_legacy_non_compliance_messages" {
  command = plan

  variables {
    assignments = {
      flattened_messages = {
        intent = {
          target = { reference_id = "flattened-messages" }
          scope  = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000001" }
        }
        resolved = {
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/flattened-messages"
          identity             = { required = false, strategy = "none" }
          required_roles       = []
        }
        non_compliance_messages = [{ content = "Flattened legacy form." }]
      }
    }
  }

  expect_failures = [var.assignments]
}

# Container boundary diagnostics: null and scalar inputs must fail at the variable boundary with the contract message.
run "assignments_null" {
  command = plan
  variables {
    assignments = null
  }
  expect_failures = [var.assignments]
}

run "assignments_scalar" {
  command = plan
  variables {
    assignments = 42
  }
  expect_failures = [var.assignments]
}

run "identity_bindings_null" {
  command = plan
  variables {
    identity_bindings = null
  }
  expect_failures = [var.identity_bindings]
}

run "identity_bindings_scalar" {
  command = plan
  variables {
    identity_bindings = 42
  }
  expect_failures = [var.identity_bindings]
}
