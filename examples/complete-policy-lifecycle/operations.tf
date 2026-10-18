# Governed operations for the complete policy lifecycle example.
#
# Stage sequencing (goal R9): stage 1 applies with create_exemption false, so
# the framework exemption input is empty and no exemption can invalidate the
# pending remediation assertion on the target. Stage 2 applies with
# create_exemption true and exemption_assignment_id set from the stage 1
# exemption_assignment_id output, creating the exemption only after the
# remediation assertion has completed.
#
# The framework wiring in main.tf supplies these locals:
#   remediation_requests = local.remediation_requests
#   exemptions           = local.exemptions

# Deterministic exemption status classification: timestamp() is unknown at
# plan time, so status outputs would churn on every plan without a fixed
# evaluation instant. Runs pass -var evaluation_time once per run.

locals {
  # Explicit eligible remediation request for the modify-tag-rg assignment.
  #
  # policy_assignment_id is omitted on purpose. The operations module takes it
  # from the assignment that assignment_key names. The assignments module
  # creates that assignment in this configuration, so the request always
  # targets the assignment this example created and no ID is copied by hand.
  # A value supplied here would have to equal that created ID, or the request
  # is blocked.
  #
  # role_scope, approval_reference and policy_definition_reference_id are
  # required by the operations safety contract for an execute request:
  # explicit approval evidence, a role scope matching the resolved
  # required-role grant scope (the least-privilege grant at the target
  # resource group) and, for an initiative-member record, the member reference
  # the remediation targets.
  remediation_requests = {
    "remediate-tag-rg" = {
      mode                           = "execute"
      assignment_key                 = "modify-tag-rg"
      scope_type                     = "resource_group"
      scope_id                       = var.target_resource_group_id
      member_reference_id            = "add-costcentre-tag-member"
      policy_definition_reference_id = "add-costcentre-tag-member"
      resource_discovery_mode        = "ExistingNonCompliant"
      location_filters               = [var.target_location]
      resource_count                 = 50
      parallel_deployments           = 1
      role_scope                     = var.target_resource_group_id
      approval_reference             = "CAB-ZCTFP-REMEDIATE-TAG-RG"
    }
  }

  # Governed exemption request for stage 2. assignment_id is the
  # caller-supplied created assignment ID from stage 1, which the operations
  # module verifies against the resolved assignment inventory before creating
  # the resource-group-scoped exemption.
  exemption_requests = {
    "exempt-tag-rg-uat" = {
      request_mode  = "create"
      assignment_id = var.exemption_assignment_id
      scope = {
        type = "resource_group"
        id   = var.target_resource_group_id
      }
      owner                = "platform-governance"
      reason               = "Temporary UAT window while the CostCentre tag remediation is verified"
      approval_reference   = "CAB-ZCTFP-EXEMPT-TAG-RG"
      ticket_reference     = "CHG-ZCTFP-0001"
      category             = "Mitigated"
      compensating_control = "Platform governance reviews the exempted target weekly until the exemption expires"
      expires_on           = var.exemption_expiry
      display_name         = "UAT exemption for the CostCentre tag requirement"
      description          = "Governed exemption created after the remediation assertion completed"
    }
  }

  # Supplied to the framework exemption input: empty in stage 1 so no exemption
  # exists while the remediation assertion is pending, and the full request set
  # in stage 2. The filtered for-expression keeps stage 1 genuinely empty; a
  # conditional against an empty object would unify to an object with a null
  # request and trip the exemptions validation.
  exemptions = { for key, request in local.exemption_requests : key => request if var.create_exemption }
}
