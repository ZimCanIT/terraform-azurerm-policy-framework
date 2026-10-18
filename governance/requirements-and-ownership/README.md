# Requirements and ownership governance

This provider-free boundary records the governance requirement, accountable owner, control keys and assignment keys that explain why a policy is deployed. It verifies references against inventories when callers supply them. It does not read policy source files, create Azure resources or infer compliance.

The check is for existence only. It confirms that a named key appears in an inventory. It does not confirm that the named assignment applies the named control. A requirement record is intent and ownership evidence, not proof of Azure deployment or compliance.

The root composition calls this module and exposes its outputs under the root `governance` output. The root passes a control inventory built from the content definition keys, initiative keys and initiative member reference IDs, an assignment inventory built from the assignment keys, and the external key sets from its own variables.

## Inputs

| Input | Type | Default | Behaviour |
| --- | --- | --- | --- |
| `requirements` | `any` | `{}` | Requirement records keyed by stable requirement key. |
| `control_inventory` | `set(string)` | `null` | Known internal control keys. |
| `assignment_inventory` | `set(string)` | `null` | Known internal assignment keys. |
| `external_control_keys` | `set(string)` | `[]` | Control keys declared as belonging to another governance system. |
| `external_assignment_keys` | `set(string)` | `[]` | Assignment keys declared as belonging to another governance system. |

Each `requirements` record is an object that may contain:

- `title`, `rationale` and `review_date`: optional and carried verbatim. Each is null when omitted. `review_date` is not parsed or compared with the current date.
- `owner`: the accountable owner. It must be non-blank for the guard to pass.
- `control_keys` and `assignment_keys`: lists of non-blank strings. Both must be present, must not be null and must not repeat a key within the list. Each needs at least one entry for the guard to pass.
- `status`: free text that defaults to `proposed` and is not validated.

A field outside this list is ignored and does not appear in the outputs.

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

## Validation

Variable validation rejects:

- a `requirements` value that is null or not a keyed object
- a blank requirement key, a record that is not an object, or a record whose `control_keys` or `assignment_keys` is missing, null or not a list
- a reference that is not a non-blank string, or a key repeated within one list
- an inventory or external key set that contains a blank key
- a key that occurs in an inventory and in the matching external key set

One blocking `terraform_data.contract_guard` has no input, so it never plans a change of its own. It fails when a requirement lacks a non-blank owner, a control key or an assignment key, and when a reference has the status `missing`. The missing-reference message names the requirement, the reference kind and the offending key.

## Reference inventories

`control_inventory` and `assignment_inventory` are optional. A null inventory means the caller has not verified that boundary. An explicit empty set means the caller has verified that no internal keys exist. Known references are matched exactly.

Callers list references that belong to another governance system in `external_control_keys` and `external_assignment_keys`. An external reference is reported as external and is never counted as an internally verified control or assignment.

Each reference gets one status:

| Status | When |
| --- | --- |
| `external` | The key is in the matching external key set. This is checked first. |
| `unknown` | The key is not external and the matching inventory is null. |
| `internal` | The key is not external and the known inventory contains it. |
| `missing` | The key is not external and the known inventory does not contain it. This blocks the guard. |

Each traceability record carries `control_references` and `assignment_references`, maps from reference key to an object with one `status` attribute, and three aggregates:

| Aggregate | Value |
| --- | --- |
| `traceability_status` | `unknown` when any reference is unknown. Otherwise `missing` when any is missing, `mixed` when both internal and external references occur, `external` when only external references occur and `internal` otherwise. |
| `traceable` | Null when any reference is unknown. Otherwise true only when the owner is non-blank and every reference is internal. It is false when any reference is external. |
| `traceability_complete` | Null when any reference is unknown. Otherwise true only when the owner is non-blank, at least one reference exists and every reference is internal or external. |

Both outputs depend on the guard and a `missing` reference blocks it, so no successful run returns a `missing` status.

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

| Output | Contents |
| --- | --- |
| `requirements` | Normalised records keyed by requirement key. Each holds `requirement_key`, `title`, `owner`, `rationale`, `review_date`, `control_keys`, `assignment_keys` and `status`. |
| `traceability` | One record per requirement with `requirement_key`, `owner`, `control_keys`, `assignment_keys`, `review_date`, `status`, `control_references`, `assignment_references`, `traceability_status`, `traceable` and `traceability_complete`. |

## Compatibility and validation

The module uses no provider and declares no Terraform version requirement of its own. The root composition requires Terraform `>= 1.12.0`, and the repository's compatibility workflow runs this module's suite on Terraform 1.12.0 and 1.15.9.

```powershell
terraform fmt -check -recursive governance/requirements-and-ownership
terraform -chdir=governance/requirements-and-ownership init -backend=false -input=false
terraform -chdir=governance/requirements-and-ownership validate -no-color
terraform -chdir=governance/requirements-and-ownership test
```

Backend-disabled initialisation and `terraform validate` establish configuration validity only. Variable validation and guard preconditions are evaluated by `terraform test`, plan or console. The suite covers verified internal references, explicit external references, independent grouping per requirement, unknown inventories, a known missing reference, duplicate references and null or scalar `requirements`. The repository CI workflow runs it.
