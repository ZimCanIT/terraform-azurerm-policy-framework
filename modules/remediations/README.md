# Remediations module

`remediations` is the explicit Azure Policy remediation boundary. It consumes canonical resolved assignment records and explicit operation requests. It never reads policy source files, resolves policy behaviour, broadens targeting, or infers remediation from an assignment effect.

## Inputs

- `resolved_assignments`: canonical records keyed by stable assignment key. Each consumed record must provide `assignment.id`, `intent.scope.type`, `intent.scope.id`, `resolved.policy_definition_id`, `resolved.remediation_eligibility`, `resolved.remediation_reason`, `resolved.members`, `resolved.member_reference_ids` and `resolved.required_roles`. Both member collections describe the complete initiative membership in the same order; `[]` means verified absence, while null means unknown. A blank `remediation_eligibility` is treated as an unknown decision, never as a declared state.
- `requests`: keyed operation requests. Each request requires `mode`, `assignment_key`, `scope_type`, `scope_id` and `policy_assignment_id`.
- `discovery_evidence`: optional caller-supplied, non-authoritative evidence keyed by request key. Each entry contains `targets`, whose records contain `resource_id` and `location`. The module never queries Azure.

A request may provide `member_reference_id`, `policy_definition_reference_id`, `resource_discovery_mode`, `location_filters`, `resource_count`, `parallel_deployments`, `failure_percentage`, `role_scope`, `approval_reference`, `evidence_status` and `expected_evidence_status`. If the resolved assignment targets an initiative, each remediation request must explicitly select one member and use the same ID for `policy_definition_reference_id`; both values must match the complete resolved member inventory. Eligibility, definition ID and role scope are checked against that selected member's decision record, so another member's eligibility or role cannot authorise this request. Direct policy targets use an empty member list and omit both member fields. Unknown membership blocks the operation.

Scope IDs must match the declared ARM scope shape. Limits follow the Azure Policy remediation contract: `resource_count` is 1 through 50000, `parallel_deployments` is 1 through 30, and `failure_percentage` is between 0 and 1 inclusive. `location_filters` must be a list of non-blank strings; an explicit empty list matches no targets. `evidence_status` and `expected_evidence_status` must be non-blank strict strings when supplied. Management-group requests reject `resource_discovery_mode` because that control is not accepted by that resource branch.

## Safety contract

`execute` creates a resource only when the request has verified assignment context, matching assignment ID, a non-blank resolved `policy_definition_id`, a request scope that matches the resolved assignment scope exactly or, for `resource` and `resource_group` requests, is contained within it, matching member and policy-definition references when resolved targeting provides them, a known `eligible` remediation status, authorised required-role grant scope, explicit approval reference, explicit role scope and a resource limit. Initiative-member records require both the resolved member reference and the matching AzureRM `policy_definition_reference_id`. A policy-definition reference must match the resolved initiative member reference; it is not compared with the top-level policy definition ID. Unknown, absent, malformed, blank or inconsistent context is blocked. Blocked reasons include the producer's `remediation_reason` so that every ineligibility verdict is attributable. Disabled requests are skipped. Discovery requests are non-mutating but are blocked by the same targeting, eligibility and bounded-control checks. When caller-supplied `discovery_evidence` exists, outputs report its filtered count and targets; absent or malformed evidence remains unknown and cannot be treated as an empty result. This module does not query Azure or enumerate targets.

Changing a managed request from `execute` to a valid `discovery` request, `disabled`, or removing it from the request set removes the execution resource from the desired state. Terraform may therefore plan resource destruction, so these explicit transitions require review. An execute or discovery request that fails its contract is blocked by a resource precondition before an apply can change existing operations. Terraform state is not operational evidence; retain approval, cleanup and re-execution records in the caller's workflow.

`role_scope` is explicit and must match a resolved required-role grant scope. This module creates no identities or role grants and has no broad-role default. Resource names are the caller's stable operation keys, so changing execution mode removes the corresponding AzureRM resource from the desired state and must be reviewed as a possible cleanup or replacement operation. Azure Policy remediation tasks are operationally finite and Azure may delete inactive tasks after 60 days; external approval and execution records must therefore be retained outside Terraform state.

Azure rejects an update to a remediation while its tasks are active with `InvalidUpdateRemediationRequest`. Sequence resource changes that would update a running remediation, such as changing its filters or resource limits, after the active task set completes.

## Example

```hcl
module "remediations" {
  source = "./modules/remediations"

  resolved_assignments = {
    assignment_example = {
      assignment = {
        id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/example"
      }
      intent = {
        scope = {
          type = "subscription"
          id   = "/subscriptions/00000000-0000-0000-0000-000000000000"
        }
      }
      resolved = {
        policy_definition_id    = "/providers/Microsoft.Authorization/policyDefinitions/example"
        member_reference_ids    = []
        members                 = []
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

The runnable discovery fixture is in the [explicit operations example](examples/explicit-operations/README.md).

## Outputs

| Output | Contents |
| --- | --- |
| `requested_operations` | Normalised requests with status, blocking reasons and the eligibility, reason, definition ID, full member inventory, and required-role decision used for the selected direct target or initiative member. |
| `discovered_operations` | Bounded, non-mutating discovery intent; Azure results remain unknown. |
| `skipped_operations` | Disabled requests. |
| `blocked_operations` | Requests blocked by unknown, malformed or inconsistent context and controls, including the producer's remediation reason. |
| `created_operations` | Explicit remediation resources created by this module, including assignment/member context, the producer remediation reason and Azure IDs. |

Operation records convey request intent and Azure resource identity only. Terraform state is not execution evidence: compliance results and execution evidence remain external operational records.

## Compatibility and validation

The module declares Terraform `>= 1.12.0` and AzureRM `>= 5.0.0, < 6.0.0`. Authorised regression evidence (implementation-run, self-reported) passes on Terraform 1.15.9 with AzureRM 5.5.0, on the Terraform 1.12.0 minimum, and on a pinned AzureRM 5.0.0 cell; provider-backed plans cover the four scope resource families; exact commands and dates are recorded in the delivery handoff. Provider configuration stays with the caller; the module declares its `required_providers` constraint only.

```powershell
terraform fmt -check -recursive modules/remediations
terraform -chdir=modules/remediations init -backend=false -input=false
terraform -chdir=modules/remediations validate -no-color
```

Module and repository test suites exercise request validation and provider payloads; a passing `terraform validate` does not execute those checks. Live remediation creation, discovery and cleanup require the authorised lifecycle run and are reported separately from module tests.
