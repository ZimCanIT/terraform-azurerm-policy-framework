mock_provider "azurerm" {
  override_during = plan

  mock_resource "azurerm_subscription_policy_assignment" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/mock" }
  }

  mock_resource "azurerm_policy_set_definition" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policySetDefinitions/mock" }
  }

  mock_resource "azurerm_resource_group_policy_assignment" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/contract/providers/Microsoft.Authorization/policyAssignments/typed-set" }
  }

  mock_resource "azurerm_resource_policy_assignment" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/contract/providers/Microsoft.Storage/storageAccounts/typed/providers/Microsoft.Authorization/policyAssignments/typed-direct" }
  }
}

mock_provider "azurerm" {
  alias = "consumer"
}

run "root_composition_preserves_intent_and_resolved_handoffs" {
  command = plan

  assert {
    condition     = output.consumer_composition.counted_instances == 1 && tolist(output.consumer_composition.keyed_instances) == tolist(["estate"])
    error_message = "The composite must support caller provider aliases, count, for_each and depends_on without a nested provider configuration."
  }

  assert {
    condition     = output.root_contract.resolved_assignments["direct_audit"].intent.target.definition_key == "direct_audit"
    error_message = "The thin root must preserve direct policy target intent into the resolved assignment contract."
  }

  assert {
    condition     = output.root_contract.resolved_assignments["direct_audit"].resolved.effective_effect == "Audit"
    error_message = "The resolver must emit the effective effect consumed by downstream modules."
  }

  assert {
    condition     = output.root_contract.plan_summary.assignment_count == 3 && output.root_contract.plan_summary.management_group_inheritance == false && tolist(output.root_contract.plan_summary.rollout_stages) == tolist(["unspecified"])
    error_message = "The thin root must derive the plan summary from the resolved assignment hand-off."
  }

  assert {
    condition     = trimspace(output.root_contract.replacement_review.assignments["direct_audit"].name_basis) != "" && length(output.root_contract.remediations) == 0 && length(output.root_contract.exemptions.requested) == 0
    error_message = "The thin root must expose deterministic replacement attributes and empty operation views when no requests are supplied."
  }

  assert {
    condition     = output.root_contract.governance.traceability["internal_requirement"].traceability_status == "internal" && output.root_contract.governance.traceability["internal_requirement"].traceable == true
    error_message = "The thin root must trace an internal requirement to the root's derived control and assignment inventories."
  }

  assert {
    condition     = output.root_contract.governance.traceability["external_requirement"].traceability_status == "external" && output.root_contract.governance.traceability["external_requirement"].traceable == false && output.root_contract.governance.traceability["external_requirement"].traceability_complete == true
    error_message = "Explicitly declared external requirement references must be complete without being reported as internally traceable."
  }

  assert {
    condition     = contains(keys(output.root_contract.lifecycle_resource_ids.assignments), "direct_audit") && contains(keys(output.root_contract.lifecycle_resource_ids.identities), "direct_audit")
    error_message = "The root lifecycle projection must expose stable assignment and identity keys for live cleanup and review."
  }
}

run "preserves_seven_typed_parameters_through_root_composition" {
  command = plan

  assert {
    condition = (
      jsonencode(output.typed_producer_contract.definitions["typed_policy"].parameters) == jsonencode(output.typed_parameter_fixture.definition_schema) &&
      jsonencode(output.typed_producer_contract.initiatives["typed_set"].parameter_schema) == jsonencode(output.typed_parameter_fixture.initiative_schema) &&
      jsonencode(output.typed_producer_contract.initiatives["typed_set"].policy_definition_references[0].parameter_values) == jsonencode(output.typed_parameter_fixture.member_bindings)
    )
    error_message = "Definitions and initiatives must preserve all seven parameter schemas, defaults, heterogeneous literal values and typed member bindings."
  }

  assert {
    condition = (
      jsonencode(output.root_contract.resolved_assignments["typed_direct"].intent.parameters) == jsonencode(output.typed_parameter_fixture.definition_values) &&
      jsonencode(output.root_contract.resolved_assignments["typed_direct"].resolved.parameter_schema) == jsonencode(output.typed_parameter_fixture.definition_schema) &&
      jsonencode(output.root_contract.resolved_assignments["typed_direct"].resolved.parameter_values) == jsonencode(output.typed_parameter_fixture.definition_values)
    )
    error_message = "A direct assignment must preserve typed intent values and its definition schema through resolution."
  }

  assert {
    condition = (
      jsonencode(output.root_contract.resolved_assignments["typed_set"].intent.parameters) == jsonencode(output.typed_parameter_fixture.initiative_values) &&
      jsonencode(output.root_contract.resolved_assignments["typed_set"].resolved.parameter_schema) == jsonencode(output.typed_parameter_fixture.initiative_schema) &&
      jsonencode(output.root_contract.resolved_assignments["typed_set"].resolved.parameter_mappings) == jsonencode(output.typed_parameter_fixture.member_bindings) &&
      jsonencode(output.root_contract.resolved_assignments["typed_set"].resolved.parameter_values) == jsonencode(merge(output.typed_parameter_fixture.member_bindings, output.typed_parameter_fixture.initiative_values))
    )
    error_message = "An initiative assignment must preserve typed set intent, set schema and each typed member binding through resolution."
  }

  assert {
    condition = (
      jsonencode(output.root_contract.resolved_assignments["typed_set"].resolved.members[0].parameter_schema) == jsonencode(output.typed_parameter_fixture.definition_schema) &&
      jsonencode(output.root_contract.resolved_assignments["typed_set"].resolved.members[0].parameter_values) == jsonencode(output.typed_parameter_fixture.member_bindings)
    )
    error_message = "The resolved initiative member must retain the referenced definition schema and the typed mapping expressions."
  }
}
