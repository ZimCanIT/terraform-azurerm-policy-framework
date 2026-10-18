# Behaviour-resolution module

`behaviour-resolution` is the authoritative effective-behaviour boundary. It consumes canonical definition and initiative resource outputs plus assignment intent, resolves decisions itself and emits deterministic records for assignments, identity/RBAC and operations (remediations and exemptions). It does not read source files or create Azure resources.

## Contract

### Inputs

| Input | Type | Default | Behaviour |
| --- | --- | --- | --- |
| `definitions` | `any` | `{}` | The `definitions` output of `modules/content`: actual resource outputs keyed by stable catalogue key, including IDs, capabilities, effects, parameters, versions and role candidates. Validation checks only that the value is a keyed object or map. Fields a definition does not carry read as unknown (null). |
| `initiatives` | `any` | `{}` | The `initiatives` output of `modules/content`: actual resource outputs keyed by stable catalogue key, including `id`, `created_by_module`, the initiative set `parameter_schema`, and the complete list of resolved member references with their own schemas, mappings, version intent, capabilities, role candidates and governance. Validation rejects any initiative field outside `catalogue_key`, `id`, `name`, `display_name`, `description`, `management_group_id`, `metadata`, `parameters`, `parameter_schema`, `policy_definition_groups`, `policy_definition_references`, `governance`, `version` and `created_by_module`, and any member field that `modules/content` does not emit. Every initiative must carry a non-blank `id`, a non-null `created_by_module` and a `policy_definition_references` list of member objects. An absent, null or non-list membership fails validation rather than being read as an empty membership. |
| `assignments` | `any` | `{}` | Assignment intent keyed by stable assignment key, described under Assignment intent. |

All three inputs must be keyed objects or maps. A list, scalar or null value fails variable validation with a message that names the input.

### Assignment intent

Assignment keys must be non-blank and every value must be an object. Only the fields below are accepted. Any other field fails variable validation, so a caller-supplied `resolved` decision is rejected.

| Field | Shape | Behaviour |
| --- | --- | --- |
| `target` | object, required | A non-blank `reference_id` and exactly one non-blank `definition_key`, `initiative_key` or `policy_definition_id`. For an initiative target `reference_id` must match a member of that initiative, and the record carries that member's parameter mapping. For other targets it is the reference ID that override selectors match. A direct `policy_definition_id` must be `/providers/Microsoft.Authorization/policyDefinitions/<name>`, the same path under `/subscriptions/<id>` or the same path under `/providers/Microsoft.Management/managementGroups/<name>`. |
| `scope` | object, required | `type` is `management_group`, `subscription`, `resource_group` or `resource`, and `id` is non-blank. The contract guard then requires `id` to match its type: `/providers/Microsoft.Management/managementGroups/<name>`, `/subscriptions/<id>`, `/subscriptions/<id>/resourceGroups/<name>` or `/subscriptions/<id>/resourceGroups/<name>/providers/<namespace>/<type>/<name>` with optional further `/<segment>` parts. `<id>` is 36 hexadecimal or hyphen characters. |
| `parameters` | null or object | Assignment-time parameter values, passed through as `intent.parameters`. |
| `overrides` | null or list of objects | Effect overrides. `policyDefinitionReferenceId` selectors with `in` or `not_in` choose the members that receive an override. |
| `effect` | null or printable string | A requested effect, normalised to the Azure effect name. For an initiative target it applies to the member named by `target.reference_id` only. |
| `version_constraint`, `pinned_version` | null or printable string | Requested version intent. |
| `version_binding` | omitted or `unversioned` | Requests Azure's unversioned policy ID. It is invalid for an initiative target and together with `version_constraint` or `pinned_version`. |
| `identity` | object | Optional identity intent. `strategy` must be omitted or `user_assigned` when an identity is required and omitted or `none` otherwise. `location` and `resource_group_name` are required when an identity is required, and `location` must not be `global`. |
| `role_grant_scopes` | null or map | Role definition ID to an explicit grant scope of any scope type above. Keys are matched exactly against the candidate role definition IDs. An entry that matches no candidate role has no effect, and that role keeps the assignment scope. |
| `selectors`, `exclusions`, `enforcement_mode`, `non_compliance_messages`, `rollout`, `governance` | any | Carried into `intent`. `governance` is also merged into the resolved governance. |

### Outputs

| Output | Contents |
| --- | --- |
| `assignments` | Resolved assignment records keyed by stable assignment key. Each record holds `assignment_key`, `intent`, `resolved` and `assignment`. |
| `resolution_summary` | `total_assignments` and the sorted `definition_keys`, `initiative_keys` and `assignment_keys`. It carries no policy content. |
| `definition_ids` | The `id` of each input definition, keyed by stable catalogue key. |
| `initiative_ids` | The `id` of each input initiative, keyed by stable catalogue key. |

In each `assignments` record:

- `intent` echoes the caller's `target`, `scope`, `parameters`, `selectors`, `overrides`, `exclusions`, `enforcement_mode`, `non_compliance_messages`, `rollout` and `governance`, plus `version_constraint`, `pinned_version` and `version_binding`.
- `resolved` holds the decisions. These are the Azure target `policy_definition_id`, `definition_key`, `initiative_key`, `member_reference_id`, the requested, member, definition default and effective effects, the requested, inherited, selected and source versions, `initiative_content_version`, `parameter_schema`, `parameter_values`, `parameter_mappings`, `capabilities`, `list_fields`, the complete `members` list, `selectors`, the compiled `overrides`, `member_reference_ids`, `exclusions`, `identity`, `required_roles`, `remediation_eligibility`, `remediation_reason`, the merged `governance` and `resolution_rationale`.
- `assignment` is the placeholder `{ id = null, name = null }`. This module creates no resource.

## Behaviour

Effect resolution is explicit. Applicable effect overrides take precedence, followed by a member-scoped assignment effect, initiative member effect, definition capability default and policy-rule default. An initiative assignment resolves every member independently and emits `resolved.members`; an assignment `effect` request compiles to a `policyEffect` override scoped to `target.reference_id`, so it cannot affect other set members. `in` and `not_in` selectors for `policyDefinitionReferenceId` determine which members receive an override. Conflicting applicable overrides fail with a guard. Resource-location selectors can make the effective value conditional; in that case the member effect remains null and identity and role decisions include every possible effect. Initiative member `required` metadata is preserved and is not treated as an effect. `enforcement_mode` is assignment intent only. Supported effects are normalised to Azure names before containment validation; null remains unknown.

Version precedence is direct assignment pin or constraint, initiative member pin or constraint, then definition pin or constraint. Initiative `version` metadata is provenance and does not select a policy version. Requested, inherited, selected and content metadata remain separate; contradictory version intent is not widened or silently replaced. Definition-level version intent is also exposed as `resolved.source_version`. Direct-target selected versions are rejected by assignments because AzureRM assignment resources do not expose a `definitionVersion` argument. A direct assignment may opt into Azure's unversioned policy ID with `version_binding = "unversioned"`; this is an explicit request to use the policy ID without a deployment version guarantee, not evidence that the source pin was deployed. The resolver then preserves the source pin in `source_version` and sets `selected_version` to null. The option is invalid for initiatives or with an assignment-level version request.

Initiative member references select definitions and preserve member parameter mappings. An initiative-keyed assignment resolves its Azure target to the initiative's own policy set definition ID, never to one member policy definition. For an initiative target `resolved.effective_effect` is the effect shared by every member when all members have a known effective effect and agree, and null otherwise. `resolved.members` contains every set member, including each member's ID, source/provenance, effective and possible effects, schema, mappings, version, capability/list fields, governance and role candidates.

`resolved.parameter_schema` is the set's own namespace for an initiative target and the definition's parameters otherwise. `resolved.parameter_mappings` is the targeted member's mapping on its own. `resolved.parameter_values` is that mapping merged with the assignment `parameters`, assignment values winning. Both are null when nothing was supplied, and an explicit empty map stays empty. The resolver does not check parameter values. The assignments module validates the caller's `intent.parameters` against `parameter_schema` and sends only those values, because member mapping keys are set-definition wiring and not assignment parameters.

Identity is required when the effective effect is `Modify` or `DeployIfNotExists` and unknown when the effective effect is unknown. For an initiative target it is required if any member can execute one of those effects, and the required roles are the deduplicated union for those members. `resolved.identity` carries `required`, `strategy`, `name_basis` (the assignment key), `location`, `resource_group_name` and `rationale`. A missing or `global` identity location, a missing identity resource group, and unknown, empty or malformed role candidates block the contract. Each required role carries its role definition ID, the fixed purpose `policy_effect` and a `grant_scope`: the `role_grant_scopes` entry for that exact role definition ID, otherwise the assignment scope. Nothing is granted here. Remediation is eligibility only and is `eligible` only when required roles are known and non-empty.

Governance is shallow-merged by key in definition, initiative, assignment order, so the most specific assignment value wins. The resolver preserves the combined object; assignments pass it into Azure metadata and expose it on the canonical assignment output.

The resolved record also emits `definition_default_effect`, the definition's own default (capability default, otherwise the policy-rule effect), so downstream boundaries can prove whether an effective effect needs an explicit override or parameter projection.

Unknown optional values are null and explicitly empty collections remain empty. One blocking `terraform_data.contract_guard` reports resolution failures. Each precondition names the broken rule and the offending assignment keys. The guard carries no input, so a change to the assignment set plans no change to the guard itself.

## Example

```hcl
module "behaviour_resolution" {
  source = "./modules/behaviour-resolution"

  definitions = module.content.definitions
  initiatives = module.content.initiatives
  assignments = {
    platform_baseline = {
      target = {
        reference_id   = "platform-baseline"
        definition_key = "allowed_locations"
      }

      scope = {
        type = "subscription"
        id   = "/subscriptions/00000000-0000-0000-0000-000000000000"
      }
    }
  }
}
```

## Compatibility

This provider-free child module targets Terraform `>= 1.12.0`. AzureRM compatibility is not declared or required by the resolver; provider-backed consumer compatibility remains a separate evidence gate. The repository's compatibility workflow runs this module's test suite on Terraform 1.12.0 and 1.15.9.

## Validation

Run formatting and backend-disabled validation from the repository root:

```powershell
terraform fmt -check -recursive modules/behaviour-resolution
terraform -chdir=modules/behaviour-resolution init -backend=false -input=false
terraform -chdir=modules/behaviour-resolution validate -no-color
```

`terraform validate` does not evaluate variable validation rules or preconditions. Run `terraform test` from the module directory to exercise the resolution decisions and the invalid-input cases without a provider or Azure credentials. The repository CI workflows run the suite. Provider-backed consumer plans are separate evidence from this provider-free suite.
