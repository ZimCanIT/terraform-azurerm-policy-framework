# Moved from the former tests/contracts/remediations root: one fixture covering
# every typed scope, then the desired-state transitions that must remove a
# previously managed execution from the plan without destroying its record.

mock_provider "azurerm" {}

variables {
  resolved_assignments = {
    assignment_discovery = {
      intent = { scope = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000000" } }
      resolved = {
        policy_definition_id    = "/providers/Microsoft.Authorization/policyDefinitions/example"
        member_reference_id     = null
        member_reference_ids    = []
        members                 = []
        effective_effect        = "DeployIfNotExists"
        remediation_eligibility = "eligible"
        required_roles          = [{ grant_scope = "/subscriptions/00000000-0000-0000-0000-000000000000" }]
      }
      assignment = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/example" }
    }
    assignment_blocked = {
      intent = { scope = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000000" } }
      resolved = {
        policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/example"
        member_reference_id  = "policyRefBlocked"
        member_reference_ids = ["policyRefBlocked"]
        members = [{
          reference_id            = "policyRefBlocked"
          policy_definition_id    = "/providers/Microsoft.Authorization/policyDefinitions/example"
          remediation_eligibility = "blocked"
          remediation_reason      = "The effective effect requires an identity but no role definitions were supplied."
          required_roles          = []
        }]
        remediation_eligibility = "blocked"
        remediation_reason      = "The effective effect requires an identity but no role definitions were supplied."
        required_roles          = []
      }
      assignment = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/blocked" }
    }
    assignment_disabled = {
      intent = { scope = { type = "resource_group", id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example" } }
      resolved = {
        policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/example"
        member_reference_id  = "policyRef1"
        member_reference_ids = ["policyRef1"]
        members = [{
          reference_id            = "policyRef1"
          policy_definition_id    = "/providers/Microsoft.Authorization/policyDefinitions/example"
          remediation_eligibility = "eligible"
          remediation_reason      = "The selected member has an eligible remediation effect."
          required_roles          = [{ grant_scope = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example" }]
        }]
        remediation_eligibility = "eligible"
        required_roles          = [{ grant_scope = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example" }]
      }
      assignment = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example/providers/Microsoft.Authorization/policyAssignments/example" }
    }
    assignment_management_group = {
      intent = { scope = { type = "management_group", id = "/providers/Microsoft.Management/managementGroups/example-platform" } }
      resolved = {
        policy_definition_id    = "/providers/Microsoft.Authorization/policyDefinitions/example"
        effective_effect        = "DeployIfNotExists"
        member_reference_ids    = []
        members                 = []
        remediation_eligibility = "eligible"
        required_roles          = [{ grant_scope = "/providers/Microsoft.Management/managementGroups/example-platform" }]
      }
      assignment = { id = "/providers/Microsoft.Management/managementGroups/example-platform/providers/Microsoft.Authorization/policyAssignments/mg-example" }
    }
    assignment_subscription = {
      intent = { scope = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000000" } }
      resolved = {
        policy_definition_id    = "/providers/Microsoft.Authorization/policyDefinitions/example"
        effective_effect        = "DeployIfNotExists"
        member_reference_ids    = []
        members                 = []
        remediation_eligibility = "eligible"
        required_roles          = [{ grant_scope = "/subscriptions/00000000-0000-0000-0000-000000000000" }]
      }
      assignment = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/sub-example" }
    }
    assignment_resource = {
      intent = { scope = { type = "resource", id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example/providers/Microsoft.Storage/storageAccounts/one" } }
      resolved = {
        policy_definition_id    = "/providers/Microsoft.Authorization/policyDefinitions/example"
        effective_effect        = "DeployIfNotExists"
        member_reference_ids    = []
        members                 = []
        remediation_eligibility = "eligible"
        required_roles          = [{ grant_scope = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example" }]
      }
      assignment = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example/providers/Microsoft.Storage/storageAccounts/one/providers/Microsoft.Authorization/policyAssignments/resource-example" }
    }
    assignment_resource_group_execute = {
      intent = { scope = { type = "resource_group", id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example" } }
      resolved = {
        policy_definition_id    = "/providers/Microsoft.Authorization/policyDefinitions/example"
        effective_effect        = "DeployIfNotExists"
        member_reference_ids    = []
        members                 = []
        remediation_eligibility = "eligible"
        required_roles          = [{ grant_scope = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example" }]
      }
      assignment = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example/providers/Microsoft.Authorization/policyAssignments/rg-execute" }
    }
  }

  discovery_evidence = {
    execute_resource = {
      targets = [{ resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example/providers/Microsoft.Storage/storageAccounts/one", location = "westeurope" }]
    }
    discovery_request = {
      targets = [
        { resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example/providers/Microsoft.Storage/storageAccounts/one", location = "westeurope" },
        { resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example/providers/Microsoft.Storage/storageAccounts/two", location = "northeurope" },
      ]
    }
  }

  requests = {
    discovery_request = {
      mode                 = "discovery"
      assignment_key       = "assignment_discovery"
      scope_type           = "subscription"
      scope_id             = "/subscriptions/00000000-0000-0000-0000-000000000000"
      policy_assignment_id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/example"
      role_scope           = "/subscriptions/00000000-0000-0000-0000-000000000000"
      resource_count       = 25
      location_filters     = ["westeurope"]
      approval_reference   = "CAB-10001"
      evidence_status      = "pending"
    }
    disabled_request = {
      mode                 = "disabled"
      assignment_key       = "assignment_disabled"
      scope_type           = "resource_group"
      scope_id             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example"
      policy_assignment_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example/providers/Microsoft.Authorization/policyAssignments/example"
    }
    blocked_request = {
      mode                           = "disabled"
      assignment_key                 = "assignment_blocked"
      scope_type                     = "subscription"
      scope_id                       = "/subscriptions/00000000-0000-0000-0000-000000000000"
      policy_assignment_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/blocked"
      member_reference_id            = "policyRefBlocked"
      policy_definition_reference_id = "policyRefBlocked"
      role_scope                     = "/subscriptions/00000000-0000-0000-0000-000000000000"
      approval_reference             = "CAB-BLOCKED"
      resource_count                 = 1
    }
    execute_request = {
      mode                           = "execute"
      assignment_key                 = "assignment_disabled"
      scope_type                     = "resource_group"
      scope_id                       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example"
      policy_assignment_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example/providers/Microsoft.Authorization/policyAssignments/example"
      member_reference_id            = "policyRef1"
      role_scope                     = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example"
      approval_reference             = "CAB-10002"
      evidence_status                = "approved"
      resource_discovery_mode        = "ExistingNonCompliant"
      location_filters               = ["westeurope", "northeurope"]
      resource_count                 = 10
      parallel_deployments           = 2
      failure_percentage             = 0.25
      policy_definition_reference_id = "policyRef1"
    }
    execute_management_group = {
      mode                 = "execute"
      assignment_key       = "assignment_management_group"
      scope_type           = "management_group"
      scope_id             = "/providers/Microsoft.Management/managementGroups/example-platform"
      policy_assignment_id = "/providers/Microsoft.Management/managementGroups/example-platform/providers/Microsoft.Authorization/policyAssignments/mg-example"
      role_scope           = "/providers/Microsoft.Management/managementGroups/example-platform"
      approval_reference   = "CAB-MG-10003"
      resource_count       = 10
    }
    execute_subscription = {
      mode                    = "execute"
      assignment_key          = "assignment_subscription"
      scope_type              = "subscription"
      scope_id                = "/subscriptions/00000000-0000-0000-0000-000000000000"
      policy_assignment_id    = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/sub-example"
      role_scope              = "/subscriptions/00000000-0000-0000-0000-000000000000"
      approval_reference      = "CAB-SUB-10004"
      resource_count          = 10
      resource_discovery_mode = "ExistingNonCompliant"
    }
    execute_resource_group = {
      mode                    = "execute"
      assignment_key          = "assignment_resource_group_execute"
      scope_type              = "resource_group"
      scope_id                = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example"
      policy_assignment_id    = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example/providers/Microsoft.Authorization/policyAssignments/rg-execute"
      role_scope              = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example"
      approval_reference      = "CAB-RG-10005"
      resource_count          = 10
      resource_discovery_mode = "ExistingNonCompliant"
    }
    execute_resource = {
      mode                    = "execute"
      assignment_key          = "assignment_resource"
      scope_type              = "resource"
      scope_id                = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example/providers/Microsoft.Storage/storageAccounts/one"
      policy_assignment_id    = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example/providers/Microsoft.Storage/storageAccounts/one/providers/Microsoft.Authorization/policyAssignments/resource-example"
      role_scope              = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example"
      approval_reference      = "CAB-RES-10006"
      resource_count          = 10
      resource_discovery_mode = "ExistingNonCompliant"
    }
  }
}

run "explicit_requests_partition_across_all_scopes" {
  command = plan

  assert {
    condition     = output.requested_operations["discovery_request"].status == "discovery" && output.requested_operations["disabled_request"].status == "skipped" && output.requested_operations["blocked_request"].status == "skipped" && output.requested_operations["execute_request"].status == "created" && output.requested_operations["execute_management_group"].status == "created" && output.requested_operations["execute_subscription"].status == "created" && output.requested_operations["execute_resource_group"].status == "created" && output.requested_operations["execute_resource"].status == "created"
    error_message = "Remediation requests must classify discovery, disabled and execute requests distinctly."
  }

  assert {
    condition     = output.discovered_operations["discovery_request"].location_filters == ["westeurope"] && output.discovered_operations["discovery_request"].resource_count == 25 && output.discovered_operations["discovery_request"].evidence_status == "pending" && output.discovered_operations["discovery_request"].discovered_count == 1 && output.discovered_operations["discovery_request"].discovered_targets[0].location == "westeurope"
    error_message = "Discovery requests must preserve filters, limits and the caller-supplied evidence status, and apply location filters before reporting caller-supplied evidence."
  }

  assert {
    condition     = length(output.created_operations) == 5 && length(output.skipped_operations) == 2 && length(output.discovered_operations) == 1 && length(output.blocked_operations) == 0
    error_message = "Created, skipped, discovery and blocked operation cardinality must match the explicit request set."
  }

  assert {
    condition     = output.created_operations["execute_request"].approval_reference == "CAB-10002" && output.created_operations["execute_request"].role_scope == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example" && output.created_operations["execute_request"].evidence_status == "approved" && output.created_operations["execute_request"].resource_discovery_mode == "ExistingNonCompliant" && output.created_operations["execute_request"].remediation_eligibility == "eligible" && output.created_operations["execute_request"].member_reference_ids == ["policyRef1"] && output.created_operations["execute_request"].member_policy_definition_id == "/providers/Microsoft.Authorization/policyDefinitions/example"
    error_message = "Execute requests must preserve approval, evidence, discovery and role-scope intent, and the selected member's eligibility, inventory and definition identity."
  }

  assert {
    condition = (
      output.created_operations["execute_management_group"].scope_type == "management_group" &&
      output.created_operations["execute_management_group"].resource_discovery_mode == null &&
      output.created_operations["execute_subscription"].scope_type == "subscription" &&
      output.created_operations["execute_subscription"].resource_discovery_mode == "ExistingNonCompliant" &&
      output.created_operations["execute_resource_group"].scope_type == "resource_group" &&
      output.created_operations["execute_resource"].scope_type == "resource" &&
      output.created_operations["execute_resource"].policy_assignment_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example/providers/Microsoft.Storage/storageAccounts/one/providers/Microsoft.Authorization/policyAssignments/resource-example"
    )
    error_message = "Each typed scope must keep its scope and assignment ID, and only management groups may omit the discovery mode they do not support."
  }
}

run "create_managed_execute_state" {
  command   = apply
  state_key = "remediation-lifecycle"

  assert {
    condition     = length(output.created_operations) == 5
    error_message = "The isolated test state must contain all four scope resource variants and the selected-member execution."
  }
}

run "discovery_disabled_and_removal_transitions_drop_execute_actions" {
  command   = apply
  state_key = "remediation-lifecycle"

  variables {
    requests = {
      discovery_request = {
        mode                 = "discovery"
        assignment_key       = "assignment_discovery"
        scope_type           = "subscription"
        scope_id             = "/subscriptions/00000000-0000-0000-0000-000000000000"
        policy_assignment_id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/example"
        role_scope           = "/subscriptions/00000000-0000-0000-0000-000000000000"
        resource_count       = 25
        location_filters     = ["westeurope"]
        approval_reference   = "CAB-10001"
        evidence_status      = "pending"
      }
      disabled_request = {
        mode                 = "disabled"
        assignment_key       = "assignment_disabled"
        scope_type           = "resource_group"
        scope_id             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example"
        policy_assignment_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example/providers/Microsoft.Authorization/policyAssignments/example"
      }
      blocked_request = {
        mode                           = "disabled"
        assignment_key                 = "assignment_blocked"
        scope_type                     = "subscription"
        scope_id                       = "/subscriptions/00000000-0000-0000-0000-000000000000"
        policy_assignment_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/blocked"
        member_reference_id            = "policyRefBlocked"
        policy_definition_reference_id = "policyRefBlocked"
        role_scope                     = "/subscriptions/00000000-0000-0000-0000-000000000000"
        approval_reference             = "CAB-BLOCKED"
        resource_count                 = 1
      }
      # Managed execution changed to disabled.
      execute_request = {
        mode                           = "disabled"
        assignment_key                 = "assignment_disabled"
        scope_type                     = "resource_group"
        scope_id                       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example"
        policy_assignment_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example/providers/Microsoft.Authorization/policyAssignments/example"
        member_reference_id            = "policyRef1"
        role_scope                     = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example"
        approval_reference             = "CAB-10002"
        evidence_status                = "approved"
        resource_discovery_mode        = "ExistingNonCompliant"
        location_filters               = ["westeurope", "northeurope"]
        resource_count                 = 10
        parallel_deployments           = 2
        failure_percentage             = 0.25
        policy_definition_reference_id = "policyRef1"
      }
      execute_management_group = {
        mode                 = "execute"
        assignment_key       = "assignment_management_group"
        scope_type           = "management_group"
        scope_id             = "/providers/Microsoft.Management/managementGroups/example-platform"
        policy_assignment_id = "/providers/Microsoft.Management/managementGroups/example-platform/providers/Microsoft.Authorization/policyAssignments/mg-example"
        role_scope           = "/providers/Microsoft.Management/managementGroups/example-platform"
        approval_reference   = "CAB-MG-10003"
        resource_count       = 10
      }
      # execute_subscription is removed from the declared request set.
      execute_resource_group = {
        mode                    = "execute"
        assignment_key          = "assignment_resource_group_execute"
        scope_type              = "resource_group"
        scope_id                = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example"
        policy_assignment_id    = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example/providers/Microsoft.Authorization/policyAssignments/rg-execute"
        role_scope              = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example"
        approval_reference      = "CAB-RG-10005"
        resource_count          = 10
        resource_discovery_mode = "ExistingNonCompliant"
      }
      # Managed execution changed to explicit discovery.
      execute_resource = {
        mode                    = "discovery"
        assignment_key          = "assignment_resource"
        scope_type              = "resource"
        scope_id                = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example/providers/Microsoft.Storage/storageAccounts/one"
        policy_assignment_id    = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example/providers/Microsoft.Storage/storageAccounts/one/providers/Microsoft.Authorization/policyAssignments/resource-example"
        role_scope              = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example"
        approval_reference      = "CAB-RES-10006"
        resource_count          = 10
        resource_discovery_mode = "ExistingNonCompliant"
      }
    }
  }

  assert {
    condition     = output.discovered_operations["execute_resource"].status == "discovery" && !contains(keys(output.created_operations), "execute_resource")
    error_message = "Changing a managed execute request to explicit discovery must remove it from the execute partition."
  }

  assert {
    condition     = output.skipped_operations["execute_request"].status == "skipped" && !contains(keys(output.created_operations), "execute_request")
    error_message = "Changing a managed execute request to disabled must remove it from the execute partition."
  }

  assert {
    condition     = !contains(keys(output.requested_operations), "execute_subscription") && !contains(keys(output.created_operations), "execute_subscription") && length(output.created_operations) == 2
    error_message = "Removing a request from the declared request set must remove its managed execution from the isolated test state, leaving only the unchanged executions."
  }
}
