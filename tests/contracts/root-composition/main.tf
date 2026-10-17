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

provider "azurerm" {
  alias = "consumer"
  features {}
}

resource "terraform_data" "consumer_prerequisite" {}

locals {
  typed_parameter_schema = {
    label     = { type = "String", defaultValue = "default-label" }
    values    = { type = "Array", defaultValue = ["westus", 5, { nested = true }] }
    settings  = { type = "Object", defaultValue = { enabled = true, nested = ["value", 2.5] } }
    enabled   = { type = "Boolean", defaultValue = true }
    count     = { type = "Integer", defaultValue = 5 }
    ratio     = { type = "Float", defaultValue = 5.5 }
    timestamp = { type = "DateTime", defaultValue = "2027-01-01T00:00:00Z" }
  }

  typed_parameter_values = {
    label     = "explicit-label"
    values    = ["eastus", 7, { nested = false }]
    settings  = { enabled = false, nested = ["changed", 3.25] }
    enabled   = false
    count     = 7
    ratio     = 7.25
    timestamp = "2028-02-03T04:05:06.0000000Z"
  }

  typed_parameter_wrappers = {
    for key, value in local.typed_parameter_values : key => { value = value }
  }

  typed_set_schema = {
    for key, schema in local.typed_parameter_schema : "set${key}" => schema
  }

  typed_set_wrappers = {
    for key, value in local.typed_parameter_values : "set${key}" => { value = value }
  }

  typed_member_bindings = {
    for key in keys(local.typed_parameter_schema) : key => { value = "[parameters('set${key}')]" }
  }
}

module "counted_framework" {
  count      = 1
  source     = "../../.."
  providers  = { azurerm = azurerm.consumer }
  depends_on = [terraform_data.consumer_prerequisite]
}

module "keyed_framework" {
  for_each   = toset(["estate"])
  source     = "../../.."
  providers  = { azurerm = azurerm.consumer }
  depends_on = [terraform_data.consumer_prerequisite]
}

variable "test_case" {
  type    = string
  default = "positive"
}

module "framework" {
  source = "../../.."

  definitions = {
    direct_audit = {
      source_type          = "built_in"
      display_name         = "Direct audit"
      policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/00000000-0000-0000-0000-000000000001"
      pinned_version       = "1.0.0"
      role_definition_ids  = []
      supported_effects    = ["Audit", "Disabled"]
      capabilities         = { default_effect = "Audit" }
      mode                 = null
    }

    typed_policy = {
      source_type          = "built_in"
      display_name         = "Typed parameter contract"
      policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/00000000-0000-0000-0000-000000000002"
      version_constraint   = "1.0.*"
      parameters           = local.typed_parameter_schema
      role_definition_ids  = []
      supported_effects    = ["Audit", "Disabled"]
      capabilities         = { default_effect = "Audit" }
    }
  }

  initiatives = {
    typed_set = {
      display_name = "Typed parameter initiative"
      parameters   = local.typed_set_schema
      policy_definition_references = [{
        reference_id     = "typed-member"
        definition_key   = "typed_policy"
        parameter_values = local.typed_member_bindings
      }]
    }
  }

  assignments = {
    direct_audit = {
      target = {
        reference_id         = "direct_audit"
        definition_key       = var.test_case == "malformed" ? null : "direct_audit"
        policy_definition_id = var.test_case == "malformed" ? "not-an-azure-policy-id" : null
      }
      scope = {
        type = "subscription"
        id   = "/subscriptions/00000000-0000-0000-0000-000000000000"
      }
      effect          = "Audit"
      version_binding = "unversioned"
    }

    typed_direct = {
      target = {
        reference_id   = "typed-direct"
        definition_key = "typed_policy"
      }
      scope = {
        type = "resource"
        id   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/contract/providers/Microsoft.Storage/storageAccounts/typed"
      }
      parameters      = local.typed_parameter_wrappers
      version_binding = "unversioned"
    }

    typed_set = {
      target = {
        reference_id   = "typed-member"
        initiative_key = "typed_set"
      }
      scope = {
        type = "resource_group"
        id   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/contract"
      }
      parameters = local.typed_set_wrappers
    }
  }

  requirements = {
    internal_requirement = {
      owner           = "platform-team"
      control_keys    = ["direct_audit"]
      assignment_keys = ["direct_audit"]
      review_date     = "2027-01-31"
      status          = "approved"
    }
    external_requirement = {
      owner           = "security-team"
      control_keys    = ["external-baseline"]
      assignment_keys = ["externally-managed-assignment"]
      review_date     = "2027-01-31"
      status          = "approved"
    }
  }

  external_control_keys    = ["external-baseline"]
  external_assignment_keys = ["externally-managed-assignment"]

}

output "root_contract" {
  value = {
    resolved_assignments   = module.framework.resolved_assignments
    lifecycle_resource_ids = module.framework.lifecycle_resource_ids
    governance             = module.framework.governance
    plan_summary           = module.framework.plan_summary
    replacement_review     = module.framework.replacement_review
    remediations           = module.framework.remediations
    exemptions             = module.framework.exemptions
  }
}

output "consumer_composition" {
  value = {
    counted_instances = length(module.counted_framework)
    keyed_instances   = keys(module.keyed_framework)
  }
}

output "typed_parameter_fixture" {
  value = {
    definition_schema = local.typed_parameter_schema
    definition_values = local.typed_parameter_wrappers
    initiative_schema = local.typed_set_schema
    initiative_values = local.typed_set_wrappers
    member_bindings   = local.typed_member_bindings
  }
}

output "typed_producer_contract" {
  value = {
    definitions = module.framework.definitions
    initiatives = module.framework.initiatives
  }
}
