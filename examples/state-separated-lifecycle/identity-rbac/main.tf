# Role-grant state: the assignment identities and their least-privilege role
# grants. It reads the content state and recomputes the resolution from the
# shared intents. It never creates an assignment.

data "terraform_remote_state" "content" {
  backend = "local"

  config = {
    path = "${path.module}/../content/terraform.tfstate"
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

module "identity_rbac" {
  source = "../../../modules/identity-rbac"

  assignments = module.behaviour_resolution.assignments
}
