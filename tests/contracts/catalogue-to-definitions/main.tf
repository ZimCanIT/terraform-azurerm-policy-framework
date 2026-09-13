terraform {
  required_version = ">= 1.12.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 5.0.0, < 6.0.0"
    }
  }
}

module "catalogue" {
  source = "../../../modules/catalogue"

  custom_definition_directory  = "../../../modules/catalogue/tests/fixtures/json_ingestion/custom"
  built_in_reference_directory = "../../../modules/catalogue/tests/fixtures/json_ingestion/built-in"
  initiative_directory         = "../../../modules/catalogue/tests/fixtures/initiative_ingestion/valid"

  native_definitions = {
    native_structured = {
      source_type         = "custom"
      display_name        = "Native structured policy"
      version             = "2.3.4"
      role_definition_ids = ["/providers/Microsoft.Authorization/roleDefinitions/11111111-1111-1111-1111-111111111111"]

      supported_effects = ["Audit", "Deny"]

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
        default = "The synthetic control is not compliant."
      }

      capabilities = {
        supportsIdentity    = true
        supportsRemediation = false
      }

      governance = {
        requirement_id = "REQ-TAGS-001"
        owner          = "platform-team"
        rationale      = "Cost allocation for synthetic resources."
        review_date    = "2026-12-31"
      }

      parameters = {
        retryCount = {
          type         = "Integer"
          defaultValue = 3
        }
        enforce = {
          type         = "Boolean"
          defaultValue = true
        }
        locations = {
          type         = "Array"
          defaultValue = ["eastus", "westus"]
        }
      }
      policy_rule = {
        if = {
          field  = "type"
          equals = "Microsoft.Resources/subscriptions"
        }
        then = {
          effect = "audit"
          details = {
            roleDefinitionIds = ["/providers/Microsoft.Authorization/roleDefinitions/22222222-2222-2222-2222-222222222222"]
          }
        }
      }
    }

    # P20 hand-off proof: every documented string scalar is supplied as a
    # strict string so modules/definitions can accept the emitted entry at its
    # variable boundary.
    native_strict_scalars = {
      source_type         = "custom"
      name                = "native-strict-scalars"
      display_name        = "Native strict scalars"
      description         = "Synthetic strict scalar projection entry."
      mode                = "All"
      management_group_id = "/providers/Microsoft.Management/managementGroups/example-platform"
      version             = "1.0.0"

      metadata = {
        version = "1.0.0"
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

    native_unknown_effects = {
      source_type  = "custom"
      display_name = "Native unknown effects"
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

    native_verified_empty_effects = {
      source_type       = "custom"
      display_name      = "Native verified empty effects"
      version           = "1.0.0"
      supported_effects = []

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

    # Built-in capability fixtures for the P18 unknown-state contract: the
    # catalogue emits null mode, parameters and role_definition_ids whenever a
    # built-in reference does not declare them.
    native_builtin_missing_capability = {
      source_type          = "built_in"
      display_name         = "Native built-in missing capability"
      policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
      version_constraint   = "1.*.*"
    }

    native_builtin_verified_empty_capability = {
      source_type          = "built_in"
      display_name         = "Native built-in verified empty capability"
      policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
      parameters           = {}
      role_definition_ids  = []
      version_constraint   = "1.*.*"
    }

    native_builtin_supplied_capability = {
      source_type          = "built_in"
      display_name         = "Native built-in supplied capability"
      policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/dddddddd-dddd-dddd-dddd-dddddddddddd"
      mode                 = "Indexed"

      parameters = {
        listOfAllowedLocations = {
          type = "Array"
        }
      }

      role_definition_ids = ["/providers/Microsoft.Authorization/roleDefinitions/44444444-4444-4444-4444-444444444444"]
      version_constraint  = "1.*.*"
    }
  }
}

module "definitions" {
  source      = "../../../modules/definitions"
  definitions = module.catalogue.definitions
}

output "definitions" {
  value = module.definitions.definitions
}

output "initiatives" {
  value = module.catalogue.initiatives
}
