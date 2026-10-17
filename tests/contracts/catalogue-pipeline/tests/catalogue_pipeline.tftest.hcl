mock_provider "azurerm" {
  override_during = plan

  mock_resource "azurerm_policy_definition" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyDefinitions/mock"
    }
  }

  mock_resource "azurerm_policy_set_definition" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policySetDefinitions/mock"
    }
  }

  mock_resource "azurerm_management_group_policy_set_definition" {
    defaults = {
      id = "/providers/Microsoft.Management/managementGroups/example/providers/Microsoft.Authorization/policySetDefinitions/mock"
    }
  }
}

run "catalogue_to_definitions_preserves_contract" {
  command = plan

  assert {
    condition     = output.definitions["allowed_locations"].id == "/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c"
    error_message = "Built-in policy IDs must pass through catalogue and definitions unchanged."
  }

  assert {
    condition     = output.definitions["allowed_locations"].version_constraint == "1.*.*" && output.definitions["allowed_locations"].pinned_version == null
    error_message = "Built-in version intent must remain a version constraint."
  }

  assert {
    condition     = output.definitions["require_cost_centre_tag"].source_type == "custom" && output.definitions["require_cost_centre_tag"].version == "1.0.0" && output.definitions["require_cost_centre_tag"].metadata.version == "1.0.0"
    error_message = "Custom version intent must be normalized and preserved."
  }

  assert {
    condition     = output.definitions["require_cost_centre_tag"].parameters.tagName.defaultValue == "costCentre"
    error_message = "Companion parameter values must reach definitions with their original types and structure."
  }

  assert {
    condition     = output.definitions["native_structured"].parameters.retryCount.defaultValue == 3 && output.definitions["native_structured"].parameters.enforce.defaultValue == true && output.definitions["native_structured"].parameters.locations.defaultValue == ["eastus", "westus"]
    error_message = "Integer, boolean, and array parameter values must remain structured values."
  }

  assert {
    condition = jsonencode(output.definitions["native_structured"].role_definition_ids) == jsonencode([
      "/providers/Microsoft.Authorization/roleDefinitions/11111111-1111-1111-1111-111111111111",
      "/providers/Microsoft.Authorization/roleDefinitions/22222222-2222-2222-2222-222222222222",
    ])
    error_message = "Candidate and policy-rule role definition IDs must be preserved."
  }

  assert {
    condition = (
      output.definitions["native_structured"].supported_overrides == [{ kind = "policyEffect", value = "Disabled" }] &&
      output.definitions["native_structured"].selectors == [{ kind = "resourceLocation", in = ["eastus"] }] &&
      output.definitions["native_structured"].non_compliance_messages.default == "The synthetic control is not compliant."
    )
    error_message = "Catalogue capability declarations must pass through definitions unchanged."
  }

  assert {
    condition = (
      output.definitions["native_structured"].capabilities.supportsIdentity == true &&
      output.definitions["native_structured"].capabilities.supportsRemediation == false &&
      output.definitions["native_structured"].governance.requirement_id == "REQ-TAGS-001" &&
      output.definitions["native_structured"].governance.owner == "platform-team" &&
      output.definitions["native_structured"].governance.review_date == "2026-12-31"
    )
    error_message = "Catalogue capability and governance declarations must reach the definitions output verbatim."
  }

  assert {
    condition = (
      output.definitions["require_cost_centre_tag"].capabilities == null &&
      output.definitions["require_cost_centre_tag"].governance == null &&
      output.definitions["require_cost_centre_tag"].supported_overrides == null &&
      output.definitions["require_cost_centre_tag"].selectors == null &&
      output.definitions["require_cost_centre_tag"].non_compliance_messages == null &&
      output.definitions["allowed_locations"].capabilities == null &&
      output.definitions["allowed_locations"].governance == null
    )
    error_message = "Undeclared capability and governance data must remain null rather than defaulting to empty collections."
  }

  assert {
    condition = (
      output.definitions["native_unknown_effects"].supported_effects == null
    )
    error_message = "Absent supported_effects must pass through definitions as null (unknown), not an empty list."
  }

  assert {
    condition = (
      output.definitions["native_verified_empty_effects"].supported_effects != null &&
      length(output.definitions["native_verified_empty_effects"].supported_effects) == 0
    )
    error_message = "An explicitly empty supported_effects collection must remain a verified absence, not null."
  }

  assert {
    condition = (
      output.definitions["allowed_locations"].mode == "Indexed" &&
      output.definitions["allowed_locations"].parameters == null &&
      output.definitions["allowed_locations"].role_definition_ids == null
    )
    error_message = "A built-in reference must keep its supplied mode while undeclared parameters and role IDs stay null (unknown)."
  }

  assert {
    condition     = output.initiatives["security_baseline"].policy_definition_references[0].definition_key == "allowed_locations" && output.initiatives["security_baseline"].policy_definition_references[1].policy_definition_id == "/providers/Microsoft.Authorization/policyDefinitions/cccccccc-cccc-cccc-cccc-cccccccccccc" && output.initiatives["security_baseline"].policy_definition_references[1].pinned_version == "2.0.0"
    error_message = "Initiative references must preserve keyed and direct IDs with explicit version intent."
  }
}

run "catalogue_to_definitions_preserves_built_in_capability_unknown_state" {
  command = plan

  assert {
    condition = (
      output.definitions["native_builtin_missing_capability"].mode == null &&
      output.definitions["native_builtin_missing_capability"].parameters == null &&
      output.definitions["native_builtin_missing_capability"].role_definition_ids == null
    )
    error_message = "Built-in mode, parameters and role IDs that the catalogue cannot supply must remain null (unknown) after definitions."
  }

  assert {
    condition = (
      output.definitions["native_builtin_verified_empty_capability"].parameters != null &&
      length(keys(output.definitions["native_builtin_verified_empty_capability"].parameters)) == 0 &&
      output.definitions["native_builtin_verified_empty_capability"].role_definition_ids != null &&
      length(output.definitions["native_builtin_verified_empty_capability"].role_definition_ids) == 0
    )
    error_message = "Explicitly empty built-in parameters and role IDs must remain verified absence, not null."
  }

  assert {
    condition = (
      output.definitions["native_builtin_supplied_capability"].mode == "Indexed" &&
      output.definitions["native_builtin_supplied_capability"].parameters.listOfAllowedLocations.type == "Array" &&
      join(",", output.definitions["native_builtin_supplied_capability"].role_definition_ids) == "/providers/Microsoft.Authorization/roleDefinitions/44444444-4444-4444-4444-444444444444"
    )
    error_message = "Supplied built-in mode, parameters and role IDs must pass through catalogue and definitions unchanged."
  }

  assert {
    condition = (
      output.definitions["native_structured"].mode == "All" &&
      output.definitions["require_cost_centre_tag"].mode == "Indexed" &&
      length(keys(output.definitions["native_unknown_effects"].parameters)) == 0 &&
      length(output.definitions["native_unknown_effects"].role_definition_ids) == 0
    )
    error_message = "Custom entries must retain the All, {} and [] resource defaults or supplied values while built-ins keep the unknown state."
  }
}

run "catalogue_to_definitions_preserves_strict_scalar_types" {
  command = plan

  assert {
    condition = alltrue([
      for _, definition in output.definitions :
      can(regex("^\\\".*\\\"$", jsonencode(definition.display_name))) &&
      (try(definition.name, null) == null || can(regex("^\\\".*\\\"$", jsonencode(definition.name)))) &&
      (try(definition.description, null) == null || can(regex("^\\\".*\\\"$", jsonencode(definition.description)))) &&
      (try(definition.mode, null) == null || can(regex("^\\\".*\\\"$", jsonencode(definition.mode)))) &&
      (try(definition.policy_definition_id, null) == null || can(regex("^\\\".*\\\"$", jsonencode(definition.policy_definition_id)))) &&
      (try(definition.management_group_id, null) == null || can(regex("^\\\".*\\\"$", jsonencode(definition.management_group_id)))) &&
      (try(definition.version, null) == null || can(regex("^\\\".*\\\"$", jsonencode(definition.version)))) &&
      (try(definition.version_constraint, null) == null || can(regex("^\\\".*\\\"$", jsonencode(definition.version_constraint)))) &&
      (try(definition.pinned_version, null) == null || can(regex("^\\\".*\\\"$", jsonencode(definition.pinned_version)))) &&
      (try(definition.metadata.version, null) == null || can(regex("^\\\".*\\\"$", jsonencode(definition.metadata.version))))
    ])
    error_message = "Every catalogue-emitted string field must be a strict string so modules/content does not reject the hand-off."
  }

  assert {
    condition = (
      output.definitions["native_strict_scalars"].name == "native-strict-scalars" &&
      output.definitions["native_strict_scalars"].description == "Synthetic strict scalar projection entry." &&
      output.definitions["native_strict_scalars"].mode == "All" &&
      output.definitions["native_strict_scalars"].management_group_id == "/providers/Microsoft.Management/managementGroups/example-platform" &&
      output.definitions["native_strict_scalars"].metadata.version == "1.0.0"
    )
    error_message = "Documented optional string scalars must pass through catalogue and definitions without coercion or loss."
  }
}

run "catalogue_to_initiatives_preserves_contract" {
  command = plan

  assert {
    condition     = output.pipeline_initiatives["security_baseline"].name == "security_baseline"
    error_message = "Initiatives must default their Azure name to the stable catalogue key."
  }

  assert {
    condition     = output.pipeline_initiatives["security_baseline"].policy_definition_references[0].policy_definition_id == output.pipeline_definitions["allowed_locations"].id
    error_message = "Keyed initiative members must resolve to the matching canonical definition ID."
  }

  assert {
    condition     = output.pipeline_initiatives["security_baseline"].policy_definition_references[1].policy_definition_id == "/providers/Microsoft.Authorization/policyDefinitions/cccccccc-cccc-cccc-cccc-cccccccccccc"
    error_message = "Direct initiative member IDs must pass through unchanged."
  }

  assert {
    condition     = output.pipeline_initiatives["security_baseline"].policy_definition_groups[0].name == "location_governance"
    error_message = "Initiative groups must preserve the declared group names."
  }

  assert {
    condition = (
      output.pipeline_initiatives["security_baseline"].version == "1.0.0" &&
      output.pipeline_initiatives["security_baseline"].parameter_schema["allowedLocations"].type == "Array" &&
      output.pipeline_initiatives["security_baseline"].policy_definition_references[0].source_type == "built_in" &&
      output.pipeline_initiatives["security_baseline"].policy_definition_references[0].created_by_module == false &&
      output.pipeline_initiatives["security_baseline"].policy_definition_references[0].inherited_version == "1.0.*" &&
      output.pipeline_initiatives["security_baseline"].policy_definition_references[0].selected_version == "1.0.*" &&
      output.pipeline_initiatives["security_baseline"].policy_definition_references[0].parameter_schema == null
    )
    error_message = "The initiative producer must keep set parameters, initiative content version, member source provenance and built-in deployment version intent in separate fields."
  }

  assert {
    condition = (
      output.pipeline_initiatives["security_baseline"].policy_definition_references[0].parameter_mappings["listOfAllowedLocations"].value == "[parameters('allowedLocations')]" &&
      output.pipeline_initiatives["security_baseline"].policy_definition_references[0].role_definition_ids == null
    )
    error_message = "A member's parameter mapping must remain member-scoped, and absent role capability must stay unknown rather than becoming an empty list."
  }

  assert {
    condition = (
      [for member in output.resolved_assignments["reviewed_baseline"].resolved.members : member.reference_id] == ["allowed_locations", "allowed_vm_skus"] &&
      [for member in output.resolved_assignments["reviewed_baseline"].resolved.members : member.effective_effect] == ["Audit", "Disabled"] &&
      output.resolved_assignments["reviewed_baseline"].resolved.initiative_content_version == "1.0.0" &&
      output.resolved_assignments["reviewed_baseline"].resolved.parameter_schema["allowedLocations"].type == "Array"
    )
    error_message = "Catalogue, definitions and initiatives outputs must feed the resolver without losing member order, member effects, set schema or initiative provenance."
  }

  assert {
    condition = (
      output.resolved_assignments["reviewed_baseline"].resolved.members[0].source_type == "built_in" &&
      output.resolved_assignments["reviewed_baseline"].resolved.members[0].created_by_module == false &&
      output.resolved_assignments["reviewed_baseline"].resolved.members[0].parameter_mappings["listOfAllowedLocations"].value == "[parameters('allowedLocations')]" &&
      output.resolved_assignments["reviewed_baseline"].resolved.members[1].selected_version == "2.0.*"
    )
    error_message = "The resolver must preserve actual initiative member provenance, member-only parameter mappings and supported provider-version intent from the initiative producer."
  }
}
