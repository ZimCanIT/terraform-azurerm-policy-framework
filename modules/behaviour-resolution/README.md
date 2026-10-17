# Behaviour-resolution module

`behaviour-resolution` is the authoritative effective-behaviour boundary. It consumes canonical definition and initiative resource outputs plus assignment intent, resolves decisions itself and emits deterministic records for assignments, identity/RBAC, remediations and exemptions. It does not read source files or create Azure resources.

## Contract

### Inputs

| Input | Type | Behaviour |
| --- | --- | --- |
| `definitions` | `any` | Actual `modules/definitions` resource outputs keyed by stable catalogue key, including IDs, capabilities, effects, parameters, versions and role candidates. |
| `initiatives` | `any` | Actual `modules/initiatives` resource outputs keyed by stable catalogue key, including `id`, `created_by_module`, the initiative set `parameter_schema`, and the complete list of resolved member references with their own schemas, mappings, version intent, capabilities, role candidates and governance. |
| `assignments` | `any` | Assignment intent keyed by stable assignment key. Exactly one of `definition_key`, `initiative_key` or `policy_definition_id` is required. `role_grant_scopes` is an optional map of role definition ID to an explicit grant scope that differs from the assignment scope. Caller-supplied `resolved` decisions are rejected. |

### Outputs

| Output | Contents |
| --- | --- |
| `assignments` | Canonical resolved assignment records keyed by stable assignment key. |
| `resolution_summary` | Non-sensitive summary of resolved keys and counts. |
| `definition_ids` | Definition IDs keyed by stable catalogue key. |
| `initiative_ids` | Initiative IDs keyed by stable catalogue key. |

## Behaviour

Effect resolution is explicit. Applicable effect overrides take precedence, followed by a member-scoped assignment effect, initiative member effect, definition capability default and policy-rule default. An initiative assignment resolves every member independently and emits `resolved.members`; an assignment `effect` request compiles to a `policyEffect` override scoped to `target.reference_id`, so it cannot affect other set members. `in` and `not_in` selectors for `policyDefinitionReferenceId` determine which members receive an override. Conflicting applicable overrides fail with a guard. Resource-location selectors can make the effective value conditional; in that case the member effect remains null and identity and role decisions include every possible effect. Initiative member `required` metadata is preserved and is not treated as an effect. `enforcement_mode` is assignment intent only. Supported effects are normalised to Azure names before containment validation; null remains unknown.

Version precedence is direct assignment pin or constraint, initiative member pin or constraint, then definition pin or constraint. Initiative `version` metadata is provenance and does not select a policy version. Requested, inherited, selected and content metadata remain separate; contradictory version intent is not widened or silently replaced. Definition-level version intent is also exposed as `resolved.source_version`. Direct-target selected versions are rejected by assignments because AzureRM assignment resources do not expose a `definitionVersion` argument. A direct assignment may opt into Azure's unversioned policy ID with `version_binding = "unversioned"`; this is an explicit request to use the policy ID without a deployment version guarantee, not evidence that the source pin was deployed. The resolver then preserves the source pin in `source_version` and sets `selected_version` to null. The option is invalid for initiatives or with an assignment-level version request.

Initiative member references select definitions and preserve member parameter mappings. An initiative-keyed assignment resolves its Azure target to the initiative's own policy set definition ID, never to one member policy definition. `resolved.members` contains every set member, including each member's ID, source/provenance, effective and possible effects, schema, mappings, version, capability/list fields, governance and role candidates. `resolved.parameter_schema` is the set's own namespace; member defaults and mappings are not injected into set assignment values. Assignment parameter values are checked against the set schema; absent values remain null and explicit empty maps remain empty. Identity is required if any member can execute `Modify` or `DeployIfNotExists`; required roles are the deduplicated union for those members. Missing identity location, resource group or role candidates block the contract. Role candidates, grant purpose and explicit grant scope are emitted without granting RBAC; each role grant scope defaults to assignment scope and may be overridden per role through `role_grant_scopes`. Remediation is eligibility only and is `eligible` only when required roles are known and non-empty.

Governance is shallow-merged by key in definition, initiative, assignment order, so the most specific assignment value wins. The resolver preserves the combined object; assignments pass it into Azure metadata and expose it on the canonical assignment output.

The resolved record also emits `definition_default_effect`, the definition's own default (capability default, otherwise the policy-rule effect), so downstream boundaries can prove whether an effective effect needs an explicit override or parameter projection.

The output uses the shared nested `intent`, `resolved` and `assignment` record. Unknown optional values are null; explicitly empty collections remain empty. Resolution failures identify the target or assignment rule in the contract guard.

## Example

```hcl
module "behaviour_resolution" {
  source = "./modules/behaviour-resolution"

  definitions = module.definitions.definitions
  initiatives = module.initiatives.initiatives
  assignments = {
    platform_baseline = {
      target = {
        reference_id   = "platform-baseline"
        definition_key  = "allowed_locations"
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

This provider-free child module targets Terraform `>= 1.12.0`. AzureRM compatibility is not declared or required by the resolver; provider-backed consumer compatibility remains a separate evidence gate.

## Validation

Run formatting and backend-disabled validation from the module root:

```powershell
terraform fmt -check -recursive modules/behaviour-resolution
terraform -chdir=modules/behaviour-resolution init -backend=false -input=false
terraform -chdir=modules/behaviour-resolution validate -no-color
```

Authorised behavioural evidence is recorded in the branch explanation and handoff. The module test suite may be run by the task owner; provider-backed consumer plans remain separate from provider-free resolver evidence.
