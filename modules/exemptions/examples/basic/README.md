# Exemptions basic example

Demonstrates a governed exemption request bound to an existing assignment at subscription scope, carrying owner, reason, ticket reference, category, compensating control and a future expiry date.

All identifiers and metadata values are synthetic; the assignment ID shown does not exist in any tenant.

## Run

```powershell
terraform init -backend=false -input=false
terraform validate -no-color
```

`terraform plan` additionally requires caller-configured AzureRM credentials and creates nothing.

## Evidence limits

Validation and planning prove schema and configuration compatibility only. They are not deployment evidence: no exemption is created and no expiry lifecycle is exercised in Azure.
