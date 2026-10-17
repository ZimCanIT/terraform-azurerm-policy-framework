# Minimal audit assignment example

The smallest real assignment through the root module. It assigns one verified Azure built-in policy definition with the Audit effect at subscription scope. No custom definitions, initiatives, identities, role grants, remediations or exemptions are created.

## Verified built-in definition

The default assignment target is a real Azure built-in policy definition, verified with read-only Azure CLI on 27 September 2026:

| Property | Value |
| --- | --- |
| Display name | Audit VMs that do not use managed disks |
| Resource ID | `/providers/Microsoft.Authorization/policyDefinitions/06a78e20-9358-41c9-923c-fb736d382a4d` |
| Policy type | BuiltIn |
| Mode | All |
| Azure reported version | 1.0.0 (source provenance verified for this built-in) |
| Policy rule effect | audit |
| Parameters | none declared, none required |

Verification command and observed result:

```powershell
az policy definition show --name 06a78e20-9358-41c9-923c-fb736d382a4d --query "{displayName: displayName, policyType: policyType, mode: mode, version: version, versions: versions, parameters: parameters, effect: policyRule.then.effect}"
```

The command returned `policyType: BuiltIn`, `mode: All`, `version: 1.0.0`, `versions: ["1.0.0"]`, `parameters: {}` and `policyRule.then.effect: audit`, confirming the Audit effect with no required parameters. The source entry retains `pinned_version = "1.0.0"` as provenance. AzureRM policy-assignment resources do not expose a definition-version field, so this direct assignment deliberately uses `version_binding = "unversioned"`: it targets the policy definition ID without a guarantee that version 1.0.0 is deployed. `resolved_assignment_review.selected_version` is null and `source_version` reports 1.0.0. Recheck the built-in before deployment if Azure changes its versions or behaviour.

## Prerequisites

- Terraform 1.12.0 or newer.
- Azure CLI authenticated: `az login`.
- Select the subscription that will hold the assignment: `az account set --subscription <subscription-id>`. The azurerm provider resolves its subscription from the CLI profile or `ARM_SUBSCRIPTION_ID`; no subscription ID is hardcoded in the example.

## Inputs

| Variable | Default | Purpose |
| --- | --- | --- |
| `assignment_scope_id` | `/subscriptions/00000000-0000-0000-0000-000000000000` | Subscription scope resource ID for the assignment. The default is a synthetic, well-formed placeholder for offline checks; substitute the real resource ID `/subscriptions/<subscription-id>` for plan and apply. |
| `built_in_audit_definition_id` | the verified built-in ID above | Override to audit a different built-in definition; the source provenance remains `1.0.0` and the example declares the `Audit` effect, so an override must be compatible with those settings. The direct assignment still makes no deployed-version guarantee. |
| `assignment_key` | `audit-sub` | Stable Terraform key used to derive the assignment address and Azure name. Changing it creates a new assignment address and name at the same scope. |
| `assignment_owner` | `platform-governance` | Owner written to assignment governance metadata. Changing it updates metadata on the existing assignment. |

## Run sequence

```powershell
terraform -chdir=examples/minimal-audit-assignment init
terraform -chdir=examples/minimal-audit-assignment validate
terraform -chdir=examples/minimal-audit-assignment plan -var 'assignment_scope_id=/subscriptions/<subscription-id>'
terraform -chdir=examples/minimal-audit-assignment apply -var 'assignment_scope_id=/subscriptions/<subscription-id>'
```

For an in-place governance metadata update, change `assignment_owner` and plan/apply with the same `assignment_key`. For an explicit assignment-name replacement at the same subscription scope, change `assignment_key` to a new stable value and review the replacement plan before applying; the previous assignment remains until Terraform performs that replacement.

- `terraform init` and `terraform validate` run with the synthetic default scope ID. Validation proves configuration and contract syntax only; it does not evaluate variable validation rules or plan-time preconditions and does not prove a safe deployment.
- `terraform plan` and `terraform apply` require a real subscription scope ID. The framework enforces, at plan time, that a subscription scope ID is a full Azure resource path; the synthetic default has the right shape but does not identify a deployable subscription.
- `terraform plan` is read-only and mutates nothing.

## Expected outputs

- `resolved_assignment_review`: map keyed by `assignment_key`, with `scope_type` of `subscription`, `effective_effect` of `Audit`, `selected_version` of `null`, `source_version` of `1.0.0`, `version_binding` of `unversioned`, governance owner, built-in `policy_definition_id`, `identity_strategy` of `none`, `enforcement_mode` of `Default`, and `assignment_id` and `assignment_name` once applied.
- `plan_summary`: `assignment_count` of `1`, `subscriptions` of `1` and no other scope types.

The default assignment name is deterministic, derived from the assignment key, scope type and target reference ID: `audit-sub-subscription-built-in-audit`. No random suffixes are generated.

## Cost and impact

The Audit effect never mutates resources: it records non-compliance in Azure Policy compliance results only. The assignment needs no managed identity and creates no role assignments. Azure Policy itself carries no charge. The only state change is the single subscription-scoped policy assignment resource.

## Cleanup

```powershell
terraform -chdir=examples/minimal-audit-assignment destroy -var 'assignment_scope_id=/subscriptions/<subscription-id>'
```

Confirm absence after the destroy completes:

```powershell
az policy assignment show --name audit-sub-subscription-built-in-audit --scope /subscriptions/<subscription-id>
```

A not-found response confirms removal; an access denied, expired authentication or timeout response is inconclusive and must be retried.
