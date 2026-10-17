# Catalogue pipeline contract root

Provider-backed contract fixture for the producer chain: catalogue to
definitions (module fixtures plus native entries, including the unknown-versus-
verified-absence capability states) and catalogue to definitions to initiatives
to behaviour resolution (file fixtures under `fixtures/`). It replaces the
former `catalogue`, `catalogue-to-definitions` and `catalogue-to-initiatives`
roots without dropping an assertion.

```powershell
terraform -chdir=tests/contracts/catalogue-pipeline init -backend=false -input=false
terraform -chdir=tests/contracts/catalogue-pipeline test
```
