module "catalogue" {
  source = "./modules/catalogue"

  initiative_directory         = var.catalogue.initiative_directory
  custom_definition_directory  = var.catalogue.custom_definition_directory
  built_in_reference_directory = var.catalogue.built_in_reference_directory
  allow_empty_sources          = var.catalogue.allow_empty_sources
  native_definitions           = var.catalogue.native_definitions
  native_initiatives           = var.catalogue.native_initiatives
}

module "content" {
  source = "./modules/content"
  # Caller entries merge over catalogue entries: an empty catalogue leaves the
  # caller input alone and a matching key overrides the catalogue record.
  definitions = merge(module.catalogue.definitions, var.definitions)
  initiatives = merge(module.catalogue.initiatives, var.initiatives)
}

module "behaviour_resolution" {
  source      = "./modules/behaviour-resolution"
  definitions = module.content.definitions
  initiatives = module.content.initiatives
  assignments = var.assignments
}

module "identity_rbac" {
  source      = "./modules/identity-rbac"
  assignments = module.behaviour_resolution.assignments
}

module "assignments" {
  source      = "./modules/assignments"
  assignments = module.behaviour_resolution.assignments
  identity_bindings = {
    for key, record in module.identity_rbac.identity_rbac : key => record.assignment_binding
    if record.assignment_binding != null
  }
}

module "governance" {
  source       = "./governance/requirements-and-ownership"
  requirements = var.requirements
  control_inventory = toset(concat(
    keys(module.content.definitions),
    keys(module.content.initiatives),
    flatten([
      for initiative in values(module.content.initiatives) : [
        for member in try(initiative.policy_definition_references, []) : member.reference_id
      ]
    ])
  ))
  assignment_inventory     = toset(keys(var.assignments))
  external_control_keys    = var.external_control_keys
  external_assignment_keys = var.external_assignment_keys
}

module "operations" {
  source               = "./modules/operations"
  resolved_assignments = local.assignment_lifecycle
  # A request that names an assignment created by this configuration cannot
  # know its Azure assignment ID before apply, so the root injects the created
  # ID from the assignment key. Requests whose assignment_key has no created
  # assignment keep the caller's policy_assignment_id unchanged and remain
  # subject to the operations module's own fail-closed validation.
  requests = {
    for key, request in var.remediation_requests :
    key => merge(request, {
      policy_assignment_id = try(module.assignments.assignments[request.assignment_key].id, request.policy_assignment_id)
    })
  }
  discovery_evidence = var.discovery_evidence
  exemptions         = var.exemptions
  evaluation_time    = var.evaluation_time
}
