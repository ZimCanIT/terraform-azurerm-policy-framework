# Contributing

## Conventions

British English, plain headings, no emojis. Stable catalogue and assignment keys, deterministic Azure names, no random suffixes. Keep environment credentials and private policy data out of examples. Treat incompatible changes as explicit version or identity changes with a migration note.

Each child module keeps its public contract self-contained in its README and validates its own inputs so it remains independently usable.

The module boundary is the state boundary. Each AzureRM resource type is declared by exactly one module: identities and role assignments only in `modules/identity-rbac`, policy assignments only in `modules/assignments`. The four modules that create resources (`content`, `identity-rbac`, `assignments` and `operations`) each document the Azure permissions their state needs and the duties they keep apart, under `Azure permissions` and `Separation of duties` headings in their README. `scripts/repository_gate.py` fails when the module set, the ownership of resource types or those sections drift. When a producer module changes an output or a consumer changes an input, change both in one commit and keep `tests/contracts/state-handoffs` passing.

## Local checks

```powershell
terraform fmt -check -recursive
terraform -chdir=<root> init -backend=false -input=false
terraform -chdir=<root> validate
terraform -chdir=<root> test
git diff --check
python scripts/repository_gate.py
```

`terraform validate` does not evaluate variable validation rules or resource preconditions. Only `terraform test`, `terraform plan` or `terraform console` establish that behaviour.

## Continuous integration

Pull requests to `main` are gated by GitHub Actions. No workflow applies or destroys infrastructure, accesses Azure or publishes to the Registry.

| Workflow | Scope |
| --- | --- |
| `ci` | Formatting, backend-disabled init, validate and `terraform test` for every root in `scripts/tf-inventory.json`, plus the documentation and whitespace gates. Required before merge to `main`. |
| `compatibility` | Lower cell (Terraform 1.12.0 with AzureRM 5.0.0) and upper cell (Terraform 1.15.9 with AzureRM 5.5.0) over provider-backed roots and suites, pinned with a throwaway override file; provider-free roots on both Terraform versions. |
| `security` | gitleaks secret scanning. |

Tests live beside the code they cover: `modules/<module>/tests/` for module suites and `tests/contracts/` for the four cross-module contracts (catalogue pipeline, behaviour resolution, state hand-offs and root composition). Examples are deployment roots and carry no test suites.

## Live Azure evidence

Live runs are opt-in and separately authorised. `tests/integration/` holds the harness and runbook. Record resource IDs, operations and verification without secrets, and confirm absence after destroy.

The harness names module addresses and output shapes. When a module address changes, update the harness allowlist and its fixtures, then run its offline demos with PowerShell 7: `pwsh -NoProfile -File tests/integration/run-live.ps1 -HarnessFixtureDemo` and the same command with `-StatusPathDemo`. They call neither Azure nor Terraform, and CI does not run them.

## Publication

This project is pre-release and is not ready to publish: no version is tagged and the module is not on the Terraform Registry. The refactor that aligned the module boundaries with the state boundaries renamed and merged modules without alias modules, because no release exists to migrate. Before the first Registry release: complete the CI and live evidence above, keep the examples current with synthetic values, publish the source in a public GitHub repository named `terraform-azurerm-policy-framework`, and tag a tested semantic version such as `v0.1.0`. See HashiCorp's [publication requirements](https://developer.hashicorp.com/terraform/registry/modules/publish) and [standard module structure](https://developer.hashicorp.com/terraform/language/modules/develop/structure).
