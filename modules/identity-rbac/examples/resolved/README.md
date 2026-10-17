# Identity and RBAC resolved example

Demonstrates identity and role-grant decisions taken from a resolved assignment contract. One `DeployIfNotExists` assignment requires a user-assigned managed identity with a role grant at an explicit resource-group scope; one `Audit` assignment requires no identity and no grant.

All identifiers, including role definition and scope IDs, are synthetic.

## Run

```powershell
terraform init -backend=false -input=false
terraform validate -no-color
```

`terraform plan` additionally requires caller-configured AzureRM credentials and creates nothing.

## Evidence limits

Validation and planning prove schema and configuration compatibility only. They are not deployment evidence: no identity, role assignment or grant scope is created or verified in Azure.
