terraform {
  required_version = ">= 1.7.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 5.0.0, < 6.0.0"
    }
  }
}

variable "management_group_id" {
  # Omit this value to create the custom definition in the provider subscription.
  description = "Optional management group resource ID for the custom definition. Leave null to use the provider subscription."
  type        = string
  default     = null

  validation {
    condition = var.management_group_id == null || can(regex(
      "^/providers/Microsoft\\.Management/managementGroups/[^/]+$",
      var.management_group_id
    ))
    error_message = "management_group_id must be null or /providers/Microsoft.Management/managementGroups/<group-id>."
  }
}

provider "azurerm" {
  features {}
}

module "definitions" {
  source = "../../"

  definitions = {
    # Built-ins are recorded as stable references; this module does not create them.
    allowed_locations = {
      source_type          = "built_in"
      policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c"
      display_name         = "Allowed locations"
      description          = "Restrict the locations in which resources can be deployed."
      mode                 = "Indexed"
      supported_effects    = ["Audit", "Deny", "Disabled"]
      version_constraint   = "1.*.*"
    }

    # Custom entries become Azure Policy definition resources.
    require_cost_centre_tag = {
      source_type         = "custom"
      display_name        = "Require cost centre tag"
      description         = "Audit resources that do not have the required cost centre tag."
      mode                = "Indexed"
      management_group_id = var.management_group_id

      metadata = {
        category = "Tags"
      }

      parameters = {
        tagName = {
          type = "String"
          metadata = {
            displayName = "Tag name"
            description = "Name of the required cost centre tag."
          }
          defaultValue = "costCentre"
        }
      }

      policy_rule = {
        if = {
          field  = "[concat('tags[', parameters('tagName'), ']')]"
          exists = "false"
        }
        then = {
          effect = "audit"
        }
      }

      supported_effects = ["Audit", "Disabled"]
      version           = "1.0.0"
    }
  }
}

output "definitions" {
  # Pass this canonical map to downstream initiative or assignment modules.
  description = "Canonical definitions for downstream initiative and assignment modules."
  value       = module.definitions.definitions
}

output "custom_definition_ids" {
  # This map contains only Azure resources created by this example.
  description = "IDs created by the definitions module."
  value       = module.definitions.custom_definition_ids
}

output "built_in_definition_ids" {
  # This map contains references only; built-ins are never created here.
  description = "Built-in IDs passed through without creating or reading Azure resources."
  value       = module.definitions.built_in_definition_ids
}
