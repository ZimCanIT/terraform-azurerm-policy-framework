run "resolves_valid_absent_and_null_effects" {
  command = plan

  variables {
    definitions = {
      valid = {
        id                = "/providers/Microsoft.Authorization/policyDefinitions/valid"
        supported_effects = ["Audit"]
        capabilities      = { default_effect = "Audit" }
        policy_rule       = { then = { effect = "Audit" } }
      }
    }

    assignments = {
      absent = {
        target = {
          reference_id   = "absent"
          definition_key = "valid"
        }
        scope = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000000" }
      }
      null_effect = {
        target = {
          reference_id   = "null-effect"
          definition_key = "valid"
        }
        scope  = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000000" }
        effect = null
      }
      valid = {
        target = {
          reference_id   = "valid"
          definition_key = "valid"
        }
        scope  = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000000" }
        effect = "audit"
      }
    }
  }

  assert {
    condition     = output.assignments["absent"].resolved.requested_effect == null && output.assignments["null_effect"].resolved.requested_effect == null && output.assignments["valid"].resolved.requested_effect == "Audit" && output.assignments["absent"].resolved.effective_effect == "Audit"
    error_message = "Absent and null requested effects must remain unknown while the definition default supplies the effective effect."
  }
}

run "preserves_absent_and_null_versions" {
  command = plan

  variables {
    definitions = {
      no_version = {
        id                = "/providers/Microsoft.Authorization/policyDefinitions/no-version"
        supported_effects = ["Audit"]
        capabilities      = { default_effect = "Audit" }
        policy_rule       = { then = { effect = "Audit" } }
      }
    }

    assignments = {
      absent = {
        target = {
          reference_id   = "absent-version"
          definition_key = "no_version"
        }
        scope = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000000" }
      }
      null_version = {
        target = {
          reference_id   = "null-version"
          definition_key = "no_version"
        }
        scope              = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000000" }
        version_constraint = null
        pinned_version     = null
      }
    }
  }

  assert {
    condition     = output.assignments["absent"].resolved.selected_version == null && output.assignments["null_version"].resolved.selected_version == null
    error_message = "Absent and explicit null version intent must remain unknown rather than being defaulted."
  }
}

run "explicit_unversioned_binding_preserves_definition_version_provenance" {
  command = plan

  variables {
    definitions = {
      built_in = {
        id                  = "/providers/Microsoft.Authorization/policyDefinitions/built-in"
        source_type         = "built_in"
        parameters          = {}
        supported_effects   = ["Audit"]
        pinned_version      = "1.0.0"
        capabilities        = { default_effect = "Audit" }
        role_definition_ids = []
      }
    }
    assignments = {
      unversioned = {
        target          = { reference_id = "built-in", definition_key = "built_in" }
        scope           = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000000" }
        version_binding = "unversioned"
      }
      inherited = {
        target = { reference_id = "built-in-default", definition_key = "built_in" }
        scope  = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000000" }
      }
    }
  }

  assert {
    condition     = output.assignments["unversioned"].resolved.selected_version == null && output.assignments["unversioned"].resolved.source_version == "1.0.0" && output.assignments["unversioned"].intent.version_binding == "unversioned"
    error_message = "An explicit unversioned direct target must preserve source pin provenance without claiming a deployed version."
  }

  assert {
    condition     = output.assignments["inherited"].resolved.selected_version == "1.0.0" && output.assignments["inherited"].resolved.source_version == "1.0.0"
    error_message = "Without the explicit opt-out, a definition pin remains inherited as a selected version."
  }
}

run "rejects_unversioned_binding_with_assignment_version_request" {
  command = plan

  variables {
    assignments = {
      conflict = {
        target             = { reference_id = "policy", definition_key = "policy" }
        scope              = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000000" }
        version_binding    = "unversioned"
        version_constraint = "1.*.*"
      }
    }
  }

  expect_failures = [var.assignments]
}

run "rejects_malformed_target" {
  command = plan

  variables {
    assignments = {
      malformed = {
        target = "not-an-object"
        scope  = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000000" }
      }
    }
  }

  expect_failures = [var.assignments]
}

run "rejects_malformed_effect_and_version" {
  command = plan

  variables {
    assignments = {
      malformed_effect = {
        target = {
          reference_id         = "malformed-effect"
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/valid"
        }
        scope  = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000000" }
        effect = 42
      }
      malformed_version = {
        target = {
          reference_id         = "malformed-version"
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/valid"
        }
        scope          = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000000" }
        pinned_version = ["1.0.0"]
      }
    }
  }

  expect_failures = [var.assignments]
}

run "rejects_unknown_target_reference" {
  command = plan

  variables {
    definitions = {
      valid = {
        id                = "/providers/Microsoft.Authorization/policyDefinitions/valid"
        supported_effects = ["Audit"]
        capabilities      = { default_effect = "Audit" }
        policy_rule       = { then = { effect = "Audit" } }
      }
    }

    assignments = {
      missing_definition = {
        target = {
          reference_id   = "missing"
          definition_key = "does-not-exist"
        }
        scope = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000000" }
      }
    }
  }

  expect_failures = [terraform_data.contract_guard]
}

run "resolves_all_initiative_members_and_scopes_effects" {
  command = plan

  variables {
    definitions = {
      audit = {
        id                  = "/providers/Microsoft.Authorization/policyDefinitions/audit-guid"
        source_type         = "built_in"
        parameters          = {}
        supported_effects   = ["Audit", "Disabled"]
        role_definition_ids = []
        capabilities        = { default_effect = "Audit" }
        policy_rule         = { then = { effect = "Audit" } }
        version_constraint  = "1.*.*"
      }
      modify = {
        id                  = "/providers/Microsoft.Authorization/policyDefinitions/modify-guid"
        source_type         = "built_in"
        parameters          = {}
        supported_effects   = ["Modify", "Audit", "Disabled"]
        role_definition_ids = ["/providers/Microsoft.Authorization/roleDefinitions/11111111-1111-1111-1111-111111111111"]
        capabilities        = { default_effect = "Modify" }
        policy_rule         = { then = { effect = "Modify" } }
        version_constraint  = "1.*.*"
      }
      deploy = {
        id                  = "/providers/Microsoft.Authorization/policyDefinitions/deploy-guid"
        source_type         = "built_in"
        parameters          = {}
        supported_effects   = ["DeployIfNotExists", "Disabled"]
        role_definition_ids = ["/providers/Microsoft.Authorization/roleDefinitions/22222222-2222-2222-2222-222222222222"]
        capabilities        = { default_effect = "DeployIfNotExists" }
        policy_rule         = { then = { effect = "DeployIfNotExists" } }
        version_constraint  = "1.*.*"
      }
    }

    initiatives = {
      mixed = {
        id                = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policySetDefinitions/mixed"
        created_by_module = true
        version           = "9.0.0"
        parameter_schema  = { setName = { type = "String" } }
        parameters        = { setName = { type = "String" } }
        governance        = { owner = "initiative-team" }
        policy_definition_references = [
          {
            reference_id         = "audit-member"
            definition_key       = "audit"
            policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/audit-guid"
            source_type          = "built_in"
            created_by_module    = false
            effect               = "Audit"
            version_constraint   = "1.*.*"
            selected_version     = "1.*.*"
            parameter_schema     = {}
            parameter_values     = {}
            parameter_mappings   = {}
            role_definition_ids  = []
            capabilities         = { default_effect = "Audit" }
            list_fields          = { supported_effects = ["Audit", "Disabled"], role_definition_ids = [] }
            governance           = { owner = "audit-team" }
          },
          {
            reference_id         = "modify-member"
            definition_key       = "modify"
            policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/modify-guid"
            source_type          = "built_in"
            created_by_module    = false
            effect               = "Modify"
            version_constraint   = "1.*.*"
            selected_version     = "1.*.*"
            parameter_schema     = {}
            parameter_values     = {}
            parameter_mappings   = {}
            role_definition_ids  = ["/providers/Microsoft.Authorization/roleDefinitions/11111111-1111-1111-1111-111111111111"]
            capabilities         = { default_effect = "Modify" }
            list_fields          = { supported_effects = ["Modify", "Audit", "Disabled"], role_definition_ids = ["/providers/Microsoft.Authorization/roleDefinitions/11111111-1111-1111-1111-111111111111"] }
            governance           = { owner = "modify-team" }
          },
          {
            reference_id         = "deploy-member"
            definition_key       = "deploy"
            policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/deploy-guid"
            source_type          = "built_in"
            created_by_module    = false
            effect               = "DeployIfNotExists"
            version_constraint   = "1.*.*"
            selected_version     = "1.*.*"
            parameter_schema     = {}
            parameter_values     = {}
            parameter_mappings   = {}
            role_definition_ids  = ["/providers/Microsoft.Authorization/roleDefinitions/22222222-2222-2222-2222-222222222222"]
            capabilities         = { default_effect = "DeployIfNotExists" }
            list_fields          = { supported_effects = ["DeployIfNotExists", "Disabled"], role_definition_ids = ["/providers/Microsoft.Authorization/roleDefinitions/22222222-2222-2222-2222-222222222222"] }
            governance           = { owner = "deploy-team" }
          }
        ]
      }
    }

    assignments = {
      mixed = {
        target     = { reference_id = "audit-member", initiative_key = "mixed" }
        scope      = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000000" }
        parameters = { setName = "platform" }
        effect     = "Disabled"
        overrides  = [{ kind = "policyEffect", value = "Audit", selectors = [{ kind = "PolicyDefinitionReferenceId", in = ["modify-member"] }] }]
        identity   = { location = "westeurope", resource_group_name = "policy-identities" }
        governance = { owner = "assignment-team" }
      }
    }
  }

  assert {
    condition     = length(output.assignments["mixed"].resolved.members) == 3 && jsonencode(output.assignments["mixed"].resolved.member_reference_ids) == jsonencode(["audit-member", "modify-member", "deploy-member"])
    error_message = "The complete initiative member inventory must be published in canonical order."
  }

  assert {
    condition     = output.assignments["mixed"].resolved.members[0].effective_effect == "Disabled"
    error_message = "The member-scoped assignment effect must resolve on audit-member."
  }

  assert {
    condition     = output.assignments["mixed"].resolved.members[1].effective_effect == "Audit"
    error_message = "The explicit member selector must resolve on modify-member."
  }

  assert {
    condition     = output.assignments["mixed"].resolved.members[2].effective_effect == "DeployIfNotExists"
    error_message = "The unselected deploy member must retain its own effect."
  }

  assert {
    condition     = jsonencode(output.assignments["mixed"].resolved.overrides[0].selectors[0].in) == jsonencode(["modify-member"]) && jsonencode(output.assignments["mixed"].resolved.overrides[1].selectors[0].in) == jsonencode(["audit-member"]) && output.assignments["mixed"].resolved.effective_effect == null
    error_message = "Explicit and compiled effect overrides must remain reference-scoped, and a mixed initiative must not claim one set-level effective effect."
  }

  assert {
    condition     = output.assignments["mixed"].resolved.identity.required
    error_message = "Identity requirement must aggregate every initiative member that can execute."
  }

  assert {
    condition     = length(output.assignments["mixed"].resolved.required_roles) == 1 && output.assignments["mixed"].resolved.required_roles[0].role_definition_id == "/providers/Microsoft.Authorization/roleDefinitions/22222222-2222-2222-2222-222222222222"
    error_message = "Aggregate roles must include the role for DeployIfNotExists members."
  }

  assert {
    condition     = output.assignments["mixed"].resolved.selected_version == "1.*.*" && output.assignments["mixed"].resolved.initiative_content_version == "9.0.0"
    error_message = "Member deployment version intent must remain distinct from initiative content metadata."
  }

  assert {
    condition     = jsonencode(output.assignments["mixed"].resolved.parameter_schema) == jsonencode({ setName = { type = "String" } }) && output.assignments["mixed"].resolved.governance.owner == "assignment-team"
    error_message = "The initiative set schema and assignment-precedence governance values must survive resolution."
  }
}

run "applies_not_in_effect_override_to_non_excluded_member" {
  command = plan

  variables {
    definitions = {
      policy = {
        id                  = "/providers/Microsoft.Authorization/policyDefinitions/policy"
        source_type         = "built_in"
        parameters          = {}
        supported_effects   = ["Audit", "Disabled"]
        capabilities        = { default_effect = "Audit" }
        role_definition_ids = []
      }
    }
    initiatives = {
      set = {
        id                = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policySetDefinitions/set"
        created_by_module = true
        parameter_schema  = {}
        policy_definition_references = [{
          reference_id         = "member"
          definition_key       = "policy"
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/policy"
          effect               = "Audit"
          capabilities         = { default_effect = "Audit" }
          role_definition_ids  = []
          list_fields          = { supported_effects = ["Audit", "Disabled"], role_definition_ids = [] }
        }]
      }
    }
    assignments = {
      selected = {
        target = { reference_id = "member", initiative_key = "set" }
        scope  = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000000" }
        overrides = [{
          kind      = "policyEffect"
          value     = "Disabled"
          selectors = [{ kind = "PolicyDefinitionReferenceId", not_in = ["other-member"] }]
        }]
      }
    }
  }

  assert {
    condition     = output.assignments["selected"].resolved.members[0].effective_effect == "Disabled" && output.assignments["selected"].resolved.members[0].identity_required == false
    error_message = "A not_in selector must apply the override to this member and update its identity decision."
  }
}

run "rejects_conflicting_effect_overrides" {
  command = plan

  variables {
    definitions = {
      policy = {
        id                  = "/providers/Microsoft.Authorization/policyDefinitions/policy"
        source_type         = "built_in"
        parameters          = {}
        supported_effects   = ["Audit", "Disabled"]
        capabilities        = { default_effect = "Audit" }
        role_definition_ids = []
      }
    }
    initiatives = {}
    assignments = {
      conflict = {
        target = { reference_id = "policy", definition_key = "policy" }
        scope  = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000000" }
        overrides = [
          { value = "Audit" },
          { value = "Disabled" }
        ]
      }
    }
  }

  expect_failures = [terraform_data.contract_guard]
}

run "preserves_heterogeneous_parameter_values_for_direct_and_set_targets" {
  command = plan

  variables {
    definitions = {
      typed = {
        id                  = "/providers/Microsoft.Authorization/policyDefinitions/typed"
        parameters          = { text = { type = "String" }, enabled = { type = "Boolean" }, count = { type = "Integer" }, whole = { type = "Float" }, ratio = { type = "Float" }, when = { type = "DateTime" }, items = { type = "Array" }, detail = { type = "Object" } }
        supported_effects   = ["Audit"]
        capabilities        = { default_effect = "Audit" }
        policy_rule         = { then = { effect = "Audit" } }
        role_definition_ids = []
      }
    }

    initiatives = {
      typed_set = {
        id                = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policySetDefinitions/typed-set"
        created_by_module = true
        parameter_schema  = { text = { type = "String" }, enabled = { type = "Boolean" }, count = { type = "Integer" }, whole = { type = "Float" }, ratio = { type = "Float" }, when = { type = "DateTime" }, items = { type = "Array" }, detail = { type = "Object" } }
        parameters        = { text = { type = "String" }, enabled = { type = "Boolean" }, count = { type = "Integer" }, whole = { type = "Float" }, ratio = { type = "Float" }, when = { type = "DateTime" }, items = { type = "Array" }, detail = { type = "Object" } }
        policy_definition_references = [{
          reference_id         = "typed-member"
          definition_key       = "typed"
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/typed"
          effect               = "Audit"
          parameter_schema     = {}
          parameter_values     = {}
          parameter_mappings   = {}
          capabilities         = { default_effect = "Audit" }
          role_definition_ids  = []
          list_fields          = { supported_effects = ["Audit"], role_definition_ids = [] }
        }]
      }
    }

    assignments = {
      direct = {
        target = { reference_id = "typed-direct", definition_key = "typed" }
        scope  = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000000" }
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
      set = {
        target = { reference_id = "typed-member", initiative_key = "typed_set" }
        scope  = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000000" }
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
    }
  }

  assert {
    condition = jsonencode(output.assignments["direct"].resolved.parameter_values) == jsonencode({
      text    = { value = "hello" }
      enabled = { value = true }
      count   = { value = 5 }
      whole   = { value = 5 }
      ratio   = { value = 5.5 }
      when    = { value = "2027-01-01T00:00:00Z" }
      items   = { value = ["text", 5, { nested = true }] }
      detail  = { value = { nested = ["text", 5], enabled = true } }
    })
    error_message = "Direct resolved values must preserve all seven JSON types and heterogeneous nested data."
  }

  assert {
    condition = jsonencode(output.assignments["set"].resolved.parameter_values) == jsonencode({
      text    = { value = "hello" }
      enabled = { value = true }
      count   = { value = 5 }
      whole   = { value = 5 }
      ratio   = { value = 5.5 }
      when    = { value = "2027-01-01T00:00:00Z" }
      items   = { value = ["text", 5, { nested = true }] }
      detail  = { value = { nested = ["text", 5], enabled = true } }
    })
    error_message = "Set resolved values must preserve all seven JSON types and heterogeneous nested data."
  }
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

run "rejects_scalar_assignment_with_contract_diagnostic" {
  command = plan
  variables { assignments = { malformed_assignment = 7 } }
  expect_failures = [var.assignments]
}

run "rejects_null_assignment_with_contract_diagnostic" {
  command = plan
  variables { assignments = { malformed_assignment = null } }
  expect_failures = [var.assignments]
}

run "rejects_null_initiative_id_with_contract_diagnostic" {
  command = plan
  variables { initiatives = { malformed_initiative = { id = null, created_by_module = true, policy_definition_references = [] } } }
  expect_failures = [var.initiatives]
}
