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

module "operations" {
  source = "../.."

  # One resolved assignment record feeds both the remediation and the exemption
  # request below.
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

  exemptions = {
    example = {
      request_mode  = "create"
      assignment_id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/example"
      scope = {
        type = "subscription"
        id   = "/subscriptions/00000000-0000-0000-0000-000000000000"
      }
      owner                = "platform-governance"
      reason               = "Time-bound migration exception"
      ticket_reference     = "CHG-1234"
      category             = "Waiver"
      compensating_control = "Weekly review"
      expires_on           = "2027-01-31T00:00:00Z"
    }
  }

  # Fixed so the expiry classification does not change between plans.
  evaluation_time = "2026-10-17T00:00:00Z"
}

output "operations" {
  value = {
    requested  = module.operations.requested_operations
    discovered = module.operations.discovered_operations
    blocked    = module.operations.blocked_operations
    created    = module.operations.created_operations
  }
}

output "exemptions" {
  value = module.operations.status_contract
}
