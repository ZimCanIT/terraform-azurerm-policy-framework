# Requirements and ownership governance

This provider-free boundary records the governance requirement, accountable owner, control keys and assignment keys that explain why a policy is deployed. It verifies references against inventories when callers supply them. It does not read policy source files, create Azure resources or infer compliance.

## Input

`requirements` is a keyed object. Each record may contain:

- `title`
- `owner`
- `rationale`
- `review_date`
- `control_keys`
- `assignment_keys`
- `status`

A requirement is traceable only when it has a non-blank owner, at least one control key and at least one assignment key. The module blocks records that do not meet those minimums.

```hcl
module "governance" {
  source = "./governance/requirements-and-ownership"

  requirements = {
    audit-coverage = {
      title           = "Record audit coverage"
      owner           = "platform-governance"
      rationale       = "Maintain an attributable control record."
      control_keys    = ["built_in_audit"]
      assignment_keys = ["audit-assignment"]
      review_date     = "2026-12-31"
      status          = "proposed"
    }
  }
}
```

## Reference inventories

`control_inventory` and `assignment_inventory` are optional `set(string)`
inputs. A null inventory means the caller has not verified that boundary; an
explicit empty set means the caller has verified that no internal keys exist.
Known references are matched exactly. A known missing key blocks the governance
guard and identifies the requirement, reference kind and offending key.

Callers may list references that belong to another governance system in
`external_control_keys` and `external_assignment_keys`. A reference explicitly
declared external is reported as external; it is never counted as an internally
verified control or assignment. An external key cannot also occur in its known
internal inventory.

Each traceability record exposes `control_references` and
`assignment_references` maps with a status for each key (`internal`,
`external`, `unknown`, or `missing`). The aggregate `traceability_status` is
`internal`, `external`, `mixed`, `unknown`, or `missing`. A `missing` status is
blocking and is not returned from a successful guarded module operation.
`traceable` is true only when the owner and
all references are verified internally. It is false for external references
and remains null when a required inventory is unknown. `traceability_complete`
is true when the owner is present and every reference is either internal or
explicitly external; it remains null while inventory status is unknown.

```hcl
module "governance" {
  source = "./governance/requirements-and-ownership"

  requirements = {
    audit-coverage = {
      owner           = "platform-governance"
      control_keys    = ["built_in_audit"]
      assignment_keys = ["audit-assignment"]
    }
  }

  control_inventory    = ["built_in_audit"]
  assignment_inventory = ["audit-assignment"]
}
```

## Outputs

- `requirements`: normalised governance records keyed by requirement key
- `traceability`: requirement-to-control-to-assignment records with per-key reference states, `traceability_status`, `traceable` and `traceability_complete`

The root module exposes these under its `governance` output. Requirement records are intent and ownership evidence; they are not proof of Azure deployment or compliance.

## Compatibility and validation

This module requires Terraform `>= 1.12.0` and no provider. Backend-disabled initialisation and `terraform validate` establish configuration validity only; variable validation and resource preconditions require `terraform test` or plan/console evidence.
