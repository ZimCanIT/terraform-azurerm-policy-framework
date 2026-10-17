# Assignments module

`assignments` is the typed Azure Policy assignment boundary. It consumes canonical definitions and initiatives or the resolved behaviour contract from `modules/behaviour-resolution`, then creates Azure Policy assignment resources for management groups, subscriptions, resource groups and resources.

It does not read policy source files, compute effective behaviour, or create identity/RBAC, remediation or exemption operations.

## Contract

### Input

`assignments` is a keyed object of the shared resolved-assignment records. Each entry must include:

- `assignment_key` as the map key
- `intent.target.reference_id`
- `intent.scope.type` and `intent.scope.id`
- `resolved.policy_definition_id`

The module requires the canonical nested `intent` and `resolved` record emitted by `modules/behaviour-resolution`. `resolved.policy_definition_id` is authoritative for the Azure resource; direct targets may retain `intent.target.policy_definition_id` for traceability, and initiatives use the resolved initiative policy definition ID. Legacy flattened records are rejected. Provider configuration stays with the caller; the module declares its `required_providers` constraint only.

Identity attachment is a separate top-level module input. `identity_bindings` is a map keyed by assignment key whose values are the `assignment_binding` records of the identity-rbac module, which its `assignment_bindings` output returns, so the output wires in without reshaping. Each record has `assignment_key`, which must equal its key, `identity_strategy`, which is `none` or `user_assigned`, and the identifiers `id`, `identity_id` and `principal_id`. A `none` record carries null identifiers. A `user_assigned` record carries the identity resource ID in `id`, starting with `/`, and a GUID in `principal_id`. The module attaches the identity to the assignment and never creates the identity or grants roles.

Optional intent fields are:

- `parameters`
- `selectors`
- `overrides`
- `exclusions`
- `enforcement_mode`
- `non_compliance_messages`
- `rollout`

`resolved.parameter_schema` is keyed by parameter name. For a direct definition target it is the definition schema; for an initiative target it is the policy set's own schema. Supported Azure Policy parameter types are `String`, `Array`, `Object`, `Boolean`, `Integer`, `Float` and `DateTime`. Values must retain their JSON type: `Integer` and `Float` require JSON numbers (so `5` is valid for either, while `"5"` is not); `DateTime` requires a valid RFC 3339 timestamp string. Arrays may contain heterogeneous JSON values, and objects may contain nested values. `allowedValues` matching preserves JSON types, so a number does not match a numeric-looking string; for `Array`, every supplied or default array element must match an allowed value. Each schema entry may contain `type`, `defaultValue` and `allowedValues`; defaults are used in the provider payload when no value is supplied, required entries without defaults must be supplied, and unknown names, incompatible Terraform values and disallowed values are rejected. Unsupported or malformed schema types fail with assignment and parameter attribution. An unknown schema accepts only absent or explicit-empty intent. The payload input source is `intent.parameters`: `resolved.parameter_values` is the resolver's effective member view, not a payload source, because it may include member template-expression mappings used to compose the initiative. Member defaults and mappings are never injected into a set assignment payload. The canonical output's `parameters` field preserves supplied intent values; when a target has no supplied values, it reports `null` for an unknown schema and `{}` for a verified schema, without projecting schema defaults into the review output. Selectors, overrides and non-compliance messages are applied only when their corresponding resolved declarations support the requested kinds and values. AzureRM limits are enforced as 400 exclusions, 10 overrides, and 50 values per selector list. Parameter diagnostics name the assignment key and offending parameter names.

For an initiative target, `resolved.members` and `resolved.member_reference_ids` carry the complete member inventory. `resolved.overrides` is the authoritative provider payload. The resolver compiles an explicit member-scoped `effect` request into a `policyEffect` override selected by `target.reference_id`; a request cannot alter another member. The assignments module passes that compiled payload to Azure and exposes it in its canonical output. `resolved.governance` is the merged definition, initiative and assignment governance object; the assignment value wins for duplicate keys, and the result is projected into Azure assignment metadata. A direct-target selected version is rejected because the declared AzureRM assignment resource does not expose `definitionVersion`; an exact `x.y.z` pin is not treated as enforced merely because its text is exact. By default, an inherited definition pin remains selected and is rejected for a direct target. To deliberately use the unversioned Azure policy ID, set `intent.version_binding = "unversioned"` on a direct target with no assignment-level version request. This explicit opt-out sets `resolved.selected_version` to null while preserving definition-level pin/constraint provenance in `resolved.source_version`; it does not guarantee a policy version. Initiatives cannot use this option. `resolved.required_roles` records, including any `grant_scope` field, pass through to the `assignments` output.

The nested `intent` and `resolved` containers are exact contracts. Legacy flattened fields such as `target`, `scope`, `parameters`, `selectors`, `overrides`, `rollout` and `enforcement_mode` are rejected.

`scope.type` must be one of `management_group`, `subscription`, `resource_group` or `resource`, and `scope.id` must be the matching Azure scope ID. A `resource` scope ID names the provider, the type and the resource, as in `/subscriptions/<subscription-id>/resourceGroups/<group>/providers/Microsoft.Storage/storageAccounts/<name>`; a bare resource type is rejected. Management-group assignment names are limited to 24 characters; other scopes are limited to 64. Long or colliding deterministic bases receive an eight-character SHA-1 key suffix, so changing the assignment key can replace the Azure assignment.

### Output

- `assignments`: canonical review output keyed by assignment key
- `resolved_assignments`: the received records with the assignment lifecycle binding merged in
- `assignment_names`: deterministic Azure Policy assignment names
- `management_group_policy_assignment_ids`
- `subscription_policy_assignment_ids`
- `resource_group_policy_assignment_ids`
- `resource_policy_assignment_ids`
- `replacement_review`: name, scope, target and identity changes that require replacement review

`resolved_assignments` returns each received record unchanged except for its `assignment` binding, which holds the Azure ID and the deterministic name of the assignment this module created. It is the `resolved_assignments` input of the operations module, so no caller rebuilds the binding. While an assignment is planned for creation its ID is unknown until apply, and a null ID means no assignment resource exists for the record. A consumer treats both as not yet bound and never as a match.

## Example

```hcl
module "assignments" {
  source = "./modules/assignments"

  assignments = {
    platform_baseline = {
      intent = {
        target = {
          reference_id         = "platform-baseline"
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c"
        }
        scope = {
          type = "subscription"
          id   = "/subscriptions/00000000-0000-0000-0000-000000000000"
        }
        parameters = {
          effect = {
            value = "Audit"
          }
        }
        rollout = {
          stage  = "pilot"
          intent = "audit-first"
        }
      }
      resolved = {
        policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c"
        parameter_values     = { effect = "Audit" }
      }
    }
  }
}
```

The runnable scope and parameter fixture is in the [typed scopes example](examples/typed-scopes/README.md).

## Azure permissions

The assignment state creates policy assignments and attaches identities that already exist. The principal that applies it needs:

| Resource | Operations | Scope |
| --- | --- | --- |
| Policy assignments | `Microsoft.Authorization/policyAssignments/read`, `write` and `delete` | The scope of each assignment |
| Identity attachment | `Microsoft.ManagedIdentity/userAssignedIdentities/*/assign/action` | Each identity named in `identity_bindings` |

Resource Policy Contributor (`36243c78-bf99-498c-9df9-86d9f8d28608`) at the assignment scope covers the first row. Managed Identity Operator (`f1a07417-d97a-45cb-824c-7a7467783830`) on the identity covers the second. Resource Policy Contributor also carries definition, exemption and remediation operations, so a state that must not hold those uses a custom role limited to the policy assignment operations. That a policy assignment needs the assign action on its identity is expected from the identity model and has not been confirmed with a least-privileged principal.

This state needs no role assignment, identity creation, definition, exemption or remediation operation. Role contents were read from Microsoft Learn on 17 October 2026. Provider configuration stays with the caller.

## Separation of duties

Assignments decide where a control applies, with which parameters and at what enforcement. The module attaches the identity that `identity_bindings` names and declares no identity or role-assignment resource, so it cannot create an identity or grant a role. The repository gate fails if that changes. Keep the principal that applies assignments separate from the one that applies role grants, and give it Managed Identity Operator only on the identity resource group rather than on every identity in a subscription. Apply this state after content and role grants, and destroy it before them.

## Compatibility

This module declares Terraform `>= 1.12.0` and AzureRM `>= 5.0.0, < 6.0.0`. AzureRM 5.0.0 resource schemas are compatible with the resources and arguments used by this module.
