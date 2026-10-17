variable "run_id" {
  type    = string
  default = "focused-test"
}

resource "terraform_data" "definition_id" {
  input = "definition-${var.run_id}"
}

resource "terraform_data" "initiative_id" {
  input = "initiative-${var.run_id}"
}

module "resolution" {
  source = "../../../"

  definitions = {
    deploy = {
      id                  = terraform_data.definition_id.id
      supported_effects   = ["DeployIfNotExists"]
      capabilities        = { default_effect = "DeployIfNotExists" }
      role_definition_ids = ["/providers/Microsoft.Authorization/roleDefinitions/11111111-1111-1111-1111-111111111111"]
    }
  }

  initiatives = {
    deploy_set = {
      id                = terraform_data.initiative_id.id
      created_by_module = "modules/initiatives"
      policy_definition_references = [{
        reference_id         = "deploy-member"
        definition_key       = "deploy"
        policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/deploy"
        role_definition_ids  = ["/providers/Microsoft.Authorization/roleDefinitions/11111111-1111-1111-1111-111111111111"]
      }]
    }
  }

  assignments = {
    direct = {
      target = { reference_id = "direct-deploy", definition_key = "deploy" }
      scope  = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000000" }
      identity = {
        strategy            = "user_assigned"
        location            = "swedencentral"
        resource_group_name = "identity-rg"
      }
    }
    initiative = {
      target = { reference_id = "deploy-member", initiative_key = "deploy_set" }
      scope  = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000000" }
      effect = "DeployIfNotExists"
      identity = {
        strategy            = "user_assigned"
        location            = "swedencentral"
        resource_group_name = "identity-rg"
      }
    }
  }
}

output "direct_effect" {
  value = module.resolution.assignments["direct"].resolved.effective_effect
}

output "direct_identity_required" {
  value = module.resolution.assignments["direct"].resolved.identity.required
}

output "direct_required_roles" {
  value = module.resolution.assignments["direct"].resolved.required_roles
}

output "initiative_effect" {
  value = module.resolution.assignments["initiative"].resolved.effective_effect
}

output "initiative_identity_required" {
  value = module.resolution.assignments["initiative"].resolved.identity.required
}

output "initiative_required_roles" {
  value = module.resolution.assignments["initiative"].resolved.required_roles
}
