# Operations synthetic example

Feeds one resolved assignment record to both operation families:

- a bounded discovery request with caller-supplied evidence and a location filter;
- a governed exemption with owner, reason, ticket reference, category, compensating control and a future expiry.

Discovery is non-mutating and does not query Azure. Every request that is not `disabled` needs an approval reference, a role scope equal to the grant scope of a required role on the resolved assignment, a resource count and an eligible resolved assignment, and a request that fails one of these rules fails the plan. The discovery request here already supplies them. Only `mode = "execute"` creates a remediation. The exemption plans one subscription-scope exemption, so a real plan needs AzureRM credentials. The example fixes `evaluation_time` so the check that the exemption expiry is still in the future gives the same result on every plan. An `evaluation_time` later than the exemption's `expires_on` blocks the plan, because a `create` exemption needs a future expiry.

All identifiers and metadata are synthetic and the assignment ID does not exist in any tenant. Terraform state and outputs record intent and resource identity, not Azure compliance or remediation success.

The example outputs `operations`, holding the requested, discovered, blocked and created remediation views, and `exemptions`, the exemption status contract.

## Run

From this directory:

```powershell
terraform init -backend=false -input=false
terraform validate -no-color
```

Validation and planning prove schema and configuration compatibility only. They are not deployment evidence: no remediation or exemption is created and no lifecycle is exercised in Azure.
