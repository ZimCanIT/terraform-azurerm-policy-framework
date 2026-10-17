run "verified_internal_references" {
  command = plan

  variables {
    requirements = {
      storage-audit = {
        owner           = "platform-governance"
        control_keys    = ["custom-storage-audit"]
        assignment_keys = ["storage-audit-subscription"]
      }
    }
    control_inventory    = ["custom-storage-audit"]
    assignment_inventory = ["storage-audit-subscription"]
  }

  assert {
    condition     = output.traceability["storage-audit"].traceability_status == "internal"
    error_message = "Known control and assignment keys must be reported as verified internal references."
  }

  assert {
    condition     = output.traceability["storage-audit"].traceable == true && output.traceability["storage-audit"].traceability_complete == true
    error_message = "A named owner with fully verified internal references must be traceable and complete."
  }

  assert {
    condition     = output.traceability["storage-audit"].control_references["custom-storage-audit"].status == "internal" && output.traceability["storage-audit"].assignment_references["storage-audit-subscription"].status == "internal"
    error_message = "Each control and assignment reference must retain its own verified status."
  }
}

run "explicit_external_references" {
  command = plan

  variables {
    requirements = {
      external-control = {
        owner           = "platform-governance"
        control_keys    = ["external-control-id"]
        assignment_keys = ["external-assignment-id"]
      }
    }
    control_inventory        = []
    assignment_inventory     = []
    external_control_keys    = ["external-control-id"]
    external_assignment_keys = ["external-assignment-id"]
  }

  assert {
    condition     = output.traceability["external-control"].traceability_status == "external"
    error_message = "Explicitly external references must be distinguished from verified internal references."
  }

  assert {
    condition     = output.traceability["external-control"].traceable == false && output.traceability["external-control"].traceability_complete == true
    error_message = "External declarations account for the references without claiming internal traceability."
  }
}

run "requirements_group_references_independently" {
  command = plan

  variables {
    requirements = {
      internal-requirement = {
        owner           = "platform-governance"
        control_keys    = ["internal-control"]
        assignment_keys = ["internal-assignment"]
      }
      mixed-requirement = {
        owner           = "security-governance"
        control_keys    = ["internal-control", "external-control"]
        assignment_keys = ["external-assignment"]
      }
    }
    control_inventory        = ["internal-control"]
    assignment_inventory     = ["internal-assignment"]
    external_control_keys    = ["external-control"]
    external_assignment_keys = ["external-assignment"]
  }

  assert {
    condition     = output.traceability["internal-requirement"].traceability_status == "internal" && output.traceability["internal-requirement"].traceable == true
    error_message = "Internal references from one requirement must not inherit another requirement's external status."
  }

  assert {
    condition     = output.traceability["mixed-requirement"].traceability_status == "mixed" && output.traceability["mixed-requirement"].traceable == false && output.traceability["mixed-requirement"].traceability_complete == true
    error_message = "Mixed internal and external references must be grouped only under their own requirement."
  }

  assert {
    condition     = length(output.traceability["internal-requirement"].control_references) == 1 && length(output.traceability["internal-requirement"].assignment_references) == 1 && length(output.traceability["mixed-requirement"].control_references) == 2 && length(output.traceability["mixed-requirement"].assignment_references) == 1
    error_message = "Per-kind reference maps must use each requirement's grouped records."
  }
}

run "unknown_inventory_stays_unknown" {
  command = plan

  variables {
    requirements = {
      pending-inventory = {
        owner           = "platform-governance"
        control_keys    = ["not-yet-verified-control"]
        assignment_keys = ["not-yet-verified-assignment"]
      }
    }
  }

  assert {
    condition     = output.traceability["pending-inventory"].traceability_status == "unknown"
    error_message = "Absent inventories must remain unknown rather than being treated as empty."
  }

  assert {
    condition     = output.traceability["pending-inventory"].traceable == null && output.traceability["pending-inventory"].traceability_complete == null
    error_message = "Unknown inventories must not become verified traceability or verified absence."
  }
}

run "known_missing_reference_blocks_with_keyed_context" {
  command         = plan
  expect_failures = [terraform_data.contract_guard]

  variables {
    requirements = {
      storage-audit = {
        owner           = "platform-governance"
        control_keys    = ["missing-control"]
        assignment_keys = ["storage-audit-subscription"]
      }
    }
    control_inventory    = ["another-control"]
    assignment_inventory = ["storage-audit-subscription"]
  }
}

run "malformed_duplicate_references_reject" {
  command         = plan
  expect_failures = [var.requirements]

  variables {
    requirements = {
      storage-audit = {
        owner           = "platform-governance"
        control_keys    = ["same-control", "same-control"]
        assignment_keys = ["storage-audit-subscription"]
      }
    }
  }
}

# Container boundary diagnostics: null and scalar inputs must fail at the variable boundary with the contract message.
run "requirements_null" {
  command = plan
  variables {
    requirements = null
  }
  expect_failures = [var.requirements]
}

run "requirements_scalar" {
  command = plan
  variables {
    requirements = 42
  }
  expect_failures = [var.requirements]
}
