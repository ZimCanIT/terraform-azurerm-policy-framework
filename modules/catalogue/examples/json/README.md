# JSON catalogue example

This provider-free example reads a flat JSON policy library. It includes:

- a custom definition with a `<name>-parameters.json` companion, capability and
  governance declarations;
- a built-in reference with version intent;
- an initiative with keyed member references, a group and member version intent.

All values are synthetic. The JSON files contain portable policy content only:
deployment bindings such as management-group IDs belong in consumer roots. The
module writes no Azure resources and performs no Azure lookups.

## Run

```powershell
terraform init -backend=false -input=false
terraform validate -no-color
```

Each directory is flat and may contain only `.json` files. Parameter companions
must have a matching policy or initiative envelope of the same stem.
