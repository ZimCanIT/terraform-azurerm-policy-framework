mock_provider "azurerm" {}

run "accepts_strict_typed_literals_and_array_element_allowlist" {
  command = plan

  variables {
    definitions = {
      typed = {
        source_type = "built_in"
        id          = "/providers/Microsoft.Authorization/policyDefinitions/typed"
        parameters = {
          text    = { type = "String", defaultValue = "ready" }
          list    = { type = "Array", allowedValues = ["eastus", "westus"], defaultValue = ["eastus"] }
          object  = { type = "Object", defaultValue = { nested = [true, 1] } }
          enabled = { type = "Boolean", defaultValue = true }
          count   = { type = "Integer", defaultValue = 2 }
          ratio   = { type = "Float", defaultValue = 1.5 }
          date    = { type = "DateTime", defaultValue = "2026-02-28T12:30:00+01:00" }
        }
      }
    }
    initiatives = {
      typed = {
        display_name = "Typed"
        policy_definition_references = [{
          reference_id   = "typed"
          definition_key = "typed"
          parameter_values = {
            text    = { value = "ready" }
            list    = { value = ["westus", "eastus"] }
            object  = { value = { nested = [false, 2.25] } }
            enabled = { value = false }
            count   = { value = 3 }
            ratio   = { value = 1.25 }
            date    = { value = "2024-02-29T20:00:00.0000000Z" }
          }
        }]
      }
    }
  }

  assert {
    condition     = output.initiatives["typed"].policy_definition_references[0].parameter_values.list.value == ["westus", "eastus"]
    error_message = "Typed literals must preserve heterogeneous JSON values and apply Array allowedValues to each item."
  }
}

run "accepts_compatible_typed_parameter_bindings" {
  command = plan
  variables {
    definitions = { typed = {
      source_type = "built_in"
      id          = "/providers/Microsoft.Authorization/policyDefinitions/typed"
      parameters = {
        text    = { type = "String" }
        list    = { type = "Array", allowedValues = ["eastus", "westus"] }
        object  = { type = "Object" }
        enabled = { type = "Boolean" }
        count   = { type = "Integer" }
        ratio   = { type = "Float" }
        date    = { type = "DateTime" }
      }
    } }
    initiatives = { typed = {
      display_name = "Typed"
      parameters = {
        setText    = { type = "String" }
        setList    = { type = "Array", allowedValues = ["westus"] }
        setObject  = { type = "Object" }
        setEnabled = { type = "Boolean" }
        setCount   = { type = "Integer" }
        setRatio   = { type = "Integer" }
        setDate    = { type = "DateTime" }
      }
      policy_definition_references = [{
        reference_id   = "typed"
        definition_key = "typed"
        parameter_values = {
          text    = { value = "[parameters('setText')]" }
          list    = { value = "[parameters('setList')]" }
          object  = { value = "[parameters('setObject')]" }
          enabled = { value = "[parameters('setEnabled')]" }
          count   = { value = "[parameters('setCount')]" }
          ratio   = { value = "[parameters('setRatio')]" }
          date    = { value = "[parameters('setDate')]" }
        }
      }]
    } }
  }
  assert {
    condition     = output.initiatives["typed"].policy_definition_references[0].parameter_values.date.value == "[parameters('setDate')]"
    error_message = "Compatible initiative parameter bindings must be accepted and preserve their Azure expression text."
  }
}

run "rejects_fractional_integer_literal" {
  command = plan
  variables {
    definitions = { typed = {
      source_type = "built_in"
      id          = "/providers/Microsoft.Authorization/policyDefinitions/typed"
      parameters  = { count = { type = "Integer" } }
    } }
    initiatives = { typed = {
      display_name = "Typed"
      policy_definition_references = [{
        reference_id     = "typed"
        definition_key   = "typed"
        parameter_values = { count = { value = 1.5 } }
      }]
    } }
  }
  expect_failures = [terraform_data.initiative_ingestion_contract]
}

run "rejects_missing_required_member_mapping" {
  command = plan
  variables {
    definitions = { typed = {
      source_type = "built_in"
      id          = "/providers/Microsoft.Authorization/policyDefinitions/typed"
      parameters  = { required = { type = "String" } }
    } }
    initiatives = { typed = {
      display_name                 = "Typed"
      policy_definition_references = [{ reference_id = "typed", definition_key = "typed" }]
    } }
  }
  expect_failures = [terraform_data.initiative_ingestion_contract]
}

run "rejects_unknown_member_mapping_key" {
  command = plan
  variables {
    definitions = { typed = {
      source_type = "built_in"
      id          = "/providers/Microsoft.Authorization/policyDefinitions/typed"
      parameters  = { known = { type = "String", defaultValue = "x" } }
    } }
    initiatives = { typed = {
      display_name = "Typed"
      policy_definition_references = [{
        reference_id     = "typed"
        definition_key   = "typed"
        parameter_values = { unknown = { value = "x" } }
      }]
    } }
  }
  expect_failures = [terraform_data.initiative_ingestion_contract]
}

run "rejects_undefined_parameter_binding" {
  command = plan
  variables {
    definitions = { typed = {
      source_type = "built_in"
      id          = "/providers/Microsoft.Authorization/policyDefinitions/typed"
      parameters  = { text = { type = "String" }, count = { type = "Integer" } }
    } }
    initiatives = { typed = {
      display_name = "Typed"
      parameters   = { setCount = { type = "Integer" } }
      policy_definition_references = [{
        reference_id   = "typed"
        definition_key = "typed"
        parameter_values = {
          text  = { value = "[parameters('does-not-exist')]" }
          count = { value = "[parameters('setCount')]" }
        }
      }]
    } }
  }
  expect_failures = [terraform_data.initiative_ingestion_contract]
}

run "rejects_mismatched_parameter_binding" {
  command = plan
  variables {
    definitions = { typed = {
      source_type = "built_in"
      id          = "/providers/Microsoft.Authorization/policyDefinitions/typed"
      parameters  = { text = { type = "String" } }
    } }
    initiatives = { typed = {
      display_name = "Typed"
      parameters   = { setCount = { type = "Integer" } }
      policy_definition_references = [{
        reference_id   = "typed"
        definition_key = "typed"
        parameter_values = {
          text = { value = "[parameters('setCount')]" }
        }
      }]
    } }
  }
  expect_failures = [terraform_data.initiative_ingestion_contract]
}
