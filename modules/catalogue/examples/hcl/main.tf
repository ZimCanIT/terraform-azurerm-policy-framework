terraform {
  required_version = ">= 1.12.0"
}

variable "management_group_id" {
  # Consumer roots supply this deployment binding. The synthetic default keeps
  # the example portable; replace it with the target environment value.
  description = "Optional management group resource ID used as the deployment binding for the custom definition."
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

  native_definitions = {
    # Built-in references are portable policy content and carry no scope.
    allowed_locations = {
      source_type          = "built_in"
      display_name         = "Allowed locations"
      description          = "Restrict the locations in which resources can be deployed."
      mode                 = "Indexed"
      policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c"
      version_constraint   = "1.*.*"
      supported_effects    = ["Audit", "Deny", "Disabled"]

      capabilities = {
        supportsIdentity    = false
        supportsRemediation = false
      }

      governance = {
        requirement_id = "REQ-LOCATION-001"
        owner          = "platform-team"
        rationale      = "Restrict deployments to approved regions."
        review_date    = "2026-12-31"
      }
    }

    # The deployment binding is supplied by this example root, not embedded in
    # portable policy content.
    require_cost_centre_tag = {
      source_type         = "custom"
      name                = "require-cost-centre-tag"
      display_name        = "Require cost centre tag"
      description         = "Audit resources that do not have a cost centre tag."
      mode                = "Indexed"
      management_group_id = var.management_group_id
      version             = "1.0.0"
      supported_effects   = ["Audit", "Disabled"]

      parameters = {
        tagName = {
          type = "String"
          metadata = {
            displayName = "Tag name"
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

      governance = {
        requirement_id = "REQ-TAGS-001"
        owner          = "platform-team"
        rationale      = "Cost allocation requires a cost centre tag."
        review_date    = "2026-12-31"
      }
    }
  }

  native_initiatives = {
    security_baseline = {
      display_name = "Security baseline"
      description  = "Synthetic initiative composed from catalogue definition references."
      version      = "1.0.0"

      metadata = {
        category = "Security"
      }

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

          group_names        = ["location_governance"]
          version_constraint = "1.*.*"
        },
        {
          reference_id   = "require_cost_centre_tag"
          definition_key = "require_cost_centre_tag"
        }
      ]

      policy_definition_groups = [
        {
          name         = "location_governance"
          display_name = "Location governance"
        }
      ]
    }
  }
}

output "definitions" {
  description = "Canonical definitions for modules/definitions."
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
