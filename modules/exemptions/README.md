# Exemptions module

`exemptions` is the governed exemption boundary for the framework. It consumes resolved assignment references, typed scope data and explicit exemption requests, then creates Azure Policy exemptions only for requests that explicitly select creation or renewal.

The module does not read source files, resolve assignments or broaden permissions by default. It preserves owner, reason, approval or ticket reference, category, compensating control and expiry metadata in both its validation contract and its outputs.

## Inputs

| Input | Type | Behaviour |
| --- | --- | --- |
| `exemptions` | `any` | Keyed map of governed exemption requests. Each request must provide `request_mode`, `assignment_id`, `scope`, `owner`, `reason`, `approval_reference` or `ticket_reference`, `category`, `compensating_control` and `expires_on`. |

Each request uses this shape. `assignments` must contain the resolved assignment record whose `assignment.id` equals `assignment_id`; the module does not accept a syntactically valid but unrelated ID.

```hcl
assignments = {
  example = {
    assignment = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/example" }
    intent = { scope = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000000" } }
    resolved = { members = [], member_reference_ids = [] }
  }
}
```

Each request uses this shape:

```hcl
exemptions = {
  example = {
    request_mode           = "create"
    assignment_id          = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/example"
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

Supported scope types are `management_group`, `subscription`, `resource_group` and `resource`. Assignment scopes must contain the exemption scope. Resource-scoped assignment IDs are supported. `policy_definition_reference_ids` is null for whole-assignment targeting, empty for verified absence, or a unique list of assignment members. Unsupported selectors are rejected, never ignored. Supported categories are `Waiver` and `Mitigated`.

`create`, `update` and `renew` retain the stable resource address and create or update the Azure exemption only when `expires_on` is in the future at the selected evaluation time. An elapsed expiry date is classified as expired; it does not silently remove an existing Azure exemption from desired state. `expire`, `reject`, `blocked` and `disabled` remove a managed resource from desired state, so Terraform can plan deletion and policy re-enforcement. Azure may retain an expired exemption record; use `expire` for explicit removal. Expiry is evaluated with `evaluation_time` or Terraform evaluation time. `active` means approved, unexpired request intent; `azure_status` separately reports whether this module returned a created resource ID.

## Outputs

| Output | Contents |
| --- | --- |
| `requested_exemptions` | Normalised request records keyed by stable request key. |
| `approved_exemptions` | Requests selected for creation or renewal with approval or ticket evidence. |
| `active_exemptions` | Approved, future-dated create, update or renewal requests; this is intent, not proof of an active Azure exemption. |
| `expired_exemptions` | Requests explicitly expired or whose expiry date has elapsed at evaluation time. |
| `blocked_exemptions` | Requests explicitly blocked or disabled, with lifecycle status. |
| `rejected_exemptions` | Requests explicitly rejected, with lifecycle status. |
| `status_contract` | Complete requested, approved, active, expired, blocked and rejected views. |
| `created_exemption_ids` | Azure Policy exemption IDs created by the module, keyed by request key. |

## Contract

The module validates request shape, allowed keys, request mode, strict governance metadata, expiry, assignment membership, member targeting and scope containment before resource creation. Governance strings (`owner`, `reason`, `category`, `compensating_control`, `approval_reference`, `ticket_reference`, `display_name`, `description` and `expires_on`) and `policy_definition_reference_ids` elements must be non-blank, single-line and free of surrounding whitespace when supplied; a value that needs JSON escaping, such as an inner newline, tab or quote, is rejected. Absent optional strings stay null and keep the documented resource fallback, while a supplied blank string is rejected, so null and empty remain distinct. Explicit create, update and renewal use the provider-backed exemption resources for the declared scope type. Blocked, expired and rejected requests remain in outputs without creating exemption resources. Unknown assignment membership, member lists or containment never broadens targeting.

The module is a child boundary, so provider configuration stays with the caller. The declared compatibility is Terraform `>= 1.12.0` and AzureRM `>= 5.0.0, < 6.0.0`. Authorised regression evidence (implementation-run, self-reported) passes on Terraform 1.15.9 with AzureRM 5.5.0, on the Terraform 1.12.0 minimum, and on a pinned AzureRM 5.0.0 cell; provider-backed plans and live lifecycle evidence are recorded in the delivery handoff.

## Example

A runnable synthetic consumer is provided in [`examples/basic`](examples/basic). It uses non-tenant IDs and demonstrates explicit request intent, resolved assignment membership and time-bound metadata. It is a configuration example only and does not grant permissions or apply Azure resources by itself.

## Validation

Backend-disabled initialisation and `terraform validate` establish configuration and provider-schema validity only. They do not execute variable validation, preconditions or Azure lifecycle behaviour. Module-local assertions live in `modules/exemptions/tests` (including the lifecycle and all-scope cases formerly held by a contract root); recorded runs of either suite are implementation-run evidence unless the project owner verifies them independently.

```powershell
$env:NO_PROXY = '127.0.0.1,localhost,::1'
terraform fmt -check -recursive modules/exemptions
terraform -chdir=modules/exemptions init -backend=false -input=false
terraform -chdir=modules/exemptions validate -no-color
git diff --check
```

## Public contract example

```hcl
module "exemptions" {
  source = "./modules/exemptions"

  exemptions = {
    example = {
      request_mode           = "create"
      assignment_id          = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/example"
      scope = {
        type = "subscription"
        id   = "/subscriptions/00000000-0000-0000-0000-000000000000"
      }
      owner                = "platform-team"
      reason               = "Temporary exception during migration"
      ticket_reference     = "CHG-1234"
      category             = "Mitigated"
      compensating_control = "Manual weekly review"
      expires_on           = "2027-01-31T00:00:00Z"
    }
  }
}
```
