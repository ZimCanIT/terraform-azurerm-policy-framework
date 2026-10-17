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

module "assignments" {
  source = "../.."

  assignments = {
    management_group = {
      intent = {
        target = {
          reference_id         = "synthetic-management-group"
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/00000000-0000-0000-0000-000000000001"
        }
        scope = {
          type = "management_group"
          id   = "/providers/Microsoft.Management/managementGroups/synthetic"
        }
        exclusions              = ["/subscriptions/00000000-0000-0000-0000-000000000001"]
        enforcement_mode        = "DoNotEnforce"
        non_compliance_messages = [{ content = "Synthetic management group audit message" }]
        rollout                 = { stage = "pilot", intent = "audit-first" }
      }
      resolved = {
        policy_definition_id      = "/providers/Microsoft.Authorization/policyDefinitions/00000000-0000-0000-0000-000000000001"
        effective_effect          = "Audit"
        definition_default_effect = "Audit"
        parameter_schema          = {}
        parameter_values          = {}
        identity                  = { required = false, strategy = "none" }
        required_roles            = []
        list_fields               = { selectors = [{ kind = "resourceLocation" }], supported_overrides = [{ kind = "policyEffect", value = "Audit" }], non_compliance_messages = { default = "Synthetic management group audit message" } }
      }

    }

    subscription = {
      intent = {
        target    = { reference_id = "synthetic-subscription" }
        scope     = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000001" }
        selectors = [{ name = "west-europe", selectors = [{ kind = "resourceLocation", in = ["westeurope"] }] }]
        overrides = [{ value = "Audit", selectors = [{ kind = "resourceLocation", in = ["westeurope"] }] }]
      }
      resolved = {
        policy_definition_id      = "/providers/Microsoft.Authorization/policyDefinitions/00000000-0000-0000-0000-000000000002"
        effective_effect          = "Audit"
        definition_default_effect = "Audit"
        parameter_schema          = { mode = { type = "string", defaultValue = "Audit", allowedValues = ["Audit", "Deny"] } }
        parameter_values          = { mode = "Audit" }
        identity                  = { required = false, strategy = "none" }
        required_roles            = []
        list_fields               = { selectors = [{ kind = "resourceLocation" }], supported_overrides = [{ kind = "policyEffect", value = "Audit" }], non_compliance_messages = { default = "Synthetic subscription audit message" } }
      }

    }

    resource_group = {
      intent = {
        target = { reference_id = "synthetic-resource-group" }
        scope  = { type = "resource_group", id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/synthetic" }
      }
      resolved = {
        policy_definition_id      = "/providers/Microsoft.Authorization/policyDefinitions/00000000-0000-0000-0000-000000000003"
        effective_effect          = "Audit"
        definition_default_effect = "Audit"
        parameter_schema          = {}
        parameter_values          = {}
        identity                  = { required = false, strategy = "none" }
        required_roles            = []
        list_fields               = { selectors = [], supported_overrides = [], non_compliance_messages = {} }
      }

    }

    resource = {
      intent = {
        target = { reference_id = "synthetic-resource" }
        scope  = { type = "resource", id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/synthetic/providers/Microsoft.Storage/storageAccounts/example" }
      }
      resolved = {
        policy_definition_id      = "/providers/Microsoft.Authorization/policyDefinitions/00000000-0000-0000-0000-000000000004"
        effective_effect          = "Audit"
        definition_default_effect = "Audit"
        parameter_schema          = {}
        parameter_values          = {}
        identity                  = { required = false, strategy = "none" }
        required_roles            = []
        list_fields               = { selectors = [], supported_overrides = [], non_compliance_messages = {} }
      }

    }
  }
}

output "assignments" {
  value = module.assignments.assignments
}
