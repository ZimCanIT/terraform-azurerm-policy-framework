# Validation guard only: no input, so it never plans a change when the
# assignment set changes.
resource "terraform_data" "contract_guard" {
  lifecycle {
    precondition {
      condition = alltrue([
        for key, rules in local.target_rules : rules.exactly_one_target
      ])
      error_message = "Each assignment must declare exactly one target mechanism. Offending assignments: ${join(", ", [for key, rules in local.target_rules : key if !rules.exactly_one_target])}."
    }

    precondition {
      condition = alltrue([
        for key, rules in local.target_rules : rules.definition_exists
      ])
      error_message = "Each assignment definition_key must resolve to a known canonical definition. Offending assignments: ${join(", ", [for key, rules in local.target_rules : key if !rules.definition_exists])}."
    }

    precondition {
      condition = alltrue([
        for key, rules in local.target_rules : rules.initiative_exists && rules.initiative_contract_valid
      ])
      error_message = "Each initiative target must reference a known initiative resource output with a non-blank id and created_by_module marker. Offending assignments: ${join(", ", [for key, rules in local.target_rules : key if !rules.initiative_exists || !rules.initiative_contract_valid])}."
    }

    precondition {
      condition = alltrue([
        for key, rules in local.target_rules : rules.member_exists
      ])
      error_message = "Each initiative-target assignment reference_id must match a member of the referenced initiative. Offending assignments: ${join(", ", [for key, rules in local.target_rules : key if !rules.member_exists])}."
    }

    precondition {
      condition = alltrue([
        for key, rules in local.target_rules : rules.direct_id_valid
      ])
      error_message = "Each direct policy_definition_id must use a supported Azure Policy resource ID format. Offending assignments: ${join(", ", [for key, rules in local.target_rules : key if !rules.direct_id_valid])}."
    }

    precondition {
      condition = alltrue([
        for key, rules in local.target_rules : rules.definition_id_known
      ])
      error_message = "Each assignment must resolve a known assignment target ID (direct ID, initiative resource id or definition id). Offending assignments: ${join(", ", [for key, rules in local.target_rules : key if !rules.definition_id_known])}."
    }

    precondition {
      condition = alltrue([
        for key, rules in local.target_rules : rules.scope_id_valid
      ])
      error_message = "Assignment scope ID does not match its declared scope type. Offending assignments: ${join(", ", [for key, rules in local.target_rules : key if !rules.scope_id_valid])}."
    }

    precondition {
      condition = alltrue([
        for key, assignment in local.resolved_assignments : local.effective_effects[key] == null || local.normalised_supported_effects[key] == null || contains(local.normalised_supported_effects[key], local.effective_effects[key])
      ])
      error_message = "An assignment effective effect is unsupported by its target definition. Offending assignments: ${join(", ", [for key, assignment in local.resolved_assignments : key if local.effective_effects[key] != null && local.normalised_supported_effects[key] != null && !contains(local.normalised_supported_effects[key], local.effective_effects[key])])}."
    }

    precondition {
      condition     = alltrue([for key, effects in local.initiative_unsupported_effects : length(effects) == 0])
      error_message = "An effective initiative member effect is not declared by that member definition. Offending assignments: ${join(", ", [for key, effects in local.initiative_unsupported_effects : key if length(effects) > 0])}."
    }

    precondition {
      condition = alltrue([
        for key, assignment in local.resolved_assignments : !local.effect_override_conflicts[key]
        ]) && alltrue(flatten([
          for key, members in local.initiative_member_decisions : [
            for member in members : !member.override_conflict
          ]
      ]))
      error_message = "Assignment effect intent or applicable member effect overrides conflict. Check the assignment key, member reference_id and override selectors."
    }

    precondition {
      condition = alltrue([
        for key, assignment in local.resolved_assignments : !local.version_contradictions[key]
      ])
      error_message = "Assignment version intent conflicts across assignment, member or definition layers. Initiative content metadata is provenance only. Offending assignments: ${join(", ", [for key, assignment in local.resolved_assignments : key if local.version_contradictions[key]])}."
    }

    precondition {
      condition = alltrue([
        for key, rules in local.identity_rules : rules.strategy_valid
      ])
      error_message = "Identity strategy is not resolvable for an assignment. Offending assignments: ${join(", ", [for key, rules in local.identity_rules : key if !rules.strategy_valid])}."
    }

    precondition {
      condition = alltrue([
        for key, rules in local.identity_rules : rules.location_valid
      ])
      error_message = "An identity-required assignment is missing a non-global identity location. Offending assignments: ${join(", ", [for key, rules in local.identity_rules : key if !rules.location_valid])}."
    }

    precondition {
      condition = alltrue([
        for key, rules in local.identity_rules : rules.resource_group_valid
      ])
      error_message = "An identity-required assignment is missing an identity resource_group_name. Offending assignments: ${join(", ", [for key, rules in local.identity_rules : key if !rules.resource_group_valid])}."
    }

    precondition {
      condition = alltrue([
        for key, rules in local.identity_rules : rules.roles_known
      ])
      error_message = "An identity-required assignment has unknown candidate roles; supply role candidates or the definition role_definition_ids. Offending assignments: ${join(", ", [for key, rules in local.identity_rules : key if !rules.roles_known])}."
    }

    precondition {
      condition = alltrue([
        for key, rules in local.identity_rules : rules.roles_non_empty
      ])
      error_message = "An identity-required assignment has an empty candidate role set. Offending assignments: ${join(", ", [for key, rules in local.identity_rules : key if !rules.roles_non_empty])}."
    }

    precondition {
      condition = alltrue([
        for key, rules in local.identity_rules : rules.role_ids_valid
      ])
      error_message = "A candidate role definition ID is not a full Azure role definition resource ID with a GUID. Offending assignments: ${join(", ", [for key, rules in local.identity_rules : key if !rules.role_ids_valid])}."
    }
  }
}
