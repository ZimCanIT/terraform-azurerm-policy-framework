# State-handoff contract root. It proves that the three cross-state hand-offs
# survive a state boundary: content to the resolving states (definitions and
# initiatives), identity-rbac to assignments (assignment_bindings) and
# assignments to operations (resolved_assignments).
#
# Each hand-off is serialised with jsonencode and decoded with jsondecode, which
# drops every Terraform type: sets and lists become tuples, maps become objects.
# That is the least typed form a consumer can receive, as when a pipeline
# supplies a hand-off as JSON. A value read from remote state is expected to
# keep its stored output type, so this is the stricter case. The direct
# pipeline wires the same modules without any serialisation, and the tests
# compare the two.

terraform {
  required_version = ">= 1.12.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 5.0.0, < 6.0.0"
    }
  }
}

provider "azurerm" {
  features {}
}

locals {
  subscription_id      = "00000000-0000-0000-0000-000000000000"
  subscription_scope   = "/subscriptions/${local.subscription_id}"
  resource_group_name  = "rg-zctfp-contract"
  resource_group_scope = "${local.subscription_scope}/resourceGroups/${local.resource_group_name}"
  evaluation_time      = "2026-12-31T23:59:59Z"

  # Tag Contributor, in the subscription-prefixed form Azure returns on read.
  tag_contributor_role_id = "${local.subscription_scope}/providers/Microsoft.Authorization/roleDefinitions/4a9ae827-6dc8-4573-8ac7-8239d42aa03f"
}

locals {
  native_definitions = {
    # Custom Modify definition. It drives the identity, role-grant and
    # remediation path, so its rule repeats the role definition ID the
    # assignment intent grants.
    "add-costcentre-tag" = {
      source_type  = "custom"
      name         = "add-costcentre-tag"
      display_name = "Add cost centre tag to storage accounts"
      description  = "Adds the configured cost centre tag to storage accounts."
      mode         = "Indexed"
      version      = "1.0.0"
      metadata     = { category = "Tags" }

      parameters = {
        tagName = {
          type         = "String"
          defaultValue = "costCentre"
          metadata     = { displayName = "Tag name", description = "Name of the tag to add." }
        }
        tagValue = {
          type         = "String"
          defaultValue = "example-cost-centre"
          metadata     = { displayName = "Tag value", description = "Value of the tag to add." }
        }
      }

      supported_effects   = ["Modify"]
      role_definition_ids = [local.tag_contributor_role_id]

      policy_rule = {
        if = {
          allOf = [
            { field = "type", equals = "Microsoft.Storage/storageAccounts" },
            { field = "[concat('tags[', parameters('tagName'), ']')]", exists = "false" }
          ]
        }
        then = {
          effect = "Modify"
          details = {
            roleDefinitionIds = [local.tag_contributor_role_id]
            operations = [{
              operation = "add"
              field     = "[concat('tags[', parameters('tagName'), ']')]"
              value     = "[parameters('tagValue')]"
            }]
          }
        }
      }
    }

    # Built-in definition for the plain subscription assignment. A built-in
    # carries no rule, so its default effect comes from the capability.
    "audit-direct" = {
      source_type          = "built_in"
      display_name         = "Direct audit"
      policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/00000000-0000-0000-0000-000000000001"
      pinned_version       = "1.0.0"
      supported_effects    = ["Audit", "Disabled"]
      capabilities         = { default_effect = "Audit" }
      role_definition_ids  = []
    }

    # Rich custom definition that no assignment targets. It carries numbers,
    # booleans, lists of objects and nested objects across the boundary.
    "rich-custom" = {
      source_type         = "custom"
      display_name        = "Rich custom definition"
      version             = "2.3.4"
      role_definition_ids = ["/providers/Microsoft.Authorization/roleDefinitions/11111111-1111-1111-1111-111111111111"]
      supported_effects   = ["Audit", "Deny"]
      supported_overrides = [{ kind = "policyEffect", value = "Disabled" }]
      selectors           = [{ kind = "resourceLocation", in = ["eastus"] }]
      non_compliance_messages = {
        default = "The synthetic control is not compliant."
      }
      capabilities = { supportsIdentity = true, supportsRemediation = false }
      governance = {
        requirement_id = "REQ-TAGS-001"
        owner          = "platform-team"
        rationale      = "Cost allocation for synthetic resources."
        review_date    = "2026-12-31"
      }
      parameters = {
        retryCount = { type = "Integer", defaultValue = 3 }
        enforce    = { type = "Boolean", defaultValue = true }
        locations  = { type = "Array", defaultValue = ["eastus", "westus"] }
      }
      policy_rule = {
        if   = { field = "type", equals = "Microsoft.Resources/subscriptions" }
        then = { effect = "audit" }
      }
    }

    # Capability states that must keep their meaning across the boundary: an
    # absent field is unknown and an empty list is verified absence.
    "unknown-effects" = {
      source_type  = "custom"
      display_name = "Unknown supported effects"
      version      = "1.0.0"
      policy_rule = {
        if   = { field = "type", equals = "Microsoft.Resources/subscriptions" }
        then = { effect = "audit" }
      }
    }

    "verified-empty-effects" = {
      source_type       = "custom"
      display_name      = "Verified empty supported effects"
      version           = "1.0.0"
      supported_effects = []
      policy_rule = {
        if   = { field = "type", equals = "Microsoft.Resources/subscriptions" }
        then = { effect = "audit" }
      }
    }

    "builtin-missing-capability" = {
      source_type          = "built_in"
      display_name         = "Built-in with no declared capability"
      policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
      version_constraint   = "1.*.*"
    }

    "builtin-verified-empty" = {
      source_type          = "built_in"
      display_name         = "Built-in with verified empty capability"
      policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
      parameters           = {}
      role_definition_ids  = []
      version_constraint   = "1.*.*"
    }
  }

  native_initiatives = {
    "tag-governance" = {
      display_name = "Tag governance"
      description  = "Composes the Modify definition for the contract fixture."
      version      = "1.0.0"
      metadata     = { category = "Tags" }
      governance   = { requirement_keys = ["req-tag-governance"] }

      parameters = {
        costCentreTagName = {
          type         = "String"
          defaultValue = "CostCentre"
          metadata     = { displayName = "Cost centre tag name", description = "Name of the tag the member adds." }
        }
        costCentreTagValue = {
          type         = "String"
          defaultValue = "zctfp-contract"
          metadata     = { displayName = "Cost centre tag value", description = "Value of the tag the member adds." }
        }
      }

      policy_definition_references = [{
        reference_id   = "add-costcentre-tag-member"
        definition_key = "add-costcentre-tag"
        parameter_values = {
          tagName  = { value = "[parameters('costCentreTagName')]" }
          tagValue = { value = "[parameters('costCentreTagValue')]" }
        }
      }]
    }
  }

  assignments = {
    # Plain subscription assignment: no identity, so identity-rbac emits no
    # binding for it and the assignments module creates it without one.
    "audit-subscription" = {
      target = {
        reference_id   = "audit-direct"
        definition_key = "audit-direct"
      }
      scope           = { type = "subscription", id = local.subscription_scope }
      effect          = "Audit"
      version_binding = "unversioned"
    }

    # Initiative-member assignment with a user-assigned identity, so the
    # binding and the role grant both cross the role-grant state boundary.
    "modify-tag-rg" = {
      target = {
        reference_id   = "add-costcentre-tag-member"
        initiative_key = "tag-governance"
      }
      scope = { type = "resource_group", id = local.resource_group_scope }
      parameters = {
        costCentreTagName  = "CostCentre"
        costCentreTagValue = "zctfp-contract"
      }
      enforcement_mode = "Default"
      identity = {
        strategy            = "user_assigned"
        location            = "westeurope"
        resource_group_name = local.resource_group_name
      }
      role_grant_scopes = {
        (local.tag_contributor_role_id) = local.resource_group_scope
      }
    }
  }

  # policy_assignment_id is omitted on purpose: operations derives it from the
  # lifecycle binding of the assignment the request names.
  requests = {
    "remediate-tag-rg" = {
      mode                           = "execute"
      assignment_key                 = "modify-tag-rg"
      scope_type                     = "resource_group"
      scope_id                       = local.resource_group_scope
      member_reference_id            = "add-costcentre-tag-member"
      policy_definition_reference_id = "add-costcentre-tag-member"
      resource_discovery_mode        = "ExistingNonCompliant"
      location_filters               = ["westeurope"]
      resource_count                 = 50
      parallel_deployments           = 1
      role_scope                     = local.resource_group_scope
      approval_reference             = "CAB-CONTRACT-REMEDIATE"
    }
  }

  # Each exemption names the assignment it exempts; the pipeline adds the
  # assignment_id from its own assignments output.
  exemption_assignment_keys = {
    "exempt-audit-subscription" = "audit-subscription"
    "exempt-tag-member"         = "modify-tag-rg"
  }

  exemption_requests = {
    "exempt-audit-subscription" = {
      request_mode         = "create"
      scope                = { type = "subscription", id = local.subscription_scope }
      owner                = "platform-governance"
      reason               = "Contract fixture exemption on a subscription assignment."
      approval_reference   = "CAB-CONTRACT-EXEMPT-SUB"
      ticket_reference     = "CHG-CONTRACT-0001"
      category             = "Mitigated"
      compensating_control = "Platform governance reviews the exemption weekly."
      expires_on           = "2027-01-31T00:00:00Z"
    }
    "exempt-tag-member" = {
      request_mode                    = "create"
      scope                           = { type = "resource_group", id = local.resource_group_scope }
      owner                           = "platform-governance"
      reason                          = "Contract fixture exemption on one initiative member."
      approval_reference              = "CAB-CONTRACT-EXEMPT-MEMBER"
      ticket_reference                = "CHG-CONTRACT-0002"
      category                        = "Waiver"
      compensating_control            = "Platform governance reviews the exemption weekly."
      expires_on                      = "2027-01-31T00:00:00Z"
      policy_definition_reference_ids = ["add-costcentre-tag-member"]
    }
  }
}

module "catalogue" {
  source = "../../../modules/catalogue"

  native_definitions = local.native_definitions
  native_initiatives = local.native_initiatives
}

# The content state. Its two outputs are the C1 hand-off.
module "content" {
  source = "../../../modules/content"

  definitions = module.catalogue.definitions
  initiatives = module.catalogue.initiatives
}

locals {
  c1 = jsondecode(jsonencode({
    definitions = module.content.definitions
    initiatives = module.content.initiatives
  }))
}

# Direct wiring: every hand-off passes the module output straight to the next
# module, as the composite root does in one state.
module "resolve_direct" {
  source = "../../../modules/behaviour-resolution"

  definitions = module.content.definitions
  initiatives = module.content.initiatives
  assignments = local.assignments
}

module "identity_direct" {
  source = "../../../modules/identity-rbac"

  assignments = module.resolve_direct.assignments
}

module "assign_direct" {
  source = "../../../modules/assignments"

  assignments       = module.resolve_direct.assignments
  identity_bindings = module.identity_direct.assignment_bindings
}

module "operations_direct" {
  source = "../../../modules/operations"

  resolved_assignments = module.assign_direct.resolved_assignments
  requests             = local.requests
  exemptions = {
    for key, request in local.exemption_requests : key => merge(request, {
      assignment_id = module.assign_direct.resolved_assignments[local.exemption_assignment_keys[key]].assignment.id
    })
  }
  evaluation_time = local.evaluation_time
}

# Separated wiring: each state resolves for itself from the C1 hand-off, and
# the C2 and C3 hand-offs cross a serialisation boundary.
module "resolve_roles_state" {
  source = "../../../modules/behaviour-resolution"

  definitions = local.c1.definitions
  initiatives = local.c1.initiatives
  assignments = local.assignments
}

module "identity_state" {
  source = "../../../modules/identity-rbac"

  assignments = module.resolve_roles_state.assignments
}

locals {
  c2 = jsondecode(jsonencode(module.identity_state.assignment_bindings))
}

# A second resolver instance with identical inputs, as the assignments state
# runs it. Equality with the role-grant state's instance is the recomputation
# contract.
module "resolve_assignments_state" {
  source = "../../../modules/behaviour-resolution"

  definitions = local.c1.definitions
  initiatives = local.c1.initiatives
  assignments = local.assignments
}

module "assign_state" {
  source = "../../../modules/assignments"

  assignments       = module.resolve_assignments_state.assignments
  identity_bindings = local.c2
}

locals {
  c3 = jsondecode(jsonencode(module.assign_state.resolved_assignments))
}

module "operations_state" {
  source = "../../../modules/operations"

  resolved_assignments = local.c3
  requests             = local.requests
  exemptions = {
    for key, request in local.exemption_requests : key => merge(request, {
      assignment_id = local.c3[local.exemption_assignment_keys[key]].assignment.id
    })
  }
  evaluation_time = local.evaluation_time
}

output "handoffs" {
  description = "The three hand-offs as the consuming states receive them."
  value = {
    c1 = local.c1
    c2 = local.c2
    c3 = local.c3
  }
}

output "content" {
  description = "The content module outputs before serialisation."
  value = {
    definitions = module.content.definitions
    initiatives = module.content.initiatives
  }
}

output "direct" {
  description = "Every output of each module in the directly wired pipeline."
  value = {
    resolution  = module.resolve_direct
    identity    = module.identity_direct
    assignments = module.assign_direct
    operations  = module.operations_direct
  }
}

output "states" {
  description = "Every output of each module in the separated pipeline, plus the second resolver instance."
  value = {
    resolution                = module.resolve_roles_state
    resolution_for_assignment = module.resolve_assignments_state
    identity                  = module.identity_state
    assignments               = module.assign_state
    operations                = module.operations_state
  }
}
