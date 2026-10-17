locals {
  requirement_records = {
    for key, requirement in var.requirements :
    key => {
      requirement_key = key
      title           = try(requirement.title, null)
      owner           = try(requirement.owner, null)
      rationale       = try(requirement.rationale, null)
      review_date     = try(requirement.review_date, null)
      control_keys    = try(requirement.control_keys, [])
      assignment_keys = try(requirement.assignment_keys, [])
      status          = try(requirement.status, "proposed")
    }
  }

  reference_records = flatten([
    for requirement_key, requirement in local.requirement_records : concat(
      [for key in try(tolist(requirement.control_keys), []) : {
        requirement_key = requirement_key
        reference_kind  = "control"
        reference_key   = key
        status = contains(var.external_control_keys, key) ? "external" : (
          var.control_inventory == null ? "unknown" : (
            contains(var.control_inventory, key) ? "internal" : "missing"
          )
        )
      }],
      [for key in try(tolist(requirement.assignment_keys), []) : {
        requirement_key = requirement_key
        reference_kind  = "assignment"
        reference_key   = key
        status = contains(var.external_assignment_keys, key) ? "external" : (
          var.assignment_inventory == null ? "unknown" : (
            contains(var.assignment_inventory, key) ? "internal" : "missing"
          )
        )
      }]
    )
  ])

  # Group source references once. Output shaping and status summaries then use
  # the requirement's small local collection instead of rescanning all refs.
  reference_records_by_requirement = {
    for reference in local.reference_records :
    reference.requirement_key => reference...
  }

  # Reference status keyed by kind then reference key, one pass per requirement.
  references_by_kind = {
    for requirement_key, references in local.reference_records_by_requirement :
    requirement_key => {
      for kind in ["control", "assignment"] : kind => {
        for reference in references : reference.reference_key => { status = reference.status }
        if reference.reference_kind == kind
      }
    }
  }

  reference_statuses = {
    for requirement_key, references in local.reference_records_by_requirement :
    requirement_key => toset([for reference in references : reference.status])
  }

  reference_summaries = {
    for requirement_key, statuses in local.reference_statuses :
    requirement_key => {
      traceability_status = contains(statuses, "unknown") ? "unknown" : (
        contains(statuses, "missing") ? "missing" : (
          contains(statuses, "internal") && contains(statuses, "external") ? "mixed" : (
            contains(statuses, "external") ? "external" : "internal"
          )
        )
      )
      traceable = contains(statuses, "unknown") ? null : (
        try(trimspace(local.requirement_records[requirement_key].owner), "") != "" &&
        length(setsubtract(statuses, toset(["internal"]))) == 0
      )
      traceability_complete = contains(statuses, "unknown") ? null : (
        try(trimspace(local.requirement_records[requirement_key].owner), "") != "" &&
        length(statuses) > 0 &&
        length(setsubtract(statuses, toset(["internal", "external"]))) == 0
      )
    }
  }

  traceability = {
    for key, requirement in local.requirement_records :
    key => {
      requirement_key       = key
      owner                 = requirement.owner
      control_keys          = requirement.control_keys
      assignment_keys       = requirement.assignment_keys
      review_date           = requirement.review_date
      status                = requirement.status
      control_references    = try(local.references_by_kind[key].control, {})
      assignment_references = try(local.references_by_kind[key].assignment, {})
      traceability_status   = try(local.reference_summaries[key].traceability_status, "unknown")
      traceable             = try(local.reference_summaries[key].traceable, null)
      traceability_complete = try(local.reference_summaries[key].traceability_complete, null)
    }
  }
}

# Validation guard only: no input, so it never plans a change on its own.
resource "terraform_data" "contract_guard" {
  lifecycle {
    precondition {
      condition = alltrue([
        for key, requirement in local.requirement_records :
        trimspace(key) != "" && try(trimspace(requirement.owner), "") != "" && length(requirement.control_keys) > 0 && length(requirement.assignment_keys) > 0
      ])
      error_message = "Each governance requirement needs an owner, at least one control key and at least one assignment key."
    }

    precondition {
      condition     = alltrue([for reference in local.reference_records : reference.status != "missing"])
      error_message = "Governance requirement references must exist in the supplied inventories or be explicitly declared external. Missing references: ${join(", ", [for reference in local.reference_records : "${reference.requirement_key}.${reference.reference_kind}[${reference.reference_key}]" if reference.status == "missing"])}."
    }
  }
}
