# Root composition contract

This contract root calls the public root module and checks its resolved assignment hand-off, assignment lifecycle ID keys, root-derived internal governance inventories, explicitly external governance references, deployment and blast-radius summaries, rollout, replacement and operational review outputs.

The test uses a provider-backed plan. It does not apply resources, contact Azure intentionally, or establish live behavior. Provider-free behavior belongs in child-module tests; live lifecycle and read-back are recorded separately by the authorised integration harness.

## Run

```powershell
terraform -chdir=tests/contracts/root-composition init -backend=false -input=false
terraform -chdir=tests/contracts/root-composition test
```

The root declares Terraform 1.12.0 or later and AzureRM 5.0.0 or later, below 6.0.0. Child-module constraints may raise the effective provider floor; this contract root's lock file currently selects AzureRM 5.5.0. Lower-bound execution is tracked separately.
