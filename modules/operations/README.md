# Operations module

`operations` is the operations state of the framework. It owns two kinds of Azure Policy resource that act on an assignment that already exists: explicit remediations and governed exemptions. Both read one shared `resolved_assignments` input, the resolver's records for the assignments they act on. The module never reads policy source files, resolves policy behaviour, creates assignments, identities or role grants, broadens targeting, or infers an operation from an assignment effect.

Remediations and exemptions share a module because they share an owner, an approval path and a lifecycle: both are deliberate, time-bound operations on assignments, applied after the assignment state. They stay independent inside the module. A request in one family never changes the other, and each family has its own contract guard.

## Inputs

| Input | Used by | Behaviour |
| --- | --- | --- |
| `resolved_assignments` | both | Resolved assignment records keyed by stable assignment key. |
| `requests` | remediations | Keyed remediation requests. |
| `discovery_evidence` | remediations | Optional caller-supplied discovery results keyed by request key. The module never queries Azure. |
| `exemptions` | exemptions | Keyed exemption requests. |
| `evaluation_time` | exemptions | Optional RFC3339 instant used to classify expiry. When omitted, Terraform evaluation time is used, so the status outputs change on every plan. |

### Resolved assignments

Each record provides `assignment.id`, `intent.scope.type` and `intent.scope.id`. Remediation requests also read `resolved.policy_definition_id`, `resolved.remediation_eligibility`, `resolved.remediation_reason`, `resolved.required_roles` and, for initiative targets, per-member decisions. Both families read `resolved.members` and `resolved.member_reference_ids`, which describe the complete initiative membership in the same order. `[]` means verified absence and null means unknown. The module rejects a record whose two member collections disagree, whichever family reads it. A blank `remediation_eligibility` is an unknown decision, never a declared state.

```hcl
resolved_assignments = {
  example = {
    assignment = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/example" }
    intent     = { scope = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000000" } }
    resolved   = { members = [], member_reference_ids = [] }
  }
}
```

Supported scope types are `management_group`, `subscription`, `resource_group` and `resource`. One scope grammar serves every check in the module. An operation scope must equal the resolved assignment scope or sit inside it: a resource group or resource inside a subscription, or a resource inside a resource group. A management-group assignment scope has no comparable lineage and needs an exact match.

## Remediations

`requests` holds keyed operation requests. Each request requires `mode`, `assignment_key`, `scope_type`, `scope_id` and `policy_assignment_id`. A request may also provide `member_reference_id`, `policy_definition_reference_id`, `resource_discovery_mode`, `location_filters`, `resource_count`, `parallel_deployments`, `failure_percentage`, `role_scope`, `approval_reference`, `evidence_status` and `expected_evidence_status`.

If the resolved assignment targets an initiative, each request must select one member and use the same ID for `policy_definition_reference_id`; both must match the complete resolved member inventory. Eligibility, definition ID and role scope are checked against that member's decision record, so another member's eligibility or role cannot authorise the request. Direct policy targets use an empty member list and omit both member fields. Unknown membership blocks the operation.

`discovery_evidence` entries contain `targets`, whose records contain `resource_id` and `location`. Limits follow the Azure Policy remediation contract: `resource_count` is 1 through 50000, `parallel_deployments` is 1 through 30 and `failure_percentage` is between 0 and 1 inclusive. `location_filters` is a list of non-blank strings, and an explicit empty list matches no targets. Management-group requests reject `resource_discovery_mode`, because that resource branch does not accept it.

### Remediation safety contract

`execute` creates a resource only when the request has all of the following:

- verified assignment context and a `policy_assignment_id` that equals the resolved assignment ID;
- a non-blank resolved `policy_definition_id`;
- a scope that matches the resolved assignment scope or sits inside it;
- matching member and policy-definition references when the target is an initiative;
- a known `eligible` remediation status;
- an explicit `role_scope` that equals a resolved required-role grant scope;
- an explicit approval reference and a resource limit.

A policy-definition reference must match the resolved initiative member reference. It is not compared with the top-level policy definition ID. Unknown, absent, malformed, blank or inconsistent context is blocked, and blocked reasons include the producer's `remediation_reason` so every ineligibility verdict is attributable. Disabled requests are skipped. Discovery requests are non-mutating but face the same targeting, eligibility and bounded-control checks. When `discovery_evidence` exists, outputs report its filtered count and targets. Absent or malformed evidence stays unknown and is never treated as an empty result.

Changing a managed request from `execute` to a valid `discovery` request or to `disabled`, or removing it, removes the remediation resource from the desired state, and Terraform may plan its destruction. Review these transitions. An execute or discovery request that fails its contract is blocked by a resource precondition before an apply can change existing operations. Resource names are the stable request keys supplied by the caller. Azure Policy remediation tasks are finite and Azure may delete inactive tasks after 60 days, so retain approval, cleanup and re-execution records outside Terraform state.

Azure rejects an update to a remediation while its tasks are active with `InvalidUpdateRemediationRequest`. Sequence changes to filters or resource limits after the active task set completes.

## Exemptions

`exemptions` holds governed exemption requests. Each request provides `request_mode`, `assignment_id`, `scope`, `owner`, `reason`, `approval_reference` or `ticket_reference`, `category`, `compensating_control` and `expires_on`. `assignment_id` must equal the `assignment.id` of a record in `resolved_assignments`, and the exemption `scope` must equal or sit inside that record scope. The module does not accept a syntactically valid but unrelated assignment ID.

```hcl
exemptions = {
  example = {
    request_mode  = "create"
    assignment_id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/example"
    scope = {
      type = "subscription"
      id   = "/subscriptions/00000000-0000-0000-0000-000000000000"
    }
    owner                = "platform-team"
    reason               = "Temporary exception during migration"
    approval_reference   = "APR-001"
    category             = "Mitigated"
    compensating_control = "Manual weekly review"
    expires_on           = "2027-01-31T00:00:00Z"
  }
}
```

Supported categories are `Waiver` and `Mitigated`. `policy_definition_reference_ids` is null for whole-assignment targeting, empty for verified absence, or a unique list of members of the referenced assignment. Unsupported selectors are rejected, never ignored.

`create`, `update` and `renew` keep the stable resource address and create or update the Azure exemption only when `expires_on` is in the future at the selected evaluation time. An elapsed expiry is classified as expired and does not silently remove an existing Azure exemption from desired state. `expire`, `reject`, `blocked` and `disabled` remove a managed resource from desired state, so Terraform can plan deletion and policy re-enforcement. Azure may retain an expired exemption record, so use `expire` for explicit removal. `active` means approved, unexpired request intent. `azure_status` separately reports whether this module returned a created resource ID.

### Exemption contract

The module validates request shape, allowed keys, request mode, strict governance metadata, expiry, assignment membership, member targeting and scope containment before it creates a resource. The governance strings (`owner`, `reason`, `category`, `compensating_control`, `approval_reference`, `ticket_reference`, `display_name`, `description` and `expires_on`) and the `policy_definition_reference_ids` elements must be non-blank, single-line and free of surrounding whitespace when supplied. A value that needs JSON escaping, such as an inner newline, tab or quote, is rejected. Absent optional strings stay null and keep the documented resource fallback, while a supplied blank string is rejected, so null and empty remain distinct. Blocked, expired and rejected requests remain in the outputs without creating resources. Unknown assignment membership, member lists or containment never broadens targeting.

## Outputs

| Output | Contents |
| --- | --- |
| `requested_operations` | Normalised remediation requests with status, blocking reasons and the eligibility, reason, definition ID, full member inventory and required-role decision for the selected target. |
| `discovered_operations` | Bounded, non-mutating discovery intent. Azure results remain unknown. |
| `skipped_operations` | Disabled remediation requests. |
| `blocked_operations` | Requests blocked by unknown, malformed or inconsistent context or controls, including the producer reason. |
| `created_operations` | Remediation resources created by this module, with assignment and member context and Azure IDs. |
| `requested_exemptions` | Normalised exemption requests keyed by request key. |
| `approved_exemptions` | Requests selected for creation or renewal with approval or ticket evidence. |
| `active_exemptions` | Approved, future-dated create, update or renew requests. This is intent, not proof of an active Azure exemption. |
| `expired_exemptions` | Requests explicitly expired, or whose expiry has elapsed at evaluation time. |
| `blocked_exemptions` | Requests explicitly blocked or disabled. |
| `rejected_exemptions` | Requests explicitly rejected. |
| `status_contract` | The requested, approved, active, expired, blocked and rejected views together. |
| `created_exemption_ids` | Azure exemption IDs created by this module, keyed by request key. |

Operation records convey request intent and Azure resource identity only. Terraform state is not execution evidence, so keep compliance results and approval records in your own workflow.

## Example

A runnable synthetic consumer is in [`examples/explicit-operations`](examples/explicit-operations/README.md). It feeds one resolved assignment record to a bounded discovery request and a governed exemption. It uses non-tenant IDs and creates nothing by itself.

```hcl
module "operations" {
  source = "./modules/operations"

  resolved_assignments = {
    assignment_example = {
      assignment = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/example" }
      intent     = { scope = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000000" } }
      resolved = {
        policy_definition_id    = "/providers/Microsoft.Authorization/policyDefinitions/example"
        members                 = []
        member_reference_ids    = []
        remediation_eligibility = "eligible"
        remediation_reason      = "The resolved direct policy definition is eligible for remediation."
        required_roles          = [{ grant_scope = "/subscriptions/00000000-0000-0000-0000-000000000000" }]
      }
    }
  }

  requests = {
    remediate_example = {
      mode                 = "execute"
      assignment_key       = "assignment_example"
      scope_type           = "subscription"
      scope_id             = "/subscriptions/00000000-0000-0000-0000-000000000000"
      policy_assignment_id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/example"
      role_scope           = "/subscriptions/00000000-0000-0000-0000-000000000000"
      approval_reference   = "CAB-12345"
      resource_count       = 50
    }
  }
}
```

## Compatibility and validation

The module declares Terraform `>= 1.12.0` and AzureRM `>= 5.0.0, < 6.0.0`. Provider configuration stays with the caller. The module declares `required_providers` only.

```powershell
terraform fmt -check -recursive modules/operations
terraform -chdir=modules/operations init -backend=false -input=false
terraform -chdir=modules/operations validate -no-color
```

`terraform validate` checks configuration and provider schema only. It does not run variable validation or preconditions. The suites under `tests/` exercise request validation, lifecycle transitions and provider payloads for all four scope families with a mock provider, and CI runs them on the declared minimum and on a current Terraform release. Live remediation and exemption behaviour in Azure is separate evidence.
