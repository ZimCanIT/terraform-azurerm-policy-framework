# Identity-RBAC module

`identity-rbac` consumes the shared resolved-assignment map and creates only the identities and least-privilege role grants already decided by behaviour resolution. It does not read policy files, resolve effects, infer roles or create remediation operations.

## Contract

### Inputs

| Input | Type | Default | Behaviour |
| --- | --- | --- | --- |
| `assignments` | `any` | `{}` | The `assignments` output of `modules/behaviour-resolution`: resolved assignment records keyed by stable `assignment_key`. |

Variable validation rejects:

- a value that is not a keyed object or map
- a record without a non-blank key, an `intent.scope` object and a `resolved.identity` object, or with a field other than `assignment_key`, `intent`, `resolved` and `assignment`
- an `intent.scope.type` outside `management_group`, `subscription`, `resource_group` and `resource`, or an `id` that does not match the form of its type
- an identity decision whose `required` is not a boolean, whose `strategy` is neither `none` nor `user_assigned`, or whose strategy is not `user_assigned` when required and `none` otherwise
- a required identity without non-blank string `name_basis`, `location` and `resource_group_name`
- `required_roles` that is null, is not a list, is empty for a required identity or is non-empty without one
- a required role with a field other than `role_definition_id`, `purpose` and `grant_scope`, or two roles of one assignment with the same role definition (compared case-insensitively) and grant scope
- `list_fields.role_definition_ids` that is null, is not a list, holds an ID that is not a tenant-level or subscription-level role definition resource ID, is empty for a required identity or is non-empty without one

### Resolved records

Each record contains `intent.scope` and the resolver-owned `resolved` object. The module consumes `resolved.identity` and `resolved.required_roles` without recomputing effect or identity requirements. Each resolved role carries a `grant_scope` selected by the resolver: an explicit `role_grant_scopes` override for that role definition wins and otherwise the resolver falls back to the assignment scope.

For initiative targets, behaviour resolution supplies the complete `resolved.members` list and aggregates `resolved.identity.required`, `resolved.required_roles` and `resolved.list_fields.role_definition_ids` across every member that can execute an identity effect. Identity-RBAC does not choose one member or infer a set-wide role from a single effect. It creates grants from the complete aggregate and returns `members` unchanged in the `identity_rbac` record for review. A null aggregate remains unknown and is rejected for an identity-required decision; a verified empty aggregate is accepted only when identity is not required.

Supported identity strategies are:

- `none`, with `required = false` and a verified empty role list
- `user_assigned`, with `required = true`, deterministic `name_basis`, `location`, `resource_group_name` and at least one required role

System-assigned identities and unknown identity decisions are rejected. A required identity is returned as an `assignment_binding`; the assignments module consumes that binding to attach the user-assigned identity to the policy assignment. The `assignment_bindings` output carries exactly those bindings, keyed by assignment key, so the caller passes it to the assignments module as `identity_bindings` without reshaping. The relationship is acyclic: the resolver feeds both modules, and the assignment resource consumes the identity output.

Each resolved role must provide:

- a full tenant-level or subscription-level Azure role-definition resource ID ending in a role GUID
- a non-blank purpose
- an explicit management-group, subscription, resource-group or resource grant scope

Roles must be declared by the resolved requirement and must also be present in the resolver's validated candidate role list, including a valid role-definition resource ID. `Contributor` and `Owner` are identified by their terminal role GUID, so the exclusion holds for the tenant-level and the subscription-prefixed ID form, and no fallback role is selected. Management-group, subscription, resource-group and resource scopes are supported; a resource scope must name a resource, so a bare provider namespace or a resource type without a resource name is rejected.

Azure normalises tenant-level role-definition IDs to the subscription-prefixed form on read-back when the grant scope is not the tenant itself. Declaring grants in tenant form therefore produces permanent drift and replacement churn for such scopes; declare the subscription-prefixed form when the grant scope carries a subscription.

Grant-scope handling is fail closed at this boundary: the module consumes the resolved `grant_scope` through guarded access and never widens a blank or unparsable grant scope to the assignment scope, rejecting the grant instead. Malformed or unknown grants fail validation rather than becoming an empty collection; null remains unknown and an explicit empty list is accepted only for an identity-free decision.

Guards are named so failures are attributable. The `assignments` variable validation rejects structural contract breaches, and each role assignment carries named preconditions that report the grant key, assignment key and offending role definition:

- `grant_scope_valid`: non-blank, well-formed grant scope, never widened to the assignment scope
- `role_definition_valid`: full role-definition resource ID ending in a role GUID
- `broad_role_excluded`: terminal role GUID is neither `Contributor` nor `Owner`
- `purpose_supplied`: non-blank resolved purpose
- `role_declared`: role definition is present in the resolved candidate role list

## Outputs

| Output | Contents |
| --- | --- |
| `identity_rbac` | One non-sensitive record per assignment key, described below. |
| `replacement_impact` | The `replacement_impact` field of each `identity_rbac` record, keyed by assignment key. |
| `assignment_bindings` | The non-null `assignment_binding` of each record, keyed by assignment key. |

Each `identity_rbac` record preserves:

- `assignment_key`, the assignment scope and the effective effect
- identity requirement, strategy and deterministic name
- identity and principal IDs when created
- the assignment binding consumed by assignments
- role definition IDs, purposes, grant scopes and role assignment IDs
- the resolver's identity rationale, governance and replacement intent
- the resolver's complete per-member decisions, unchanged (null remains unknown)
- `replacement_impact`, which marks the identity name and strategy as replacement triggers, marks role definition and grant scope as grant-address triggers, lists the fields to review before apply, and gives the identity name and the role-assignment addresses

`assignment_bindings` holds only the non-null `assignment_binding` records, so an assignment that verifiably needs no identity has no entry. Each binding contains `assignment_key`, `id`, `identity_id`, `principal_id` and `identity_strategy`, which is the shape the assignments module validates for `identity_bindings`. When the identity is not yet created, the identity and principal fields are unknown until apply.

The identity name is `irb-` followed by the first 20 hexadecimal characters of a SHA-1 over the assignment key, `name_basis` and strategy. A role assignment is addressed by the assignment key and a SHA-1 over its grant scope and lower-cased role definition ID. Its Azure name is a GUID formatted from a SHA-1 over the assignment key, grant scope and lower-cased role definition ID. Purpose is descriptive output and forms neither the address nor the name. Changing identity name basis, strategy, location or resource group is a replacement/migration event; changing role definition or grant scope changes the grant address and requires review of the old grant. The resolver sets `name_basis` to the assignment key, so renaming an assignment key also replaces its identity and moves its grants. The assignments module receives only `assignment_binding` records from this module, so identity attachment is acyclic and cannot use a broad caller fallback.

## Example

```hcl
module "identity_rbac" {
  source = "../../modules/identity-rbac"

  assignments = {
    deploy_storage = {
      intent = {
        scope = {
          type = "resource_group"
          id   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example-rg"
        }
      }
      resolved = {
        effective_effect = "DeployIfNotExists"
        list_fields = {
          role_definition_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/00000000-0000-0000-0000-000000000000"]
        }
        identity = {
          required            = true
          strategy            = "user_assigned"
          name_basis          = "storage-deploy"
          location            = "westeurope"
          resource_group_name = "identity-rg"
          rationale           = "The resolved deployment operation requires a managed identity."
        }
        required_roles = [{
          role_definition_id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/00000000-0000-0000-0000-000000000000"
          purpose            = "deploy resources"
          grant_scope        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example-rg"
        }]
      }
    }
  }
}
```

## Azure permissions

The role-grant state creates user-assigned identities and the role assignments those identities need. The principal that applies it needs two kinds of access:

| Resource | Operations | Scope |
| --- | --- | --- |
| User-assigned identities | `Microsoft.ManagedIdentity/userAssignedIdentities/read`, `write` and `delete` | The identity resource group |
| Role assignments | `Microsoft.Authorization/roleAssignments/read`, `write` and `delete` | Each grant scope the resolver names |

Managed Identity Contributor (`e40ec5ca-96e0-45a2-b4ff-59039f2c2b59`) on the identity resource group covers the first row. Role Based Access Control Administrator (`f58310d9-a9f6-439a-9e8d-f62e7b41a168`) at each grant scope covers the second. Prefer it with an ABAC condition over User Access Administrator or Owner. The condition limits which role definitions the principal may assign, here the resolver's candidate roles, and which principal types may receive them, here `ServicePrincipal`, which is the type this module sets. Microsoft documents this as constrained delegation of role assignment management. User Access Administrator grants `Microsoft.Authorization/*`, far more than this state needs.

This state needs no policy definition, policy assignment, exemption or remediation operation. Role contents were read from Microsoft Learn on 17 October 2026. The module already refuses roles outside the resolver's candidate list and refuses Contributor and Owner. The ABAC condition repeats that limit in Azure, so a later change to a pipeline cannot widen it. The condition itself, and a run with a least-privileged principal, are not exercised by this repository's tests.

## Separation of duties

This is the state that turns a policy decision into privilege. A Modify or DeployIfNotExists assignment needs roles for its identity, and applying them needs a role-assignment writer. Keep that writer separate from the principal that creates policy assignments. The assignments state only attaches an identity that already exists, through `assignment_bindings`, and cannot create one or grant a role. A pipeline that held both rights could give any identity any role, which is the escalation the split prevents. Review `replacement_impact` before applying, because replacing an identity changes its principal ID and every grant that depends on it. The module cannot enforce that two pipelines use two principals. The caller's pipeline configuration does that, for example with one federated workload identity credential per state.

## Compatibility and validation

This child module targets Terraform `>= 1.12.0` and AzureRM `>= 5.0.0, < 6.0.0`. Provider aliases, credentials and scope bindings remain caller-owned. `terraform validate` checks configuration and provider schema only; it does not execute variable validation or resource preconditions. Run `terraform test` from the module directory to exercise the identity, grant and guard cases against a mocked AzureRM provider. The suites create no Azure resources and the repository CI workflows run them. The compatibility workflow runs them on Terraform 1.12.0 with AzureRM 5.0.0 and on Terraform 1.15.9 with AzureRM 5.5.0.
