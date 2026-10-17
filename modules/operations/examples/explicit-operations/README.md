# Operations synthetic example

Feeds one resolved assignment record to both operation families:

- a bounded discovery request with caller-supplied evidence and a location filter;
- a governed exemption with owner, reason, ticket reference, category, compensating control and a future expiry.

Discovery is non-mutating and does not query Azure. Change the request `mode` to `execute` only with an approval reference, a role scope that matches a resolved required role, a resource limit and an eligible resolved assignment. The exemption plans one subscription-scope exemption, so a real plan needs AzureRM credentials. The example fixes `evaluation_time` so the expiry classification does not change between plans.

All identifiers and metadata are synthetic and the assignment ID does not exist in any tenant. Terraform state and outputs record intent and resource identity, not Azure compliance or remediation success.

## Run

```powershell
terraform init -backend=false -input=false
terraform validate -no-color
```

Validation and planning prove schema and configuration compatibility only. They are not deployment evidence: no remediation or exemption is created and no lifecycle is exercised in Azure.
