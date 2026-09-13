# Native HCL catalogue example

This provider-free example shows catalogue consumption from native Terraform
values only. It declares one built-in reference, one custom definition bound to
a synthetic management group, and one initiative that references both.

All values are synthetic. `management_group_id` is a consumer binding supplied
by the example root through a variable; it is never embedded in portable policy
content. Replace the synthetic value when wiring a real consumer root.

The module writes no Azure resources and reads no files in this configuration.

## Run

```powershell
terraform init -backend=false -input=false
terraform validate -no-color
```

Pass `-var 'management_group_id=/providers/Microsoft.Management/managementGroups/<group-id>'`
to bind a different environment value.
