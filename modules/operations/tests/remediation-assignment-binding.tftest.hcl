mock_provider "azurerm" {}

# A request may omit policy_assignment_id. The module then takes the ID from
# the lifecycle binding of the assignment the request names, and a supplied ID
# must equal that binding.

variables {
  resolved_assignments = {
    bound = {
      assignment = {
        id   = "/subscriptions/11111111-1111-1111-1111-111111111111/providers/Microsoft.Authorization/policyAssignments/bound"
        name = "bound"
      }
      intent = {
        scope = { type = "subscription", id = "/subscriptions/11111111-1111-1111-1111-111111111111" }
      }
      resolved = {
        policy_definition_id    = "/providers/Microsoft.Authorization/policyDefinitions/example"
        members                 = []
        member_reference_ids    = []
        remediation_eligibility = "eligible"
        remediation_reason      = "The resolved direct policy definition is eligible for remediation."
        required_roles          = [{ grant_scope = "/subscriptions/11111111-1111-1111-1111-111111111111" }]
      }
    }
  }
}

run "omitted_policy_assignment_id_takes_the_lifecycle_binding" {
  command = plan

  variables {
    requests = {
      omitted = {
        mode               = "execute"
        assignment_key     = "bound"
        scope_type         = "subscription"
        scope_id           = "/subscriptions/11111111-1111-1111-1111-111111111111"
        role_scope         = "/subscriptions/11111111-1111-1111-1111-111111111111"
        approval_reference = "CAB-BINDING"
        resource_count     = 5
      }
      explicit_null = {
        mode                 = "execute"
        assignment_key       = "bound"
        scope_type           = "subscription"
        scope_id             = "/subscriptions/11111111-1111-1111-1111-111111111111"
        policy_assignment_id = null
        role_scope           = "/subscriptions/11111111-1111-1111-1111-111111111111"
        approval_reference   = "CAB-BINDING"
        resource_count       = 5
      }
    }
  }

  assert {
    condition     = length(output.created_operations) == 2 && length(output.blocked_operations) == 0
    error_message = "A request that omits policy_assignment_id, or sets it to null, must be accepted when its assignment has a binding."
  }

  assert {
    condition = alltrue([
      for key, operation in output.created_operations :
      operation.policy_assignment_id == var.resolved_assignments["bound"].assignment.id
    ])
    error_message = "The derived policy_assignment_id in the operation record must equal the lifecycle binding ID."
  }

  assert {
    condition     = azurerm_subscription_policy_remediation.this["omitted"].policy_assignment_id == var.resolved_assignments["bound"].assignment.id
    error_message = "The remediation resource must receive the ID derived from the lifecycle binding."
  }
}

run "reject_supplied_policy_assignment_id_that_differs_from_the_binding" {
  command = plan

  variables {
    requests = {
      different = {
        mode                 = "execute"
        assignment_key       = "bound"
        scope_type           = "subscription"
        scope_id             = "/subscriptions/11111111-1111-1111-1111-111111111111"
        policy_assignment_id = "/subscriptions/11111111-1111-1111-1111-111111111111/providers/Microsoft.Authorization/policyAssignments/other"
        role_scope           = "/subscriptions/11111111-1111-1111-1111-111111111111"
        approval_reference   = "CAB-BINDING"
        resource_count       = 5
      }
    }
  }

  expect_failures = [terraform_data.remediation_contract_guard]
}

run "omitted_policy_assignment_id_without_a_binding_stays_unbound" {
  command = plan

  variables {
    resolved_assignments = {
      bound = {
        assignment = { id = null, name = "bound" }
        intent = {
          scope = { type = "subscription", id = "/subscriptions/11111111-1111-1111-1111-111111111111" }
        }
        resolved = {
          policy_definition_id    = "/providers/Microsoft.Authorization/policyDefinitions/example"
          members                 = []
          member_reference_ids    = []
          remediation_eligibility = "eligible"
          remediation_reason      = "The resolved direct policy definition is eligible for remediation."
          required_roles          = [{ grant_scope = "/subscriptions/11111111-1111-1111-1111-111111111111" }]
        }
      }
    }

    requests = {
      omitted = {
        mode           = "disabled"
        assignment_key = "bound"
        scope_type     = "subscription"
        scope_id       = "/subscriptions/11111111-1111-1111-1111-111111111111"
      }
    }
  }

  assert {
    condition     = output.skipped_operations["omitted"].policy_assignment_id == null
    error_message = "A request without a supplied ID must stay unbound while its assignment has no ID. It must not receive an empty or invented one."
  }

  assert {
    condition     = contains(output.skipped_operations["omitted"].blocked_reasons, "assignment_id_unknown")
    error_message = "The missing binding must be reported as assignment_id_unknown, so it is never read as a match."
  }
}

run "reject_execute_request_whose_assignment_has_no_binding" {
  command = plan

  variables {
    resolved_assignments = {
      bound = {
        assignment = { id = null, name = "bound" }
        intent = {
          scope = { type = "subscription", id = "/subscriptions/11111111-1111-1111-1111-111111111111" }
        }
        resolved = {
          policy_definition_id    = "/providers/Microsoft.Authorization/policyDefinitions/example"
          members                 = []
          member_reference_ids    = []
          remediation_eligibility = "eligible"
          remediation_reason      = "The resolved direct policy definition is eligible for remediation."
          required_roles          = [{ grant_scope = "/subscriptions/11111111-1111-1111-1111-111111111111" }]
        }
      }
    }

    requests = {
      omitted = {
        mode               = "execute"
        assignment_key     = "bound"
        scope_type         = "subscription"
        scope_id           = "/subscriptions/11111111-1111-1111-1111-111111111111"
        role_scope         = "/subscriptions/11111111-1111-1111-1111-111111111111"
        approval_reference = "CAB-BINDING"
        resource_count     = 5
      }
    }
  }

  expect_failures = [terraform_data.remediation_contract_guard]
}

run "reject_blank_supplied_policy_assignment_id" {
  command = plan

  variables {
    requests = {
      blank = {
        mode                 = "execute"
        assignment_key       = "bound"
        scope_type           = "subscription"
        scope_id             = "/subscriptions/11111111-1111-1111-1111-111111111111"
        policy_assignment_id = ""
        role_scope           = "/subscriptions/11111111-1111-1111-1111-111111111111"
        approval_reference   = "CAB-BINDING"
        resource_count       = 5
      }
    }
  }

  expect_failures = [var.requests]
}

run "reject_malformed_supplied_policy_assignment_id" {
  command = plan

  variables {
    requests = {
      malformed = {
        mode                 = "execute"
        assignment_key       = "bound"
        scope_type           = "subscription"
        scope_id             = "/subscriptions/11111111-1111-1111-1111-111111111111"
        policy_assignment_id = "not-an-assignment-id"
        role_scope           = "/subscriptions/11111111-1111-1111-1111-111111111111"
        approval_reference   = "CAB-BINDING"
        resource_count       = 5
      }
    }
  }

  expect_failures = [var.requests]
}
