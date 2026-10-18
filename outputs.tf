output "catalogue" {
  description = "Canonical catalogue outputs from the source adapter."
  value = {
    definitions    = module.catalogue.definitions
    initiatives    = module.catalogue.initiatives
    source_summary = module.catalogue.source_summary
  }
}

output "definitions" {
  description = "Canonical definition resources keyed by stable catalogue key."
  value       = module.content.definitions
}

output "initiatives" {
  description = "Canonical initiative resources keyed by stable catalogue key."
  value       = module.content.initiatives
}

output "resolved_assignments" {
  description = "Shared resolved-assignment contract keyed by stable assignment key, including created assignment IDs and names."
  value       = module.assignments.resolved_assignments
}

output "lifecycle_resource_ids" {
  description = "Azure resource IDs reported by the assignment, identity/RBAC, remediation and exemption resources."
  value = {
    assignments = {
      for key, record in module.assignments.resolved_assignments : key => try(record.assignment.id, null)
    }
    identities = {
      for key, record in module.identity_rbac.identity_rbac : key => try(record.identity_id, null)
    }
    principals = {
      for key, record in module.identity_rbac.identity_rbac : key => try(record.principal_id, null)
    }
    role_assignments = {
      for key, record in module.identity_rbac.identity_rbac : key => {
        for grant in record.role_grants : "${grant.purpose}|${grant.role_definition_id}|${grant.grant_scope}" => grant.role_assignment_id
      }
    }
    remediations = {
      for key, record in module.operations.created_operations : key => record.id
    }
    exemptions = module.operations.created_exemption_ids
  }
}

output "governance" {
  description = "Governance requirement and ownership traceability outputs."
  value = {
    requirements = module.governance.requirements
    traceability = module.governance.traceability
  }
}

output "remediations" {
  description = "Requested remediation operations keyed by operation key, with mode, status, eligibility and blocked reasons."
  value       = module.operations.requested_operations
}

output "exemptions" {
  description = "Exemption lifecycle views: requested, approved, active, expired, blocked and rejected, keyed by request key."
  value       = module.operations.status_contract
}

output "plan_summary" {
  description = "Scope counts, management-group inheritance, exclusion and selector totals and rollout stages derived from the resolved assignments."
  value       = local.plan_summary
}

output "replacement_review" {
  description = "Assignment and identity attributes whose change replaces an Azure resource."
  value = {
    assignments = module.assignments.replacement_review
    identity    = module.identity_rbac.replacement_impact
  }
}
