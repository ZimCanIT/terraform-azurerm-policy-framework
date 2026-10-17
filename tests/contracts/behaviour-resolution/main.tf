terraform {
  required_version = ">= 1.12.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 5.0.0, < 6.0.0"
    }
  }
}

provider "azurerm" {
  features {}
}

variable "test_case" {
  type    = string
  default = "positive"
}

# Mock producers for resolver contract test
locals {
  mock_definitions = {
    allowed_locations = {
      catalogue_key     = "allowed_locations"
      id                = "/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c"
      source_type       = "built_in"
      parameters        = null
      supported_effects = ["Audit", "Deny", "Disabled"]
      capabilities = {
        default_effect = "Audit"
      }
      policy_rule = {
        then = {
          effect = "Audit"
        }
      }
      role_definition_ids = []
    }
    remediation_policy = {
      catalogue_key     = "remediation_policy"
      id                = "/providers/Microsoft.Authorization/policyDefinitions/11111111-1111-1111-1111-111111111111"
      source_type       = "built_in"
      parameters        = null
      supported_effects = ["Modify", "Disabled"]
      capabilities = {
        default_effect = "Modify"
      }
      policy_rule = {
        then = {
          effect = "Modify"
        }
      }
      role_definition_ids = ["/providers/Microsoft.Authorization/roleDefinitions/4d97b98b-1d4f-4787-a291-c67834d212e7"]
    }
    deploy_policy = {
      catalogue_key       = "deploy_policy"
      id                  = "/providers/Microsoft.Authorization/policyDefinitions/22222222-2222-2222-2222-222222222222"
      source_type         = "built_in"
      parameters          = null
      supported_effects   = ["DeployIfNotExists", "Disabled"]
      capabilities        = { default_effect = "DeployIfNotExists" }
      policy_rule         = { then = { effect = "DeployIfNotExists" } }
      role_definition_ids = ["/providers/Microsoft.Authorization/roleDefinitions/00000000-0000-0000-0000-000000000002"]
    }
    disabled_policy = {
      catalogue_key       = "disabled_policy"
      id                  = "/providers/Microsoft.Authorization/policyDefinitions/33333333-3333-3333-3333-333333333333"
      source_type         = "built_in"
      parameters          = null
      supported_effects   = ["Disabled"]
      capabilities        = { default_effect = "Disabled" }
      policy_rule         = { then = { effect = "Disabled" } }
      role_definition_ids = []
    }
  }

  mock_initiatives = {
    security_baseline = {
      catalogue_key       = "security_baseline"
      id                  = "/providers/Microsoft.Authorization/policySetDefinitions/12345678-1234-1234-1234-123456789abc"
      name                = "security-baseline"
      display_name        = "Security baseline"
      description         = "Example initiative."
      management_group_id = null
      metadata            = {}
      parameters = {
        environment = {
          type          = "String"
          defaultValue  = "production"
          allowedValues = ["production", "test"]
        }
      }
      parameter_schema = {
        environment = {
          type          = "String"
          defaultValue  = "production"
          allowedValues = ["production", "test"]
        }
      }
      policy_definition_references = [
        {
          reference_id         = "allowed_locations"
          definition_key       = "allowed_locations"
          initiative_key       = "security_baseline"
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c"
          parameter_values     = null
          parameter_schema     = null
          group_names          = []
          effect               = "Audit"
          required             = false
          version_constraint   = null
          pinned_version       = null
          inherited_version    = null
          selected_version     = null
          parameter_mappings   = null
          capabilities         = null
          list_fields          = {}
          governance           = null
          resource_version     = null
          source_type          = "built_in"
          created_by_module    = true
          role_definition_ids  = []
          target = {
            reference_id         = "allowed_locations"
            definition_key       = "allowed_locations"
            initiative_key       = "security_baseline"
            policy_definition_id = null
          }
        },
        {
          reference_id         = "modify_member"
          definition_key       = "remediation_policy"
          initiative_key       = "security_baseline"
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/11111111-1111-1111-1111-111111111111"
          parameter_values     = null
          parameter_schema     = null
          group_names          = []
          effect               = "Modify"
          required             = false
          version_constraint   = null
          pinned_version       = null
          inherited_version    = null
          selected_version     = null
          parameter_mappings   = null
          capabilities         = null
          list_fields          = {}
          governance           = null
          resource_version     = null
          source_type          = "built_in"
          created_by_module    = true
          role_definition_ids  = ["/providers/Microsoft.Authorization/roleDefinitions/4d97b98b-1d4f-4787-a291-c67834d212e7"]
          target = {
            reference_id         = "modify_member"
            definition_key       = "remediation_policy"
            initiative_key       = "security_baseline"
            policy_definition_id = null
          }
        },
        {
          reference_id         = "deploy_member"
          definition_key       = "deploy_policy"
          initiative_key       = "security_baseline"
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/22222222-2222-2222-2222-222222222222"
          parameter_values     = null
          parameter_schema     = null
          group_names          = []
          effect               = "DeployIfNotExists"
          required             = false
          version_constraint   = null
          pinned_version       = null
          inherited_version    = null
          selected_version     = null
          parameter_mappings   = null
          capabilities         = null
          list_fields          = {}
          governance           = null
          resource_version     = null
          source_type          = "built_in"
          created_by_module    = true
          role_definition_ids  = ["/providers/Microsoft.Authorization/roleDefinitions/00000000-0000-0000-0000-000000000002"]
          target = {
            reference_id         = "deploy_member"
            definition_key       = "deploy_policy"
            initiative_key       = "security_baseline"
            policy_definition_id = null
          }
        },
        {
          reference_id         = "disabled_member"
          definition_key       = "disabled_policy"
          initiative_key       = "security_baseline"
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/33333333-3333-3333-3333-333333333333"
          parameter_values     = null
          parameter_schema     = null
          group_names          = []
          effect               = "Disabled"
          required             = false
          version_constraint   = null
          pinned_version       = null
          inherited_version    = null
          selected_version     = null
          parameter_mappings   = null
          capabilities         = null
          list_fields          = {}
          governance           = null
          resource_version     = null
          source_type          = "built_in"
          created_by_module    = true
          role_definition_ids  = []
          target = {
            reference_id         = "disabled_member"
            definition_key       = "disabled_policy"
            initiative_key       = "security_baseline"
            policy_definition_id = null
          }
        }
      ]
      policy_definition_groups = []
      governance               = {}
      version                  = "1.0.0"
      created_by_module        = true
    }
  }
}

module "behaviour_resolution" {
  source = "../../../modules/behaviour-resolution"

  definitions = local.mock_definitions
  initiatives = local.mock_initiatives
  assignments = {
    platform_locations = {

      target = {
        reference_id   = "allowed_locations"
        definition_key = var.test_case == "malformed" ? "missing" : "allowed_locations"
      }
      scope = {
        type = "subscription"
        id   = "/subscriptions/00000000-0000-0000-0000-000000000000"
      }
    }
    initiative_locations = {
      target = {
        reference_id   = "allowed_locations"
        initiative_key = "security_baseline"
      }
      scope = {
        type = "subscription"
        id   = "/subscriptions/00000000-0000-0000-0000-000000000000"
      }
      parameters = {
        environment = { value = "test" }
      }
      identity = {
        location            = "westeurope"
        resource_group_name = "policy-identities"
      }
    }
    remediation_assignment = {
      target = {
        reference_id   = "remediation_policy"
        definition_key = "remediation_policy"
      }
      scope = {
        type = "subscription"
        id   = "/subscriptions/00000000-0000-0000-0000-000000000000"
      }
      identity = {
        location            = "westeurope"
        resource_group_name = "policy-identities"
      }
    }
  }
}

locals {
  resolved_assignment_inventory = {
    for key, record in module.behaviour_resolution.assignments : key => merge(record, {
      assignment = {
        id   = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/${key}"
        name = key
      }
    })
  }
}

module "identity_rbac" {
  source = "../../../modules/identity-rbac"

  assignments = local.resolved_assignment_inventory
}

module "assignments" {
  source = "../../../modules/assignments"

  assignments       = local.resolved_assignment_inventory
  identity_bindings = module.identity_rbac.assignment_bindings
}

module "operations" {
  source = "../../../modules/operations"

  resolved_assignments = local.resolved_assignment_inventory
  requests = {
    test_remediation = {
      mode                     = "execute"
      assignment_key           = "remediation_assignment"
      scope_type               = "subscription"
      scope_id                 = "/subscriptions/00000000-0000-0000-0000-000000000000"
      resource_discovery_mode  = "ExistingNonCompliant"
      location_filters         = null
      resource_count           = 10
      parallel_deployments     = 5
      failure_percentage       = 0.1
      role_scope               = "/subscriptions/00000000-0000-0000-0000-000000000000"
      approval_reference       = "test-approval"
      evidence_status          = null
      expected_evidence_status = null
    }
  }
  exemptions = {
    test_exemption = {
      request_mode  = "create"
      assignment_id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/remediation_assignment"
      scope = {
        type = "subscription"
        id   = "/subscriptions/00000000-0000-0000-0000-000000000000"
      }
      owner                = "test-owner"
      reason               = "test reason"
      approval_reference   = "test-approval"
      ticket_reference     = "test-ticket"
      category             = "Waiver"
      compensating_control = "test control"
      expires_on           = "2027-01-01T00:00:00Z"
    }
    initiative_member_exemption = {
      request_mode  = "create"
      assignment_id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/initiative_locations"
      scope = {
        type = "subscription"
        id   = "/subscriptions/00000000-0000-0000-0000-000000000000"
      }
      owner                           = "security-team"
      reason                          = "Approved exception for one initiative member."
      approval_reference              = "CAB-INIT-001"
      category                        = "Waiver"
      compensating_control            = "Monthly owner review."
      expires_on                      = "2027-01-01T00:00:00Z"
      policy_definition_reference_ids = ["modify_member"]
    }
  }
  evaluation_time = "2026-12-31T23:59:59Z"
}

output "resolver_assignments" {
  value = module.behaviour_resolution.assignments
}

output "identity_rbac" {
  value = module.identity_rbac.identity_rbac
}

output "assignments" {
  value = module.assignments.assignments
}

output "remediations" {
  value = module.operations.requested_operations
}

output "exemptions" {
  value = module.operations.status_contract
}
