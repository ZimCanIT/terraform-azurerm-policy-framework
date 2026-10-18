# Mixed HCL and JSON catalogue example

This provider-free example exercises every catalogue authoring path in one
call:

- a flat JSON library under `catalogue/` with a built-in reference
  (`built-in-references/`), two custom definitions, one carrying a
  `<name>-parameters.json` companion (`custom-definitions/`), and an
  initiative with keyed members, a group and member version intent
  (`initiatives/`);
- native HCL declaring a custom definition bound to a synthetic management
  group and an initiative that references JSON and native entries by their
  stable catalogue keys.

All values are synthetic. JSON files hold portable policy content only; the
management-group binding is supplied by this root through a variable and is
never embedded in the library. The module writes no Azure resources and
performs no Azure lookups.

## Run

From this directory:

```powershell
terraform init -backend=false -input=false
terraform validate -no-color
```

`terraform validate` checks the configuration regardless of variable values. To
bind a different environment value, pass
`-var 'management_group_id=/providers/Microsoft.Management/managementGroups/<group-id>'`
to `terraform plan` or `terraform console`, which also evaluate the variable's
validation rule. Each JSON directory is flat and may contain only `.json` files;
a parameter companion must have a matching policy or initiative envelope of the
same stem.

The example outputs the canonical `definitions` and `initiatives` that
`modules/content` consumes, and the `source_summary` provenance records.
