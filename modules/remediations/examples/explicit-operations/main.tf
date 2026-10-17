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

module "remediations" {
  source = "../.."

  resolved_assignments = {
    assignment = {
      assignment = {
        id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/example"
      }
      intent = {
        scope = {
          type = "subscription"
          id   = "/subscriptions/00000000-0000-0000-0000-000000000000"
        }
      }
      resolved = {
        effective_effect        = "DeployIfNotExists"
        policy_definition_id    = "/providers/Microsoft.Authorization/policyDefinitions/example"
        members                 = []
        member_reference_ids    = []
        remediation_eligibility = "eligible"
        remediation_reason      = "The synthetic direct policy definition is eligible for remediation."
        required_roles = [{
          role_definition_id = "/providers/Microsoft.Authorization/roleDefinitions/00000000-0000-0000-0000-000000000001"
          purpose            = "synthetic remediation"
          grant_scope        = "/subscriptions/00000000-0000-0000-0000-000000000000"
        }]
      }
    }
  }

  requests = {
    discover = {
      mode                 = "discovery"
      assignment_key       = "assignment"
      scope_type           = "subscription"
      scope_id             = "/subscriptions/00000000-0000-0000-0000-000000000000"
      policy_assignment_id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/example"
      role_scope           = "/subscriptions/00000000-0000-0000-0000-000000000000"
      approval_reference   = "CAB-SYNTHETIC"
      resource_count       = 10
      location_filters     = ["westeurope"]
    }
  }

  discovery_evidence = {
    discover = {
      targets = [{
        resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example/providers/Microsoft.Storage/storageAccounts/example"
        location    = "westeurope"
      }]
    }
  }
}

output "operations" {
  value = {
    requested  = module.remediations.requested_operations
    discovered = module.remediations.discovered_operations
    blocked    = module.remediations.blocked_operations
    created    = module.remediations.created_operations
  }
}
