# Complete policy lifecycle example: UAT environment runbook

This runbook executes the complete policy lifecycle example against the authorised UAT subscription in a staged sequence, then destroys and verifies everything the run created. The values are synthetic-safe until you replace the placeholders; nothing real is checked in.

The example root is `examples/complete-policy-lifecycle` and all commands below are run from the repository root. Subscription selection is ambient: the example root declares no provider subscription override, so the AzureRM provider uses the Azure CLI login context. The `az account set` step below is therefore mandatory.

## Prerequisites

1. Terraform 1.12 or newer on the PATH.
2. Azure CLI logged in: `az login`.
3. Select the authorised subscription and record it for later read-back:

   ```powershell
   az account show --query "[id, name]" --output table
   az account set --subscription "<authorised-subscription-id>"
   ```

4. A short lowercase alphanumeric run identifier (RUNID) that is unique in the subscription. It keeps resource names collision-free and makes cleanup attributable.

## Inputs

Copy the template and replace the placeholders:

```powershell
Copy-Item examples/complete-policy-lifecycle/environments/uat/terraform.tfvars.example `
          examples/complete-policy-lifecycle/environments/uat/uat.tfvars
```

Then in `uat.tfvars` replace every `RUNID` with your run identifier and every `SUBSCRIPTION-ID` with the authorised subscription ID. Set `EVALUATION-TIME-UTC` to the current UTC RFC3339 instant and `EXPIRY-TIME-UTC` to a later future UTC RFC3339 instant. Keep the evaluation instant fixed across the run. The storage account name segment `runid` must become the lowercase run identifier because storage account names accept only lowercase alphanumeric characters.

| Input | Template value | Meaning |
| --- | --- | --- |
| `policy_subscription_id` | `SUBSCRIPTION-ID` | Qualifies policy role IDs and the live grant scope; match the selected Azure CLI subscription. |
| `target_resource_group_name` | `rg-zctfp-RUNID` | Disposable resource group hosting the storage account target, the assignment scope and the role grant scope. |
| `target_location` | `swedencentral` | Region for the target resource group. |
| `target_storage_account_name` | `zctfprunidstore` | Storage account the Modify policy tags and remediation changes. 3 to 24 lowercase alphanumeric characters. |
| `target_resource_group_id` | `/subscriptions/SUBSCRIPTION-ID/resourceGroups/rg-zctfp-RUNID` | Full resource group scope for the assignment and grant; keeps Modify and remediation contained to the run's resources. |
| `identity_location` | `swedencentral` | Region for the user-assigned managed identity. |
| `identity_resource_group_name` | `rg-zctfp-RUNID` | Resource group that hosts the managed identity. |
| `create_exemption` | `false` | Stage 2 switch; stays false for the whole of stage 1. |
| `evaluation_time` | `EVALUATION-TIME-UTC` | UTC RFC3339 instant fixed once for every plan and apply in this run. |
| `exemption_expiry` | `EXPIRY-TIME-UTC` | Future UTC RFC3339 expiry used by stage 2 and changed only in the renewal step. |
| `exemption_assignment_id` | commented out | Stage 2 only: the resolved assignment id from the stage 1 outputs. |

Keep `uat.tfvars`, `terraform.tfstate*` and any plan files out of Git. The committed artefact is the `.example` template only.

## Stage 0: create the target resource group, definitions and initiative first

The managed identity and the role grant are created inside the target resource group, but the identity and RBAC modules reference that group by name and cannot depend on the example's own `azurerm_resource_group` resource. Create the group with one targeted apply before the full apply so the later stages never race the group's creation:

```powershell
terraform -chdir=examples/complete-policy-lifecycle init -backend=false -input=false
terraform -chdir=examples/complete-policy-lifecycle apply -input=false `
  -target=azurerm_resource_group.target `
  -var-file=environments/uat/uat.tfvars
```

The role grant address is derived from the resolved required-role record, which includes the created policy definition and initiative resource IDs. Terraform cannot plan a `for_each` address from values that are only known after the definitions exist, so the first run also applies the policy content layer on its own:

```powershell
terraform -chdir=examples/complete-policy-lifecycle apply -input=false `
  -target=module.framework.module.content.azurerm_policy_definition.this `
  -target=module.framework.module.content.azurerm_policy_set_definition.subscription `
  -var-file=environments/uat/uat.tfvars
```

The storage account is not included in these steps: it already depends on the resource group resource and is created in stage 1 with everything else. Applies where the definitions and initiative already exist do not need the targeted steps.

## Stage 1a: apply the assignment, identity, grant and storage account layer

The remediation request's `for_each` address digests the created assignment's Azure ID, which is unknown while the assignment itself is being created, so the full apply fails on its first run. Apply the assignment, identity, role grant and storage account layer first; the remediation is created by the full apply in stage 1b once the assignment exists in state:

```powershell
terraform -chdir=examples/complete-policy-lifecycle apply -input=false `
  -target=azurerm_storage_account.target `
  -target=module.framework.module.assignments.azurerm_resource_group_policy_assignment.this `
  -target=module.framework.module.assignments.terraform_data.contract_guard `
  -target=module.framework.module.identity-rbac.azurerm_user_assigned_identity.this `
  -target=module.framework.module.identity-rbac.azurerm_role_assignment.this `
  -var-file=environments/uat/uat.tfvars
```

## Stage 1b: apply the remediation and converge

```powershell
terraform -chdir=examples/complete-policy-lifecycle apply -input=false `
  -var-file=environments/uat/uat.tfvars
```

This creates the explicit remediation request against the now-known assignment ID. Review the plan before approving.

### Remediation evaluation race

A remediation task can reach `Succeeded` with zero deployments when the assignment's policy evaluation lags the task's creation: the task scans the compliance snapshot from before the storage account was assessed. The storage account stays untagged. Recover by deleting the task and re-applying so Terraform recreates it against a refreshed compliance snapshot:

```powershell
az policy remediation delete --name remediate-tag-rg --resource-group "rg-zctfp-RUNID"
terraform -chdir=examples/complete-policy-lifecycle apply -input=false `
  -var-file=environments/uat/uat.tfvars
```

### Stage 1 verification

Wait for remediation to finish, then verify the observed effect with read-only Azure CLI queries:

```powershell
# Remediation task status must reach Succeeded.
az policy remediation list `
  --resource-group "rg-zctfp-RUNID" --output table

# The policy-added tag on the storage account must be the expected value.
az storage account show `
  --name "zctfprunidstore" --resource-group "rg-zctfp-RUNID" `
  --query "tags.CostCentre" --output tsv
```

The tag read-back must return exactly `zctfp-uat`, the Modify parameter value the example declares. Also read back the assignment binding and identity:

```powershell
terraform -chdir=examples/complete-policy-lifecycle output resolved_assignment_id
az policy assignment show --name "<assignment name from resolved id>" --scope "<target resource group id>" --output json
```

The assignment must show the target resource group as its scope, a `UserAssigned` identity type and the managed identity resource id from this run.

### Stage 1 convergence

```powershell
terraform -chdir=examples/complete-policy-lifecycle plan -detailed-exitcode -input=false `
  -var-file=environments/uat/uat.tfvars
```

The exit code must be 0 with no unexpected changes.

Ownership note: Azure Policy writes the `CostCentre` tag during remediation. The example's lifecycle rule ignores only `tags["CostCentre"]`; Terraform continues to own the `Owner` tag and every other storage account property. The refreshed plan must converge while unrelated tag drift remains visible.

## Stage 2: create the exemption (R9 sequencing)

Only after every stage 1 assertion has passed, set `create_exemption = true` in `uat.tfvars`, uncomment `exemption_assignment_id` and set it to the resolved assignment id output. Confirm `evaluation_time` is set in `uat.tfvars`: `timestamp()` is unknown at plan time, so the exemption status outputs churn on every plan and no plan can converge without a fixed evaluation instant.

```powershell
terraform -chdir=examples/complete-policy-lifecycle output -raw resolved_assignment_id
```

```hcl
create_exemption        = true
exemption_assignment_id = "/subscriptions/SUBSCRIPTION-ID/resourceGroups/rg-zctfp-RUNID/providers/Microsoft.Authorization/policyAssignments/<assignment-name>"
```

Apply again with the same variable file:

```powershell
terraform -chdir=examples/complete-policy-lifecycle apply -input=false `
  -var-file=environments/uat/uat.tfvars
```

The sequencing is deliberate (goal requirement R9): the exemption is created only after the remediation assertion completes, so exemption evaluation cannot invalidate the remediation fixture mid-run, and the remediation task has already changed the target before the policy evaluation is relaxed.

### Stage 2 verification and convergence

```powershell
az policy exemption list --resource-group "rg-zctfp-RUNID" --output json
```

The exemption must reference this run's assignment as its `policyAssignmentId`, carry the exact UTC instant configured in `exemption_expiry` as `expiresOn`, and include the governance metadata (owner, reason, ticket, approver, compensating control). Then re-run the stage 1 convergence plan command; the exit code must again be 0.

## Renewal: in-place exemption update

Change `exemption_expiry` in `uat.tfvars` to a later future date, apply with the same variable file, and read the exemption back:

```powershell
terraform -chdir=examples/complete-policy-lifecycle apply -input=false `
  -var-file=environments/uat/uat.tfvars
az policy exemption list --resource-group "rg-zctfp-RUNID" --output json
```

The exemption must be updated in place (no destroy or recreate of the policy assignment or exemption), and the convergence plan must still return exit code 0. Compute the new date once for the run and keep it in `uat.tfvars` so repeated plans stay converged; do not use a moving timestamp.

## Destroy and absence verification

Keep `uat.tfvars` exactly as the final stage left it (`create_exemption = true` and `exemption_assignment_id` set) so the destroy plan covers every created resource, then destroy:

```powershell
terraform -chdir=examples/complete-policy-lifecycle destroy `
  -var-file=environments/uat/uat.tfvars
```

A successful destroy command alone is not proof of absence. Verify each class with Azure CLI read-back; only an authoritative not-found response counts, and access denied, expired tokens and network errors are inconclusive:

```powershell
az group show --name "rg-zctfp-RUNID"
az policy assignment show --name "<assignment name from resolved id>" --scope "<target resource group id>"
az policy definition show --id "<definition id>"
az policy set-definition show --id "<initiative id>"
az identity show --ids "<identity resource id>"
az role assignment list --scope "<target resource group id>"
az policy remediation list --resource-group "rg-zctfp-RUNID"
az policy exemption list --resource-group "rg-zctfp-RUNID"
```

Every query must return not found (the role assignment and exemption lists must be empty). The target resource group absence also confirms the storage account, identity, grant, remediation and RG-scoped exemption went with it, and the subscription-scoped policy definition and initiative checks confirm the policy content is gone.

## Optional harness

`tests/integration/run-live.ps1` automates this runbook against the published example root, with bounded polling, a guaranteed cleanup handler and separate test and cleanup exit statuses. See `tests/integration/README.md` for usage, polling defaults and the cleanup-only resume command.
