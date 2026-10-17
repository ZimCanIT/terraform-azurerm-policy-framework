# Azure Policy Framework for Terraform

A composite Terraform module for Azure Policy governance at enterprise scale. It turns a portable policy catalogue into definitions, initiatives, typed assignments, managed identity and least-privilege RBAC, explicit remediation requests and governed exemptions, with governance ownership recorded alongside every control.

The design follows [Architecting Azure Policy Governance at Enterprise Scale, Part 1](https://zimcanit.com/articles/azure-policy-at-scale-part-1/).

## Usage

```hcl
module "policy" {
  source = "ZimCanIT/policy-framework/azurerm"

  catalogue = {
    custom_definition_directory  = "${path.root}/catalogue/custom-definitions"
    built_in_reference_directory = "${path.root}/catalogue/built-in-references"
    initiative_directory         = "${path.root}/catalogue/initiatives"
  }

  assignments = {
    tag-baseline = {
      target          = { initiative_key = "tag-governance", reference_id = "tag-baseline" }
      scope           = { type = "management_group", id = "/providers/Microsoft.Management/managementGroups/landing-zones" }
      effect          = "Modify"
      version_binding = "unversioned"
      governance      = { owner = "platform-governance", requirement_id = "REQ-TAG-001" }
    }
  }

  requirements = {
    tag-governance = {
      owner           = "platform-governance"
      control_keys    = ["tag-governance"]
      assignment_keys = ["tag-baseline"]
      status          = "approved"
    }
  }
}
```

The caller owns the provider configuration, backend and state. The module never prescribes a management-group hierarchy and never reads tenant values from source files; scope IDs arrive through variables.

## What it provides

| Layer | Module | Responsibility |
| --- | --- | --- |
| Control catalogue | `modules/catalogue` | Only file-reading boundary. Adapts JSON directories and native HCL into canonical `definitions` and `initiatives` envelopes. Provider-free. |
| Content | `modules/definitions`, `modules/initiatives` | Custom definitions, built-in pass-through by stable Azure ID, initiative composition with groups, parameters and version choices. |
| Behaviour | `modules/behaviour-resolution` | Effective effect, version, identity requirement and remediation eligibility per assignment. Provider-free. |
| Assignment topology | `modules/assignments` | Typed management-group, subscription, resource-group and resource assignments with parameters, enforcement, exclusions, selectors, overrides and messages. |
| Operations | `modules/identity-rbac`, `modules/remediations`, `modules/exemptions` | Assignment identities and deduplicated role grants at explicit scopes, explicit remediation requests, governed exemptions with expiry. |
| Governance | `governance/requirements-and-ownership` | Requirement ownership and traceability to controls and assignments. Provider-free. |

Each child module is independently usable and validates its own inputs. Stable catalogue and assignment keys drive deterministic Azure names; no random suffixes are generated.

## Inputs

| Name | Type | Purpose |
| --- | --- | --- |
| `catalogue` | object | Source directories and native HCL entries for the catalogue adapter. |
| `definitions`, `initiatives` | any | Canonical entries merged over the catalogue output; a matching key overrides the catalogue record. |
| `assignments` | any | Assignment intent keyed by stable assignment key. |
| `remediation_requests`, `discovery_evidence` | any | Explicit remediation operations and their discovery evidence. |
| `exemptions`, `evaluation_time` | any, string | Governed exemption requests and the fixed RFC3339 instant used to classify expiry. |
| `requirements`, `external_control_keys`, `external_assignment_keys` | map(object), set(string) | Governance requirements and references declared as externally managed. |

Policy payload inputs are `any` because every key carries its own parameter and rule shapes. Each child module validates its keys and names the offending key and rule in its diagnostics.

## Outputs

`definitions`, `initiatives`, `resolved_assignments`, `lifecycle_resource_ids`, `governance`, `remediations`, `exemptions`, `plan_summary` and `replacement_review`. Resource IDs for assignments, identities, role grants, remediations and exemptions are in `lifecycle_resource_ids`.

## Examples

| Example | Deploys |
| --- | --- |
| [`examples/minimal-audit-assignment`](examples/minimal-audit-assignment/README.md) | One built-in Audit assignment at subscription scope. No identity, no mutation. |
| [`examples/complete-policy-lifecycle`](examples/complete-policy-lifecycle/README.md) | Catalogue through custom Modify definition, initiative, resource-group assignment with user-assigned identity and least-privilege grant, explicit remediation and a governed exemption against a disposable target. |

Each example README covers prerequisites, inputs, run sequence, expected outputs and cleanup. Child modules carry their own single-module examples under `modules/<module>/examples/`.

## Supported versions

Terraform `>= 1.12.0` and AzureRM `>= 5.0.0, < 6.0.0`. The catalogue, behaviour-resolution and governance modules need Terraform only. Consumer roots should commit their own provider lock file.

## Composition ordering on first apply

When one configuration creates custom definitions or initiatives and also assigns them with managed identities and role grants, apply the content layer first, then the assignment and grant layer. Applies where the content already exists are unaffected.

## Migration and replacement

Stable keys and deterministic names are part of the public contract. Changing a key, scope, identity strategy or grant scope replaces an Azure resource. The `replacement_review` output lists the attributes involved. A release that changes them carries a migration note naming the old and new address and any import or state move required.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for validation commands, CI gates and publication requirements.

## Acknowledgements

Thank you to [Gettek](https://github.com/gettek) for the [Terraform Azure Policy as Code module](https://github.com/gettek/terraform-azurerm-policy-as-code), which inspired this project.

## Licence

See [LICENSE](LICENSE).
