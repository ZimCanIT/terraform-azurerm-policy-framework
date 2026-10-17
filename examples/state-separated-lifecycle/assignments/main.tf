# Assignment state: the policy assignments. It reads the content state, recomputes
# the same resolution as the role-grant state from the shared intents, and reads
# the identity bindings the role-grant state created. It never creates an
# identity or a role grant.

data "terraform_remote_state" "content" {
  backend = "local"

  config = {
    path = "${path.module}/../content/terraform.tfstate"
  }
}

data "terraform_remote_state" "identity_rbac" {
  backend = "local"

  config = {
    path = "${path.module}/../identity-rbac/terraform.tfstate"
  }
}

module "shared" {
  source = "../shared"

  subscription_id = var.subscription_id
  location        = var.location
  run_id          = var.run_id
}

module "behaviour_resolution" {
  source = "../../../modules/behaviour-resolution"

  definitions = data.terraform_remote_state.content.outputs.definitions
  initiatives = data.terraform_remote_state.content.outputs.initiatives
  assignments = module.shared.assignments
}

module "assignments" {
  source = "../../../modules/assignments"

  assignments       = module.behaviour_resolution.assignments
  identity_bindings = data.terraform_remote_state.identity_rbac.outputs.assignment_bindings
}
