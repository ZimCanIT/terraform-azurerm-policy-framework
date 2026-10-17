# Complete policy lifecycle example

This example calls the root module, which wires the catalogue, content, behaviour-resolution, identity-rbac, assignments, operations and governance modules. It takes a portable policy catalogue from source fixture through to a governed assignment, an explicit remediation request and a time-bound exemption against a disposable Azure target.

Every module runs in one state under one principal, so this example does not separate duties. [`examples/state-separated-lifecycle`](../state-separated-lifecycle/README.md) runs the same lifecycle as separate states.

## Content flow

1. A portable catalogue fixture (custom definition, initiative and built-in reference) enters the catalogue source adapter.
2. The content module turns the canonical envelopes into Azure Policy definitions and initiatives.
3. The behaviour resolver derives the effective effect, version, identity requirement and remediation eligibility for the requested assignment.
4. The identity-rbac module creates the assignment's user-assigned managed identity and least-privilege role grant. The assignments module creates the typed assignment and attaches that identity.
5. The operations module issues an explicit, eligible remediation request against the disposable target and reports status. The request omits `policy_assignment_id`, so the module takes it from the assignment the request names.
6. The operations module records the governed exemption with owner, reason, ticket, approver, compensating control and future expiry, tied to the assignment this example creates.
7. The governance module traces the example's requirement to its control and its assignment.

The Modify definition adds the configured tag only when it is absent from a storage account. Existing tag values, including different or empty values, are preserved. Once remediation adds the tag, the resource no longer matches the rule's non-compliance condition.

## Variables

All defaults are synthetic. The public input variables are declared in `variables.tf`; this table is the complete list.

| Variable | Synthetic default | Supplied by `environments/uat` |
| --- | --- | --- |
| `policy_subscription_id` | `00000000-0000-0000-0000-000000000000` | Yes, the authorised subscription (qualifies the role definition IDs). |
| `target_resource_group_name` | `rg-zctfp-example` | Yes, the disposable target resource group. |
| `target_location` | `westeurope` | Yes, the target region. |
| `target_storage_account_name` | `zctfpexamplestore` | Yes, the disposable remediation target. |
| `target_resource_group_id` | `/subscriptions/00000000-.../resourceGroups/rg-zctfp-example` | Yes, keeps Modify and remediation contained to the run's resources. |
| `identity_location` | `westeurope` | Yes, the managed identity region. |
| `identity_resource_group_name` | `rg-zctfp-example` | Yes, hosts the managed identity. |
| `create_exemption` | `false` | Stage 2 only: `true` creates the exemption after the remediation assertion. |
| `evaluation_time` | `null` | Set once per run to a fixed RFC3339 instant for repeatable exemption expiry classification; never use a moving timestamp for convergent plans. |
| `exemption_expiry` | `2027-01-31T00:00:00Z` | Yes, RFC3339; persisted for the run and changed only in the renewal step. |
| `exemption_assignment_id` | empty | Stage 2 only: the created assignment ID from the stage 1 output. |

No tenant identifiers, subscription IDs or credentials are checked in. The `environments/uat` profile is a documented input profile, not a separate state root: the example root owns its provider configuration and default local state, and the runbook's staged applies all use that one state, so the profile supplies scope and tenant values through the tfvars template only.

## Staged run sequence

The example applies in stages: policy content first, then the identity, role grant and assignment layer, then the remediation and exemption operations. The staged applies all use one state. Exact commands and hand-off values are in the [uat runbook](environments/uat/README.md).

## Expected outputs

The example's `outputs.tf` reports:

- `resolved_assignments` with the effective effect, version and identity decision per assignment key, including the created assignment ID.
- `governance` requirements and traceability referencing assignments that exist in this configuration.
- `resolved_assignment_id` and `exemption_assignment_id`, the created `modify-tag-rg` assignment ID used for read-back and as the stage 2 exemption input.
- `definition_ids` keyed by catalogue key and `set_definition_id`, the created definition and initiative IDs.
- `remediation_and_exemption`, a compact review of the remediation request status and eligibility and of the exemption lifecycle.

## Cost and impact

The example creates one disposable resource group and one storage account as the remediation target, plus a user-assigned managed identity. The assignment uses the Modify effect with a least-privilege Tag Contributor grant scoped to the target resource group, so policy effects and remediation are contained to resources created for the run. Azure Policy owns only the `CostCentre` tag it adds; Terraform retains ownership of `Owner` and ignores only the policy-managed tag key for convergence. Delete the target resource group after the run to stop all charges.

## Cleanup

Run `terraform destroy` with the final stage's variable file, as the uat runbook describes, then verify with Azure CLI or provider data that the resource group, storage account, identity, role assignment, remediation, exemption and policy resources are gone. A successful destroy command alone is not proof of absence.
