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

module "exemptions" {
  source = "../../"

  assignments = {
    example = {
      assignment_key = "example"
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
        members              = []
        member_reference_ids = []
      }
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
}
