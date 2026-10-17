mock_provider "azurerm" {}

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

run "create_initiative_state" {
  command   = apply
  state_key = "targeted-guard"
  assert {
    condition     = length(output.initiatives) == 1
    error_message = "The isolated fixture must manage one initiative before testing its target guard."
  }
}

run "targeted_invalid_members_block_existing_state" {
  command   = plan
  state_key = "targeted-guard"
  plan_options { target = [azurerm_policy_set_definition.subscription] }
  variables {
    initiatives = {
      baseline = {
        name                         = "baseline"
        display_name                 = "Baseline"
        policy_definition_references = null
      }
    }
  }
  expect_failures = [terraform_data.initiative_ingestion_contract]
}

run "failed_targeted_plan_retains_initiative_identity" {
  command   = plan
  state_key = "targeted-guard"
  assert {
    condition     = azurerm_policy_set_definition.subscription["baseline"].id == run.create_initiative_state.initiative_ids["baseline"]
    error_message = "A rejected targeted plan must leave the existing managed initiative identity available in the unchanged state."
  }
}
