module "catalogue" {
  source = "./modules/catalogue"

  initiative_directory         = var.catalogue.initiative_directory
  custom_definition_directory  = var.catalogue.custom_definition_directory
  built_in_reference_directory = var.catalogue.built_in_reference_directory
  allow_empty_sources          = var.catalogue.allow_empty_sources
  native_definitions           = var.catalogue.native_definitions
  native_initiatives           = var.catalogue.native_initiatives
}

module "definitions" {
  source = "./modules/definitions"
  # Caller entries merge over catalogue entries: an empty catalogue leaves the
  # caller input alone and a matching key overrides the catalogue record.
  definitions = merge(module.catalogue.definitions, var.definitions)
}

module "initiatives" {
  source      = "./modules/initiatives"
  initiatives = merge(module.catalogue.initiatives, var.initiatives)
  definitions = module.definitions.definitions
}

module "behaviour_resolution" {
  source      = "./modules/behaviour-resolution"
  definitions = module.definitions.definitions
  initiatives = module.initiatives.initiatives
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
    keys(module.definitions.definitions),
    keys(module.initiatives.initiatives),
    flatten([
      for initiative in values(module.initiatives.initiatives) : [
        for member in try(initiative.policy_definition_references, []) : member.reference_id
      ]
    ])
  ))
  assignment_inventory     = toset(keys(var.assignments))
  external_control_keys    = var.external_control_keys
  external_assignment_keys = var.external_assignment_keys
}

module "remediations" {
  source               = "./modules/remediations"
  resolved_assignments = local.assignment_lifecycle
  # A request that names an assignment created by this configuration cannot
  # know its Azure assignment ID before apply, so the root injects the created
  # ID from the assignment key. Requests whose assignment_key has no created
  # assignment keep the caller's policy_assignment_id unchanged and remain
  # subject to the remediations module's own fail-closed validation.
  requests = {
    for key, request in var.remediation_requests :
    key => merge(request, {
      policy_assignment_id = try(module.assignments.assignments[request.assignment_key].id, request.policy_assignment_id)
    })
  }
  discovery_evidence = var.discovery_evidence
}

module "exemptions" {
  source          = "./modules/exemptions"
  assignments     = local.assignment_lifecycle
  exemptions      = var.exemptions
  evaluation_time = var.evaluation_time
}
