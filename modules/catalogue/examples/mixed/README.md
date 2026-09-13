# Mixed HCL and JSON catalogue example

This provider-free example combines both authoring formats in one call:

- native HCL declares a built-in reference, a custom definition and an
  initiative;
- a flat JSON directory declares one custom definition with governance and
  capability declarations.

The initiative references native and JSON entries by their stable catalogue
keys, proving the merge is deterministic. All values are synthetic. The HCL
management-group binding is supplied by the example root through a variable and
is never embedded in portable policy content.

## Run

```powershell
terraform init -backend=false -input=false
terraform validate -no-color
```
