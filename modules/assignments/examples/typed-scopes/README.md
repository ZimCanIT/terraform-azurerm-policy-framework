# Assignments synthetic example

Demonstrates typed scopes for all four implemented scope types (management group, subscription, resource group and resource) in one module call, with exclusions, selectors, effect overrides, enforcement mode, non-compliance messages and rollout metadata. Assignment intent is separated from the resolved behaviour contract, mirroring the resolver output.

All identifiers are synthetic; no tenant or subscription data is embedded.

## Run

From this directory:

```powershell
terraform init -backend=false -input=false
terraform validate -no-color
```

`terraform plan` additionally requires caller-configured AzureRM credentials and creates nothing. The example outputs `assignments`, the canonical assignment records.

## Evidence limits

Validation and planning prove schema and configuration compatibility only. They are not deployment evidence: no assignment is created and no Azure Policy behaviour is observed.
