terraform {
  required_version = ">= 1.12.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 5.0.0, < 6.0.0"
    }
  }
}

resource "azurerm_resource_group" "target" {
  name     = "plan-known-remediation-target"
  location = "westeurope"
}

# Stands in for an assignment created in the same apply: its ID is unknown
# until apply, which is how the assignments module reports a new assignment.
resource "terraform_data" "created_assignment" {
  input = "created-in-this-apply"
}

locals {
  subscription_id    = "/subscriptions/11111111-1111-1111-1111-111111111111"
  assignment_id      = "${local.subscription_id}/providers/Microsoft.Authorization/policyAssignments/example"
  created_assignment = "${local.subscription_id}/providers/Microsoft.Authorization/policyAssignments/${terraform_data.created_assignment.id}"
  resource_id        = "${azurerm_resource_group.target.id}/providers/Microsoft.Compute/virtualMachines/example"
  eligible_resolution = {
    policy_definition_id    = "/providers/Microsoft.Authorization/policyDefinitions/example"
    members                 = []
    member_reference_ids    = []
    remediation_eligibility = "eligible"
    remediation_reason      = "The computed target fixture has an eligible direct definition."
    required_roles          = [{ grant_scope = local.subscription_id }]
  }
}

module "operations" {
  source = "../../../"

  resolved_assignments = {
    assignment = {
      assignment = {
        id = local.assignment_id
      }
      intent = {
        scope = {
          type = "subscription"
          id   = local.subscription_id
        }
      }
      resolved = local.eligible_resolution
    }
    created = {
      assignment = {
        id = local.created_assignment
      }
      intent = {
        scope = {
          type = "subscription"
          id   = local.subscription_id
        }
      }
      resolved = local.eligible_resolution
    }
  }

  requests = {
    execute_resource_group = {
      mode                 = "execute"
      assignment_key       = "assignment"
      scope_type           = "resource_group"
      scope_id             = azurerm_resource_group.target.id
      policy_assignment_id = local.assignment_id
      role_scope           = local.subscription_id
      approval_reference   = "CAB-PLAN-KNOWN"
      resource_count       = 10
    }
    execute_resource = {
      mode                 = "execute"
      assignment_key       = "assignment"
      scope_type           = "resource"
      scope_id             = local.resource_id
      policy_assignment_id = local.assignment_id
      role_scope           = local.subscription_id
      approval_reference   = "CAB-PLAN-KNOWN"
      resource_count       = 10
    }
    # Omits policy_assignment_id: the module derives it from the binding, which
    # is unknown until apply here. The key must still be known at plan.
    execute_created_assignment = {
      mode               = "execute"
      assignment_key     = "created"
      scope_type         = "subscription"
      scope_id           = local.subscription_id
      role_scope         = local.subscription_id
      approval_reference = "CAB-PLAN-KNOWN"
      resource_count     = 10
    }
  }
}

output "planned_operation_keys" {
  value = sort(keys(module.operations.created_operations))
}
