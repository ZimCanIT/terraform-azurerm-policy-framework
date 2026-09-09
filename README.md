# Azure Policy Framework for Terraform

Azure Policy Framework is the foundation for a composite Terraform module for Azure Policy governance. It is designed to provision definitions, initiatives, assignments, managed identity and RBAC, remediation tasks and exemptions through one reusable package.

The project follows proposed architecture from the article: [Architecting Azure Policy Governance at Enterprise Scale, Part 1](https://zimcanit.com/articles/azure-policy-at-scale-part-1/), and constitutes as the foundation for Part 2.

## Intended capabilities

- JSON directory ingestion and HCL authoring through a canonical model, including built-in references identified by stable Azure definition IDs.
- Bulk orchestration of definitions, initiatives and assignments, with independently usable submodules.
- Typed scopes for management groups, subscriptions, resource groups and resources, with parameter and effect validation where technically possible.
- Initiative groups, stable member references, explicit version choices and detection of incompatible parameter contracts.
- Assignment parameters, enforcement, exclusions, non-compliance messages, selectors and supported effect/version overrides.
- Effective behaviour resolved before managed identity and RBAC decisions, with declared roles deduplicated and granted at explicit scopes.
- Explicit remediation requests and auditable exemptions, including ownership and expiry metadata.
- Reviewable outputs for scopes, versions, effective behaviour and identity/RBAC requirements.

AzureRM is the intended primary provider, and AzAPI is used selectively for documented provider gaps.

## Architecture and ownership

The package root will expose the composite module. Consumer root configurations will supply provider configuration, backends, environment-specific scope IDs and parameter values. Each consumer root configuration owns its state; calling a child module does not create a separate state.

The article's content and ownership layout is represented by:

```text
catalogue/
  built-in-references/
  custom-definitions/
  initiatives/
assignments/
  organisation/
  platform/
  landing-zones/
  subscriptions/
exemptions/
remediation/
tests/
environments/
```

These categories illustrate deployment ownership. They do not require a particular landing-zone hierarchy. Resource-group and resource assignments use the same scope contract, irrespective of the folder used to organise them.

Reusable implementation belongs under `modules/`, with boundaries for catalogue normalisation, definitions, initiatives, behaviour resolution, assignments, identity/RBAC, remediations and exemptions. Normalisation accepts HCL objects or decoded JSON; resource modules consume the resolved contract. Environment data remains separate from reusable policy content.

State boundaries may separate content, assignments and operational requests. Cross-state consumers must receive explicit IDs and schema/version contracts. Remediation approvals and execution evidence belong in operational workflows; they are not implied by assignment creation.

## Development checks

GitHub Actions is the planned CI/CD platform. Workflows and pre-commit hooks are architectural scope only and have not been implemented. The future formatting gate will run `terraform fmt -check -diff` against maintained Terraform sources, excluding `docs/` and downloaded provider/module caches.

Local pre-commit hooks will provide early formatting feedback. GitHub Actions will independently enforce the same checks on pull requests, regardless of whether contributors install local hooks. An empty scaffold must be reported as having no Terraform sources, rather than presented as a validated module.

## CI/CD scope

| Stage | Scope and gate |
| --- | --- |
| Architecture branch, current | Document GitHub Actions and pre-commit responsibilities; no executable workflows or hooks. |
| Module implementation, required before release | Add `terraform init -backend=false` and `terraform validate` for each supported module and example root; add `terraform test` contract tests, JSON checks, documentation checks and secret scanning. |
| Azure integration, required before release | Dedicated test scopes and workload identity federation; verify provider behaviour, all supported scopes, identities, roles, exemptions and explicit remediation. Clean up test resources and retain evidence. |
| Consumer deployment | Environment-specific root configurations produce reviewed plans. Protected GitHub environments gate apply, using the reviewed plan and concurrency controls per state. Remediation requires a separate approved operation. |
| Registry release | Publish only tested semantic versions after documentation, compatibility and migration checks. Registry publication is separate from deployment into Azure. |

Policy tests must cover incompatible initiative parameters, missing or invalid assignment parameters, scope mismatch, effect overrides, role scope selection, stable keys and remediation opt-in. Provider-backed tests are needed where local validation cannot establish Azure behaviour.

## Publication requirements

Before the first Registry release:

1. Implement the composite root and public submodules with documented inputs, outputs, validations and provider requirements.
2. Supply runnable JSON, HCL, mixed initiative and operational examples with synthetic environment values.
3. Complete automated validation and Azure integration tests; document supported versions and known limitations.
4. Publish the source in a public GitHub repository named `terraform-azurerm-policy-framework`.
5. Provide a repository description and a tested semantic version release tag, such as `v0.1.0`, before registering the module.

See HashiCorp's [publication requirements](https://developer.hashicorp.com/terraform/registry/modules/publish) and [standard module structure](https://developer.hashicorp.com/terraform/language/modules/develop/structure).

## Contributing and references

Use British English, plain headings and concise explanations. Keep architecture changes traceable to governance requirements. Do not include environment credentials or private policy data in examples.

Reference material and local working records under `docs/` are ignored by this repository. Public usage and compatibility documentation must therefore live in the root README, module READMEs and examples.

## Acknowledgements

Thank you to [Gettek](https://github.com/gettek) for the [Terraform Azure Policy as Code module](https://github.com/gettek/terraform-azurerm-policy-as-code), which inspired this project. Its approach to reusable policy definitions, initiative composition, assignments, role extraction, remediation and exemptions helped shape the architecture of Azure Policy Framework.

The design also draws on experience reviewing an offline Sigma implementation, particularly its bulk ingestion of policy JSON.

## Licence

See [LICENSE](LICENSE). Any reused third-party source must retain its applicable notices and attribution.
