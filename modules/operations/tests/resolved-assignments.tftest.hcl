mock_provider "azurerm" {}

# The resolved_assignments input is shared by both operation families, so its
# cross-record rules are checked here once rather than through either family.

run "reject_member_inventory_disagreement_at_the_shared_input" {
  command = plan

  variables {
    resolved_assignments = {
      subscription = {
        assignment = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/sub-assignment" }
        intent     = { scope = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000000" } }
        resolved   = { members = [{ reference_id = "member-a" }, { reference_id = "member-b" }], member_reference_ids = ["member-b", "member-a"] }
      }
    }
  }

  expect_failures = [var.resolved_assignments]
}

run "reject_two_keys_sharing_one_assignment_id" {
  command = plan

  variables {
    resolved_assignments = {
      first = {
        assignment = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/shared" }
        intent     = { scope = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000000" } }
        resolved   = { members = [], member_reference_ids = [] }
      }
      second = {
        assignment = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/shared" }
        intent     = { scope = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000000" } }
        resolved   = { members = [], member_reference_ids = [] }
      }
    }
  }

  expect_failures = [var.resolved_assignments]
}

run "accept_distinct_assignment_ids_on_a_shared_scope" {
  command = plan

  variables {
    resolved_assignments = {
      first = {
        assignment = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/first" }
        intent     = { scope = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000000" } }
        resolved   = { members = [], member_reference_ids = [] }
      }
      second = {
        assignment = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/second" }
        intent     = { scope = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000000" } }
        resolved   = { members = [], member_reference_ids = [] }
      }
    }
  }

  assert {
    condition     = length(output.created_operations) == 0 && length(output.created_exemption_ids) == 0
    error_message = "Distinct assignment IDs on one scope must be accepted and must create no operation without a request."
  }
}
