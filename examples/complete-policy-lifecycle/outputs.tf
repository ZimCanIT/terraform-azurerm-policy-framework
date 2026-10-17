# Review outputs for the complete policy lifecycle example.
#
# Terraform outputs record request intent and resource identity. Compliance
# results, remediation task status and execution evidence remain external
# operational records read from Azure, never from Terraform state.

output "resolved_assignments" {
  description = "Framework resolved assignment records keyed by stable assignment key, including the created assignment IDs used for the governance and exemption hand-offs."
  value       = module.framework.resolved_assignments
}

output "governance" {
  description = "Governance requirement and ownership traceability for the assignments this example creates."
  value       = module.framework.governance
}

output "exemption_assignment_id" {
  description = "Created policy assignment ID for the modify-tag-rg assignment. Supply it as exemption_assignment_id in the stage 2 run that creates the governed exemption."
  value       = try(module.framework.resolved_assignments["modify-tag-rg"].assignment.id, null)
}

output "resolved_assignment_id" {
  description = "Created policy assignment ID for the modify-tag-rg assignment, used by the integration harness for read-back assertions."
  value       = try(module.framework.resolved_assignments["modify-tag-rg"].assignment.id, null)
}

output "definition_ids" {
  description = "Created or referenced policy definition resource IDs keyed by catalogue key, used by the integration harness for read-back assertions."
  value = {
    for key, definition in module.framework.definitions : key => definition.id
  }
}

output "set_definition_id" {
  description = "Created initiative (policy set definition) resource ID, used by the integration harness for read-back assertions."
  value       = try(module.framework.initiatives["tag-governance"].id, null)
}

output "remediation_and_exemption" {
  description = "Compact operational review of the explicit remediation request and the governed exemption lifecycle."
  value = {
    remediations = {
      for key, operation in module.framework.remediations :
      key => {
        mode                    = operation.mode
        status                  = operation.status
        assignment_key          = operation.assignment_key
        member_reference_id     = operation.member_reference_id
        remediation_eligibility = operation.remediation_eligibility
        remediation_reason      = operation.remediation_reason
        blocked_reasons         = operation.blocked_reasons
      }
    }
    exemptions = {
      for key, request in module.framework.exemptions.requested :
      key => {
        request_mode = request.request_mode
        owner        = request.owner
        category     = request.category
        expires_on   = request.expires_on
        active       = contains(keys(module.framework.exemptions.active), key)
        expired      = contains(keys(module.framework.exemptions.expired), key)
        blocked      = contains(keys(module.framework.exemptions.blocked), key)
        rejected     = contains(keys(module.framework.exemptions.rejected), key)
        azure_status = try(module.framework.exemptions.active[key].azure_status, null)
      }
    }
  }
}
