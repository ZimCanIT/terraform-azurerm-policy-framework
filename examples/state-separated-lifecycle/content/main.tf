# Content state: the policy definitions and the initiative. Its two outputs are
# the only thing the other states read from it.

module "shared" {
  source = "../shared"

  subscription_id = var.subscription_id
  location        = var.location
  run_id          = var.run_id
}

module "catalogue" {
  source = "../../../modules/catalogue"

  native_definitions = local.native_definitions
  native_initiatives = local.native_initiatives
}

module "content" {
  source = "../../../modules/content"

  definitions = module.catalogue.definitions
  initiatives = module.catalogue.initiatives
}
