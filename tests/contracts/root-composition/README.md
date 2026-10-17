# Root composition contract

This contract root calls the public root module and checks its resolved assignment hand-off, assignment lifecycle ID keys, root-derived internal governance inventories, explicitly external governance references, deployment and blast-radius summaries, rollout, replacement and operational review outputs.

The test uses a provider-backed plan. It does not apply resources, contact Azure intentionally, or establish live behavior. Provider-free behavior belongs in child-module tests; live lifecycle and read-back are recorded separately by the authorised integration harness.

## Run

```powershell
terraform -chdir=tests/contracts/root-composition init -backend=false -input=false
terraform -chdir=tests/contracts/root-composition test
```

The root declares Terraform 1.12.0 or later and AzureRM 5.0.0 or later, below 6.0.0, the same range as each child module that uses the provider. Lock files are not committed, so a local `init` selects the newest AzureRM in that range.

The `compatibility` workflow lists this root as a provider-backed suite. For each cell it pins AzureRM with a throwaway override file, initialises, checks the selected provider version and runs this suite: Terraform 1.12.0 with AzureRM 5.0.0, and Terraform 1.15.9 with AzureRM 5.5.0. The result of each cell is in that workflow run. This file records no result.
