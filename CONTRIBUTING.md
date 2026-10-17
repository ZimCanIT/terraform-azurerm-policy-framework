# Contributing

## Conventions

British English, plain headings, no emojis. Stable catalogue and assignment keys, deterministic Azure names, no random suffixes. Keep environment credentials and private policy data out of examples. Treat incompatible changes as explicit version or identity changes with a migration note.

Each child module keeps its public contract self-contained in its README and validates its own inputs so it remains independently usable.

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

Tests live beside the code they cover: `modules/<module>/tests/` for module suites and `tests/contracts/` for the three cross-module hand-offs (catalogue pipeline, behaviour resolution and root composition). Examples are deployment roots and carry no test suites.

## Live Azure evidence

Live runs are opt-in and separately authorised. `tests/integration/` holds the harness and runbook. Record resource IDs, operations and verification without secrets, and confirm absence after destroy.

## Publication

Before the first Registry release: complete the CI and live evidence above, keep the examples current with synthetic values, publish the source in a public GitHub repository named `terraform-azurerm-policy-framework`, and tag a tested semantic version such as `v0.1.0`. See HashiCorp's [publication requirements](https://developer.hashicorp.com/terraform/registry/modules/publish) and [standard module structure](https://developer.hashicorp.com/terraform/language/modules/develop/structure).
