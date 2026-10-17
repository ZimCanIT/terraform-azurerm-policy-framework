terraform {
  required_version = ">= 1.12.0"
}

variable "management_group_id" {
  # Consumer roots supply this deployment binding. The synthetic default keeps
  # the example portable; replace it with the target environment value.
  description = "Optional management group resource ID used as the deployment binding for native custom definitions."
  type        = string
  default     = "/providers/Microsoft.Management/managementGroups/example-platform"

  validation {
    condition = var.management_group_id == null || can(regex(
      "^/providers/Microsoft\\.Management/managementGroups/[^/]+$",
      var.management_group_id
    ))
    error_message = "management_group_id must be null or /providers/Microsoft.Management/managementGroups/<group-id>."
  }
}

module "catalogue" {
  source = "../.."

  # Flat JSON library: a built-in reference, two custom definitions (one with a
  # parameter companion) and an initiative that references them by key.
  custom_definition_directory  = "${path.module}/catalogue/custom-definitions"
  built_in_reference_directory = "${path.module}/catalogue/built-in-references"
  initiative_directory         = "${path.module}/catalogue/initiatives"

  # Native HCL entries merge with the JSON library under one key space.
  native_definitions = {
    native_governed_control = {
      source_type         = "custom"
      display_name        = "Native governed control"
      description         = "Synthetic native control with governance and override declarations."
      version             = "2.0.0"
      management_group_id = var.management_group_id
      supported_effects   = ["Audit", "Disabled"]

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
      description  = "Initiative composed from JSON and native catalogue entries."
      version      = "1.0.0"

      parameters = {
        allowedLocations = {
          type = "Array"
          metadata = {
            displayName = "Allowed locations"
          }
        }
      }

      policy_definition_references = [
        {
          reference_id   = "allowed_locations"
          definition_key = "allowed_locations"

          parameter_values = {
            listOfAllowedLocations = {
              value = "[parameters('allowedLocations')]"
            }
          }

          version_constraint = "1.*.*"
        },
        {
          reference_id   = "require_cost_centre_tag"
          definition_key = "require_cost_centre_tag"
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
  description = "Canonical definitions merging native HCL and JSON sources, for modules/definitions."
  value       = module.catalogue.definitions
}

output "initiatives" {
  description = "Canonical initiative envelopes from both sources, for modules/initiatives."
  value       = module.catalogue.initiatives
}

output "source_summary" {
  description = "Non-sensitive provenance for review."
  value       = module.catalogue.source_summary
}
