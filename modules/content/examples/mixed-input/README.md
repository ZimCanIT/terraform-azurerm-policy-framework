# Mixed custom and built-in definitions

This runnable root demonstrates the two definition paths exposed by the
module:

- `allowed_locations` is an existing Azure built-in definition. The module
  records its ID and wildcard version intent without creating or looking up a
  resource.
- `require_cost_centre_tag` is a custom definition created by the module. Its
  catalogue key becomes its Azure name, and its `1.0.0` content version is
  added to the output metadata.

The custom definition is created in the subscription selected by the AzureRM
provider by default. To create it at management-group scope, supply the full
management group resource ID:

```powershell
terraform init
terraform plan -var 'management_group_id=/providers/Microsoft.Management/managementGroups/example'
```

Omit the variable for subscription scope:

```powershell
terraform init
terraform plan
```

Authentication and provider subscription selection are caller concerns. A
successful apply creates only the custom definition. The outputs expose the
shared canonical contract and filtered custom and built-in ID maps for
downstream modules.
