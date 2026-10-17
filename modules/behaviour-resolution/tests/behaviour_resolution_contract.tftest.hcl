run "resolves_effect_and_preserves_empty_lists" {
  command = plan

  variables {
    definitions = {
      policy = {
        id                  = "/providers/Microsoft.Authorization/policyDefinitions/policy"
        source_type         = "built_in"
        parameters          = {}
        supported_effects   = ["Audit"]
        capabilities        = { default_effect = "Audit" }
        role_definition_ids = []
      }
    }
    initiatives = {}
    assignments = {
      audit = {
        target = {
          reference_id   = "policy"
          definition_key = "policy"
        }
        scope = {
          type = "subscription"
          id   = "/subscriptions/00000000-0000-0000-0000-000000000000"
        }
      }
    }
  }

  assert {
    condition     = output.assignments["audit"].resolved.requested_effect == null && output.assignments["audit"].resolved.effective_effect == "Audit"
    error_message = "Behaviour resolution must preserve absent requested effect intent and derive the definition default effect."
  }

  assert {
    condition     = output.assignments["audit"].resolved.required_roles == []
    error_message = "Verified empty role declarations must remain empty through required_roles."
  }

  assert {
    condition     = length(output.assignments["audit"].resolved.list_fields.role_definition_ids) == 0
    error_message = "Verified empty role declarations must remain empty through list_fields.role_definition_ids."
  }

  assert {
    condition     = output.assignments["audit"].resolved.remediation_eligibility == "not_eligible"
    error_message = "An Audit assignment must not be marked eligible for remediation."
  }
}

run "rejects_competing_target_mechanisms" {
  command = plan

  variables {
    assignments = {
      ambiguous = {
        target = {
          reference_id         = "policy"
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/policy"
          definition_key       = "policy"
        }
        scope = {
          type = "subscription"
          id   = "/subscriptions/00000000-0000-0000-0000-000000000000"
        }
      }
    }
  }

  expect_failures = [var.assignments]
}

run "rejects_unknown_definition_reference" {
  command = plan

  variables {
    definitions = {}
    assignments = {
      unknown = {
        target = {
          reference_id   = "unknown"
          definition_key = "absent"
        }
        scope = {
          type = "subscription"
          id   = "/subscriptions/00000000-0000-0000-0000-000000000000"
        }
      }
    }
  }

  expect_failures = [terraform_data.contract_guard]
}

run "keeps_identity_and_role_decisions_known_with_provider_computed_ids" {
  command = plan

  module {
    source = "./tests/fixtures/provider-computed-ids"
  }

  assert {
    condition     = output.direct_effect == "DeployIfNotExists" && output.direct_identity_required && length(output.direct_required_roles) == 1 && output.direct_required_roles[0].role_definition_id == "/providers/Microsoft.Authorization/roleDefinitions/11111111-1111-1111-1111-111111111111"
    error_message = "A provider-computed definition ID must not make direct assignment effect, identity or role decisions unknown."
  }

  assert {
    condition     = output.initiative_effect == "DeployIfNotExists" && output.initiative_identity_required && length(output.initiative_required_roles) == 1 && output.initiative_required_roles[0].role_definition_id == "/providers/Microsoft.Authorization/roleDefinitions/11111111-1111-1111-1111-111111111111"
    error_message = "A provider-computed initiative ID must not make initiative assignment effect, identity or role decisions unknown."
  }
}
