terraform {
  required_version = ">= 1.12.0"
}

variable "management_group_id" {
  # Consumer roots supply this deployment binding. The synthetic default keeps
  # the example portable; replace it with the target environment value.
  description = "Optional management group resource ID used as the deployment binding for native custom definitions."
  type        = string
  default     = "/providers/Microsoft.Management/managementGroups/example-platform"
}

module "catalogue" {
  source = "../.."

  custom_definition_directory = "${path.module}/catalogue/custom-definitions"

  native_definitions = {
    allowed_locations = {
      source_type          = "built_in"
      display_name         = "Allowed locations"
      mode                 = "Indexed"
      policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c"
      version_constraint   = "1.*.*"
      supported_effects    = ["Audit", "Deny", "Disabled"]
    }

    native_governed_control = {
      source_type         = "custom"
      display_name        = "Native governed control"
      version             = "2.0.0"
      management_group_id = var.management_group_id

      governance = {
        requirement_id = "REQ-NATIVE-001"
        owner          = "platform-team"
      }

      supported_overrides = [
        {
          kind  = "policyEffect"
          value = "Disabled"
        }
      ]

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
  }

  native_initiatives = {
    mixed_baseline = {
      display_name = "Mixed baseline"
      version      = "1.0.0"

      policy_definition_references = [
        {
          reference_id   = "allowed_locations"
          definition_key = "allowed_locations"
        },
        {
          reference_id   = "governed_control"
          definition_key = "governed_control"
        },
        {
          reference_id   = "native_governed_control"
          definition_key = "native_governed_control"
        }
      ]
    }
  }
}

output "definitions" {
  description = "Canonical definitions merging native HCL and JSON sources."
  value       = module.catalogue.definitions
}

output "initiatives" {
  description = "Canonical initiative envelopes for the future modules/initiatives."
  value       = module.catalogue.initiatives
}

output "source_summary" {
  description = "Non-sensitive provenance for review."
  value       = module.catalogue.source_summary
}
