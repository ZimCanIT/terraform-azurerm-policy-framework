terraform {
  required_version = ">= 1.12.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 5.0.0, < 6.0.0"
    }
  }
}

# Caller-owned provider configuration: reusable child modules must not declare
# their own azurerm provider blocks. This example composes the module exactly
# as a consuming root module would.
provider "azurerm" {
  features {}
}

module "identity_rbac" {
  source = "../../"

  assignments = {
    deploy_storage = {
      intent = {
        scope = {
          type = "resource_group"
          id   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example-rg"
        }
      }
      resolved = {
        effective_effect = "DeployIfNotExists"
        identity = {
          required            = true
          strategy            = "user_assigned"
          name_basis          = "storage-deploy"
          location            = "westeurope"
          resource_group_name = "identity-rg"
          rationale           = "Resolved deployment identity requirement"
        }
        list_fields = {
          role_definition_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/00000000-0000-0000-0000-000000000000"]
        }
        required_roles = [{
          role_definition_id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/00000000-0000-0000-0000-000000000000"
          purpose            = "deploy resources"
          grant_scope        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example-rg"
        }]
      }
    }

    audit_storage = {
      intent = {
        scope = {
          type = "subscription"
          id   = "/subscriptions/00000000-0000-0000-0000-000000000000"
        }
      }
      resolved = {
        effective_effect = "Audit"
        list_fields = {
          role_definition_ids = []
        }
        identity = {
          required = false
          strategy = "none"
        }
        required_roles = []
      }
    }
  }
}

output "identity_rbac" {
  value = module.identity_rbac.identity_rbac
}
