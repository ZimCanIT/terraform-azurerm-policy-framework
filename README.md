# Azure Policy Framework for Terraform

A composite Terraform module for Azure Policy governance. It turns a policy catalogue (JSON files or native HCL) into custom definitions and initiatives, typed assignments, user-assigned identities with least-privilege role grants, explicit remediation requests and governed exemptions, and records requirement ownership with traceability to controls and assignments.

The architecture follows [Architecting Azure Policy Governance at Enterprise Scale: The Framework, Part 1](https://zimcanit.com/articles/azure-policy-at-scale-part-1/).

## Status

This project is pre-release and is not ready to publish. It is not published to the Terraform Registry, no release is tagged and the Registry address `ZimCanIT/policy-framework/azurerm` does not resolve. Until a first release is tagged, module names, inputs and outputs can change without a migration path. Review every plan before you apply it.

## Usage

Pin a commit of this public repository as a Git source, or point `source` at a local checkout (for example `"../terraform-azurerm-policy-framework"`).

```hcl
provider "azurerm" {
  features {}
}

module "policy" {
  source = "git::https://github.com/ZimCanIT/terraform-azurerm-policy-framework.git?ref=<commit-sha>"

  catalogue = {
    native_definitions = {
      require_cost_centre_tag = {
        source_type  = "custom"
        display_name = "Require cost centre tag"
        version      = "1.0.0"
        mode         = "Indexed"

        policy_rule = {
          if   = { field = "tags['costCentre']", exists = "false" }
          then = { effect = "audit" }
        }
      }
    }
  }

  assignments = {
    cost-centre-tag-audit = {
      target     = { reference_id = "require_cost_centre_tag", definition_key = "require_cost_centre_tag" }
      scope      = { type = "subscription", id = "/subscriptions/00000000-0000-0000-0000-000000000000" }
      effect     = "Audit"
      governance = { owner = "platform-governance" }
    }
  }

  requirements = {
    cost-centre-tagging = {
      owner           = "platform-governance"
      control_keys    = ["require_cost_centre_tag"]
      assignment_keys = ["cost-centre-tag-audit"]
      status          = "approved"
    }
  }
}
```

Replace `<commit-sha>` and the all-zero subscription ID. Use the subscription your `azurerm` provider targets, because a custom definition without `management_group_id` is created there. To read definitions and initiatives from flat JSON directories instead of inline HCL, set `custom_definition_directory`, `built_in_reference_directory` and `initiative_directory` in `catalogue`; the file formats are in [modules/catalogue/README.md](modules/catalogue/README.md).

- You own the provider configuration, backend and state. The module declares no provider configuration, and its only provider declaration is `required_providers`. It prescribes no management-group hierarchy and uses no data sources: built-in definitions are referenced by ID and never looked up.
- Scope IDs come from your inputs. Keep them out of portable catalogue files; an optional `management_group_id` on a definition or initiative entry is passed through unchanged.
- `terraform validate` does not run input validation rules or preconditions, so contract errors appear at `terraform plan`. The plan also lists `terraform_data` guard resources, which hold no policy content and exist to run those checks.

## What it provides

| Layer | Module | Responsibility |
| --- | --- | --- |
| Control catalogue | `modules/catalogue` | The only module that reads files. Adapts flat JSON directories and native HCL into canonical `definitions` and `initiatives` entries. Provider-free. |
| Content | `modules/content` | Custom definitions, built-in references by stable Azure ID and initiatives with groups, parameters and `major.minor.*` member version constraints. |
| Behaviour | `modules/behaviour-resolution` | Effective effect, version, identity requirement and remediation eligibility per assignment. Provider-free. |
| Role grants | `modules/identity-rbac` | User-assigned identities and role grants limited to the roles each definition declares. The only module that creates identities or role assignments. |
| Assignment topology | `modules/assignments` | Management-group, subscription, resource-group and resource assignments with parameters, enforcement mode, exclusions, selectors, overrides and non-compliance messages. It attaches the identity that identity-rbac created and creates none itself. |
| Operations | `modules/operations` | Explicit remediation requests and governed exemptions that act on assignments that already exist. Exemptions carry owner, reason, approval and expiry. |
| Governance | `governance/requirements-and-ownership` | Requirement ownership and traceability to controls and assignments. Provider-free. |

Each child module can be called on its own and validates its own inputs; its README documents the contract. Azure names are deterministic and derive from your stable keys. Definitions and initiatives use their key unless you set `name`, remediations and exemptions use their request key, assignments combine the key, scope type and target reference (with a hash suffix when long or colliding), and identities and role assignments are named from a hash. Nothing random is generated.

## Separating duties across states

Each module that creates Azure resources is also a state boundary, so different principals or pipelines can hold different rights. Apply the states in this order and destroy them in reverse:

| Order | State | Module | Creates | Publishes |
| --- | --- | --- | --- | --- |
| 1 | Content | `modules/content` | Custom policy definitions and initiatives | `definitions` and `initiatives`, the canonical envelopes with Azure IDs |
| 2 | Role grants | `modules/identity-rbac` | User-assigned identities and role assignments | `assignment_bindings`, the identity each assignment attaches, keyed by assignment key |
| 3 | Assignment | `modules/assignments` | Policy assignments | `resolved_assignments`, the resolver records with the created assignment ID and name |
| 4 | Operations | `modules/operations` | Remediations and exemptions | Nothing |

The catalogue, behaviour-resolution and governance modules create no Azure resources. Behaviour resolution is a pure function of its inputs, so each state that needs a decision recomputes it from the content hand-off and the same assignment intent. An omitted `policy_assignment_id` on a remediation request is taken from the assignment that `assignment_key` names, so no state copies an assignment ID by hand.

The modules never read state. A reference root passes each hand-off to the next module as a plain input, read with `terraform_remote_state`, and a pipeline can supply the same values another way.

Each module README lists the Azure permissions its state needs and the duties to keep apart: [content](modules/content/README.md#azure-permissions), [identity-rbac](modules/identity-rbac/README.md#azure-permissions), [assignments](modules/assignments/README.md#azure-permissions) and [operations](modules/operations/README.md#azure-permissions). Only `identity-rbac` declares identity and role-assignment resources, so an assignment state cannot create an identity or grant a role. The repository gate fails if the root module, or a module's `.tf` files outside its `examples` and `tests` folders, declares an AzureRM resource type that the module does not own. It does not scan the top-level `examples`, `tests` or `governance` folders, so review those by hand.

[`examples/state-separated-lifecycle`](examples/state-separated-lifecycle/README.md) applies the framework this way with local state. It runs under one operator, so it shows the boundaries and hand-offs without separating duties. Giving each state its own principal is outside this repository.

The composite root described in this README runs every module in one state with one principal. It is a single-state convenience and does not separate duties.

## Inputs

All inputs are optional. They default to empty, except `evaluation_time`, which defaults to null.

| Name | Type | Purpose |
| --- | --- | --- |
| `catalogue` | `object` | Catalogue sources: `initiative_directory`, `custom_definition_directory` and `built_in_reference_directory` (flat JSON directories), `native_definitions` and `native_initiatives` (HCL maps keyed by stable catalogue key) and `allow_empty_sources` (default `false`). |
| `definitions`, `initiatives` | `any` | Canonical entries merged over the catalogue output. A matching key replaces the catalogue entry. |
| `assignments` | `any` | Assignment intent keyed by stable assignment key (see below). |
| `remediation_requests` | `any` | Explicit remediation requests keyed by operation key. `policy_assignment_id` may be omitted: the operations module then takes the Azure ID of the assignment that `assignment_key` names, which is unknown until apply for an assignment created here. A supplied value must equal that ID. |
| `discovery_evidence` | `any` | Caller-supplied discovery results keyed by operation key. The module never queries Azure. |
| `exemptions` | `any` | Exemption requests keyed by request key, each with `assignment_id` (the Azure ID of an assignment resolved in this configuration), `scope`, owner, category, reason, approval or ticket reference, compensating control and expiry. |
| `evaluation_time` | `string` | RFC3339 instant used to classify exemption expiry. When unset the current time is used and the exemption status outputs change on every plan, so fix it per run. |
| `requirements` | `map(object)` | Governance requirements keyed by requirement key: `title`, `owner`, `rationale`, `review_date`, `control_keys`, `assignment_keys` and `status` (default `proposed`). |
| `external_control_keys`, `external_assignment_keys` | `set(string)` | Governance references declared as managed outside this configuration. |

The policy payload inputs are `any` because each key carries its own parameter and rule shapes. The child modules validate each entry and report the rule that failed.

Each `assignments` entry needs a `target` and a `scope`:

- `target` is a `reference_id` plus exactly one of `definition_key`, `initiative_key` or `policy_definition_id`. For an initiative target, `reference_id` must name one of its members.
- `scope` is a `type` (`management_group`, `subscription`, `resource_group` or `resource`) and an Azure scope `id` in the matching resource ID form.

The optional fields are `effect`, `parameters`, `exclusions`, `selectors`, `overrides`, `enforcement_mode`, `non_compliance_messages`, `rollout`, `governance`, `identity`, `role_grant_scopes`, `version_constraint`, `pinned_version` and `version_binding`. Three rules are enforced at plan time:

- An effective effect of `Modify` or `DeployIfNotExists` needs `identity` with a `location` and `resource_group_name`. The module then creates a user-assigned identity and grants it only the roles the definition declares, at the assignment scope unless `role_grant_scopes` sets a scope for a role. Contributor and Owner are rejected.
- AzureRM assignments cannot carry a definition version. A direct target whose definition declares a version pin or constraint needs `version_binding = "unversioned"`. That setting is valid only for a direct target with no assignment-level `pinned_version` or `version_constraint`, so it is rejected on initiative targets. Initiative members accept `major.minor.*` version constraints only; exact pins are rejected.
- A built-in reference assigned directly must set `role_definition_ids`, using `[]` when it needs none. An omitted list means unknown and is rejected.

The full contracts are in [modules/behaviour-resolution/README.md](modules/behaviour-resolution/README.md), [modules/assignments/README.md](modules/assignments/README.md) and [modules/operations/README.md](modules/operations/README.md).

## Outputs

| Output | Contents |
| --- | --- |
| `catalogue` | The adapter result: `definitions`, `initiatives` and `source_summary` (provenance per entry). |
| `definitions` | Canonical definitions keyed by catalogue key, with Azure IDs. |
| `initiatives` | Canonical initiatives keyed by catalogue key, with Azure IDs and resolved members. |
| `resolved_assignments` | One record per assignment key with `intent`, `resolved` and `assignment` (created ID and name). |
| `lifecycle_resource_ids` | Azure IDs by kind: `assignments`, `identities`, `principals`, `role_assignments`, `remediations` and `exemptions`. |
| `governance` | `requirements` and `traceability` records. |
| `remediations` | Requested operations keyed by operation key, with mode, status, eligibility and blocked reasons. |
| `exemptions` | Lifecycle views `requested`, `approved`, `active`, `expired`, `blocked` and `rejected`, each keyed by request key. |
| `plan_summary` | Scope counts, management-group inheritance, exclusion and selector totals and rollout stages. |
| `replacement_review` | Assignment and identity attributes whose change replaces an Azure resource. |

## Examples

| Example | Deploys |
| --- | --- |
| [`examples/minimal-audit-assignment`](examples/minimal-audit-assignment/README.md) | One built-in Audit assignment at subscription scope. No identity, role grant or remediation. |
| [`examples/complete-policy-lifecycle`](examples/complete-policy-lifecycle/README.md) | A native HCL catalogue with a custom Modify definition and an initiative, a resource-group assignment with a user-assigned identity and Tag Contributor grant, an explicit remediation request and an optional governed exemption, against a resource group and storage account that the example creates. It uses one state and one principal. |
| [`examples/state-separated-lifecycle`](examples/state-separated-lifecycle/README.md) | The same lifecycle as five roots, each with its own local state: target, content, identity-rbac, assignments and operations. Each root reads only what earlier roots published, through `terraform_remote_state`. |

Applying any of these examples creates real Azure resources. Each example README documents its inputs, run sequence and cleanup. Single-module examples live under `modules/<module>/examples/` for catalogue, content, assignments, identity-rbac and operations.

## Supported versions

Terraform `>= 1.12.0` and the `hashicorp/azurerm` provider `>= 5.0.0, < 6.0.0`. The catalogue, behaviour-resolution and governance modules declare no AzureRM provider requirement. The `compatibility` workflow pins two cells: the lower cell (Terraform 1.12.0 with AzureRM 5.0.0) and the normal cell (Terraform 1.15.9 with AzureRM 5.5.0). The `ci` workflow runs Terraform 1.15.9 with the newest AzureRM release that satisfies the constraint, because no lock file is committed and `terraform init` resolves a fresh version on each run. Releases between the two pinned versions are not tested one by one. Commit a provider lock file in your own root.

## Composition ordering on first apply

Resource addresses are built from the keys, scopes and role definition IDs you supply, not from Azure IDs created during the apply. Even so, a first apply that creates policy content and role grants together can need staging. Three cases need care:

- Role grants are addressed by assignment key, grant scope and role definition ID. The grant scope is the assignment scope unless `role_grant_scopes` sets one. All of these must be known at plan time: a scope or role definition ID taken from a resource created in the same apply (for example `azurerm_resource_group.example.id`) fails with `Invalid for_each argument`. Build the ID from known values such as the subscription ID and the group name, or create that resource first with a targeted apply. The complete example needs this for its policy content: its role grant addresses are derived from resolved records that include the created definition and initiative IDs, so its runbook applies the content first.
- `identity.resource_group_name` is a plain string and the module does not create the group, so Terraform does not order identity creation after a resource group in your configuration. Create the group first, or add `depends_on` to the module call.
- A remediation created in the same apply as its assignment can finish with no deployments if Azure has not yet evaluated compliance. Delete the task and apply again; the [complete example runbook](examples/complete-policy-lifecycle/environments/uat/README.md) shows the steps.

## Migration and replacement

Keys and deterministic names are part of the public contract. Renaming a key, or changing a scope, target definition, identity setting or grant scope, changes an Azure name or address and replaces the resource; for definitions and initiatives it can also affect the assignments that reference them. Review the plan before applying such a change. The `replacement_review` output lists the attributes involved. The project records incompatible changes as explicit version or identity changes with a migration note; see [CONTRIBUTING.md](CONTRIBUTING.md).

No release exists yet, so the merge of the definitions and initiatives modules into `content`, and of the remediations and exemptions modules into `operations`, has no alias modules. State written by an earlier commit holds those resources at the old module addresses. Move them with `moved` blocks or `terraform state mv`, or accept replacement.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for local checks, the CI workflows and the publication checklist. Module suites live beside each module, and four contract roots under `tests/contracts` cover the catalogue pipeline, behaviour resolution, state hand-offs and root composition.

## Acknowledgements

Thank you to [Gettek](https://github.com/gettek) for the [Terraform Azure Policy as Code module](https://github.com/gettek/terraform-azurerm-policy-as-code), which inspired this project.

## Licence

MIT. See [LICENSE](LICENSE).
