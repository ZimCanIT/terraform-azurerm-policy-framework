mock_provider "azurerm" {}

variables {
  definitions = {
    typed = {
      source_type          = "built_in"
      display_name         = "Typed"
      policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
      version_constraint   = "1.0.*"
      parameters           = { text = { type = "String", defaultValue = "default" } }
    }
  }
}

run "independent_initiative_members_preserve_literal_binding_and_absent_mappings" {
  command = plan
  variables {
    initiatives = {
      literal = {
        display_name = "Literal"
        policy_definition_references = [{
          reference_id     = "shared-reference"
          definition_key   = "typed"
          parameter_values = { text = { value = "literal" } }
        }]
      }
      binding = {
        display_name = "Binding"
        parameters   = { setText = { type = "String" } }
        policy_definition_references = [{
          reference_id     = "shared-reference"
          definition_key   = "typed"
          parameter_values = { text = { value = "[parameters('setText')]" } }
        }]
      }
      absent = {
        display_name = "Absent"
        policy_definition_references = [{
          reference_id   = "shared-reference"
          definition_key = "typed"
        }]
      }
    }
  }
  assert {
    condition = (
      output.initiatives["literal"].policy_definition_references[0].parameter_values.text.value == "literal" &&
      output.initiatives["binding"].policy_definition_references[0].parameter_values.text.value == "[parameters('setText')]" &&
      output.initiatives["absent"].policy_definition_references[0].parameter_values == null
    )
    error_message = "Members with the same reference ID in separate initiatives must preserve their own literal, binding and absent mapping contracts."
  }
}

run "management_group_members_preserve_heterogeneous_mappings" {
  command = plan
  variables {
    initiatives = {
      literal = {
        display_name        = "Literal"
        management_group_id = "/providers/Microsoft.Management/managementGroups/platform"
        policy_definition_references = [{
          reference_id     = "shared-reference"
          definition_key   = "typed"
          parameter_values = { text = { value = "literal" } }
        }]
      }
      binding = {
        display_name        = "Binding"
        management_group_id = "/providers/Microsoft.Management/managementGroups/platform"
        parameters          = { setText = { type = "String" } }
        policy_definition_references = [{
          reference_id     = "shared-reference"
          definition_key   = "typed"
          parameter_values = { text = { value = "[parameters('setText')]" } }
        }]
      }
      absent = {
        display_name        = "Absent"
        management_group_id = "/providers/Microsoft.Management/managementGroups/platform"
        policy_definition_references = [{
          reference_id   = "shared-reference"
          definition_key = "typed"
        }]
      }
    }
  }
  assert {
    condition = (
      output.initiatives["literal"].policy_definition_references[0].parameter_values.text.value == "literal" &&
      output.initiatives["binding"].policy_definition_references[0].parameter_values.text.value == "[parameters('setText')]" &&
      output.initiatives["absent"].policy_definition_references[0].parameter_values == null
    )
    error_message = "Members with the same reference ID in separate initiatives must preserve their own literal, binding and absent mapping contracts."
  }
}

run "one_invalid_binding_still_blocks_among_independent_members" {
  command = plan
  variables {
    initiatives = {
      valid = {
        display_name = "Valid"
        policy_definition_references = [{
          reference_id     = "shared-reference"
          definition_key   = "typed"
          parameter_values = { text = { value = "literal" } }
        }]
      }
      invalid = {
        display_name = "Invalid"
        parameters   = { setText = { type = "String" } }
        policy_definition_references = [{
          reference_id     = "shared-reference"
          definition_key   = "typed"
          parameter_values = { text = { value = "[parameters('missing')]" } }
        }]
      }
    }
  }
  expect_failures = [terraform_data.initiative_ingestion_contract]
}
