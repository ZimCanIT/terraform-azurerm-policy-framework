# Operations state: the explicit remediation and the governed exemption. It reads
# only the assignment state. The module takes the assignment ID from the
# lifecycle binding in that state, so no ID is copied by hand.

data "terraform_remote_state" "assignments" {
  backend = "local"

  config = {
    path = "${path.module}/../assignments/terraform.tfstate"
  }
}

module "shared" {
  source = "../shared"

  subscription_id = var.subscription_id
  location        = var.location
  run_id          = var.run_id
}

locals {
  resolved_assignments = data.terraform_remote_state.assignments.outputs.resolved_assignments

  # policy_assignment_id is omitted on purpose. A value supplied here would have
  # to equal the created assignment ID, or the request is blocked.
  #
  # role_scope, approval_reference and policy_definition_reference_id are
  # required for an execute request: explicit approval evidence, a role scope
  # equal to the least-privilege grant scope, and the initiative member the
  # remediation targets.
  remediation_requests = {
    "remediate-tag-rg" = {
      mode                           = "execute"
      assignment_key                 = "modify-tag-rg"
      scope_type                     = "resource_group"
      scope_id                       = module.shared.target.resource_group_id
      member_reference_id            = "add-costcentre-tag-member"
      policy_definition_reference_id = "add-costcentre-tag-member"
      resource_discovery_mode        = "ExistingNonCompliant"
      location_filters               = [module.shared.location]
      resource_count                 = 50
      parallel_deployments           = 1
      role_scope                     = module.shared.target.resource_group_id
      approval_reference             = "CAB-ZCTFP-STATES-REMEDIATE"
    }
  }

  exemption_requests = {
    "exempt-tag-rg" = {
      request_mode         = "create"
      assignment_id        = local.resolved_assignments["modify-tag-rg"].assignment.id
      scope                = { type = "resource_group", id = module.shared.target.resource_group_id }
      owner                = "platform-governance"
      reason               = "Temporary window while the CostCentre tag remediation is verified"
      approval_reference   = "CAB-ZCTFP-STATES-EXEMPT"
      ticket_reference     = "CHG-ZCTFP-STATES-0001"
      category             = "Mitigated"
      compensating_control = "Platform governance reviews the exempted target weekly until the exemption expires"
      expires_on           = var.exemption_expiry
      display_name         = "Exemption for the CostCentre tag requirement"
      description          = "Governed exemption created after the remediation completed"
    }
  }

  # A filtered for expression keeps the first apply genuinely empty. A
  # conditional against an empty object would unify to an object with a null
  # request and fail the exemptions validation.
  exemptions = { for key, request in local.exemption_requests : key => request if var.create_exemption }
}

module "operations" {
  source = "../../../modules/operations"

  resolved_assignments = local.resolved_assignments
  requests             = local.remediation_requests
  exemptions           = local.exemptions
  evaluation_time      = var.evaluation_time
}
