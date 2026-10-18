# Live integration harness

`run-live.ps1` is an operator-started integration harness for the published examples. It runs Terraform against the approved UAT subscription, checks Azure read-backs between lifecycle stages and keeps a protected recovery record. It does not run in pull-request CI.

## Scope and profiles

- `complete-policy-lifecycle` exercises subscription-scoped definitions and initiative, the target resource group and storage account, assignment identity and role grant, remediation, exemption creation, renewal and convergence.
- `minimal-audit-assignment` exercises an assignment-only profile. At live time the harness supplies `assignment_scope_id` from the approved subscription context; it does not need a checked-in UAT variable file.
- No management-group or other-subscription writes are in scope.

The harness has two profiles, `complete` and `minimal`. It takes the profile from the folder name of `-ExampleRoot`: `complete-policy-lifecycle` selects `complete`, and `minimal-audit-assignment` selects `minimal`. Any other example root exits 1.

The complete profile uses a protected UAT variable file with `create_exemption = false`; the harness owns the later exemption and renewal stages. Prepare a new ignored input for each RunId from `examples/complete-policy-lifecycle/environments/uat/terraform.tfvars.example`, and keep the input at `<ArtifactRoot>/<RunId>/run-input.tfvars`. The harness treats that file as its protected input snapshot without copying onto itself. Do not reuse or overwrite an existing UAT file or run artifact. The complete example runbook describes the required values and Azure prerequisites.

## Approved local context

`<ArtifactRoot>` is the harness `-ArtifactRoot` parameter. It defaults to `terraform-azurerm-policy-framework-integration` under the user temporary directory (`$env:TEMP` on Windows), so run directories, logs, the mutation lock and recovery files never sit inside the working tree or the package snapshot. Pass an explicit path to keep several machines or clones apart.

Copy `tests/integration/approved-context.example.json` to
`<ArtifactRoot>/approved-context.json` and replace the synthetic
subscription, tenant and user with the explicitly authorised execution context.
Keep that real file ignored. The supported cloud and identity type remain
`AzureCloud` and `user`. A configuration file records approval scope; it does
not itself grant permission to run against an account.

Every live run, `-SkipApply` and `-CleanupOnly` invocation requires
`-ApprovedContextPath <ArtifactRoot>/approved-context.json`.
The harness validates the exact five-field schema before invoking Azure,
then retains a byte-hashed `approved-context.json` snapshot in the run directory.
Before mutations it checks the snapshot and current Azure account. Cleanup
requires an explicitly supplied context matching that pinned snapshot, including
the cloud and user. Missing or changed context blocks cleanup; preserve the
original recovery files. Runs created by an older harness without this snapshot
must finish cleanup with their original frozen harness before migration.
Offline fixture/status demos use synthetic context and require no context file.

## Run commands

Run from the repository root with PowerShell 7+, Terraform, and Azure CLI installed. The active Azure CLI tenant and subscription must exactly match the approved context supplied through `-ApprovedContextPath`. Before each Terraform mutation and exact Azure deletion, the harness rechecks that context and rejects `ARM_SUBSCRIPTION_ID` or `ARM_TENANT_ID` overrides outside the approved UAT.

Complete lifecycle:

```powershell
pwsh -File tests/integration/run-live.ps1 -ApprovedContextPath <ArtifactRoot>/approved-context.json -RunId "r261001120000" `
  -ExampleRoot examples/complete-policy-lifecycle `
  -VarFile "<ArtifactRoot>\r261001120000\run-input.tfvars"
```

Minimal assignment lifecycle (no variable file):

```powershell
pwsh -File tests/integration/run-live.ps1 -ApprovedContextPath <ArtifactRoot>/approved-context.json -RunId "r261001120001" `
  -ExampleRoot examples/minimal-audit-assignment
```

Preflight and inventory only:

```powershell
pwsh -File tests/integration/run-live.ps1 -ApprovedContextPath <ArtifactRoot>/approved-context.json -RunId "r261001120002" -SkipApply `
  -StatusPath "<ArtifactRoot>/preflight-r261001120002/run-status.json"
```

`-SkipApply` performs read-only Azure account, collision and baseline inventory checks. It writes the local run-status, input snapshot, log and baseline files, but returns before Terraform init, workspace selection/creation or Azure mutation. Use a preflight status path separate from the later live run's default status file; an existing status file is never overwritten or reused for a live run.

Resume cleanup from a persisted status file after interruption:

```powershell
pwsh -File tests/integration/run-live.ps1 -ApprovedContextPath <ArtifactRoot>/approved-context.json -StatusPath `
  "<ArtifactRoot>/r261001120000/run-status.json" -CleanupOnly
```

Explicit cleanup recovery exercise (complete profile only):

```powershell
pwsh -File tests/integration/run-live.ps1 -ApprovedContextPath <ArtifactRoot>/approved-context.json -RunId "r261001120003" `
  -VarFile "<ArtifactRoot>\r261001120003\run-input.tfvars" -RecoveryProbe
```

The probe runs only through target group, policy content and target baseline. It records an intentional test failure, removes only captured policy IDs, verifies their absence and the isolated state inventory, then persists a `CleanupOnly` pause before Terraform destroy. The initial process exits 3 to show the deliberate test failure and pending recovery; immediately run `-CleanupOnly` with its recorded status path. The resume completes destroy and absence/baseline checks, while reporting the original intentional test failure. The probe is separate from the default lifecycle and requires the approved live-run authorization.

`RunId` must be 1–14 lowercase letters or digits. Use a unique value for each run. The harness uses a global file lock to prevent concurrent live mutations.

Terraform argument probe. It runs Terraform on a generated configuration whose path contains spaces, under `-ArtifactRoot`. It makes no Azure call, so it needs neither Azure CLI nor `-ApprovedContextPath`:

```powershell
pwsh -File tests/integration/run-live.ps1 -TerraformArgumentProbe
```

It runs `init`, `validate`, `output` and `plan` on that configuration and exits 0 when each step passes. A failed step stops the script with an error, and Terraform must be on the PATH.

Usage and precondition rejections exit 1. These include an invalid or missing `-ApprovedContextPath`, an invalid `-RunId`, a missing `terraform` or `az` on the PATH, an Azure account that does not match the approved context, an unsupported example root, `-RecoveryProbe` combined with `-SkipApply` or the minimal profile, a missing variable file or one that breaks a profile rule, and an existing run status file. `-CleanupOnly` exits 2 when neither `-RunId` nor `-StatusPath` is given, once the approved context and Azure account checks have passed, and when a resume is refused because no status file exists at the path, the recorded tenant or subscription differs, or the mutation lock belongs to another run. These codes are shared with the test and cleanup results, so read the message as well as the code.

## Stage sequencing and assertions

In run order, the complete profile logs `stage 0a`, `stage 1a`, `stage 1b`, `stage 1c`, `stage 2` and `renewal`. The status file names each apply stage in `activeStage` while it runs and in `appliedStages` once it succeeds, using the identifiers `stage-0a`, `stage-0b`, `stage-1a`, `stage-1b`, `stage-1c`, `complete-owner-drift-restore`, `stage-2`, `renewal`, `exemption-removal` and `remediation-repeat`. It sets `activeStage` to `complete-owner-drift-mutation` before the Owner tag drift and to `policy-reenforcement-tag-removal-under-exemption` before the policy tag removal. The minimal profile applies `minimal-apply`, `minimal-owner-update` and `minimal-key-replacement`, then checks its plans. The recovery probe stops after `stage-1a` and sets `activeStage` to `recovery-probe-intentional-failure`.

`-ExpectedTagName` and `-ExpectedTagValue` (defaults `CostCentre` and `zctfp-uat`) name the policy-written tag and its value. The initial-absence check and the tag read-back use them. The stage 1 assignment check and the Owner drift step compare the literal `CostCentre` and `zctfp-uat`, and the policy tag removal deletes the literal `CostCentre`, so changing these parameters does not retarget a whole run.

The complete flow first creates the target group, then the policy definition and initiative, then the storage account. Before assignment it confirms `CostCentre` is absent and the Terraform-owned `Owner` tag is present. After assignment it verifies exact assignment scope, policy-set binding, identity and parameters; it compares Azure role grants with captured role-assignment IDs. Before creating a remediation task, the harness triggers a compliance scan scoped to the run-owned resource group. It polls only the captured storage resource and requires a `NonCompliant` state matching the captured assignment ID and exact initiative member reference `add-costcentre-tag-member`; any other, compliant or inconclusive state blocks remediation. It then requires remediation to report at least one successful deployment and zero failed deployments, verifies `CostCentre = zctfp-uat` while `Owner = terraform` remains, creates and reads back the exemption, exercises renewal and requires a converged plan. After remediation, it changes only `Owner` on the run-owned storage resource through its captured exact ID. The saved AzureRM plan must show an `update` that restores `Owner = terraform` and keeps policy-written `CostCentre = zctfp-uat` unchanged. The harness applies that exact plan, checks both tags in Azure and requires a no-change plan.

The complete profile removes only `CostCentre` from the run-owned storage account while the captured exemption is still active, confirms `Owner` remains, then removes the exemption with a reviewed Terraform plan and confirms the captured exemption ID is absent and no exemption still references the run assignment. A resource-group-only scan must then report that exact target/assignment/member as `NonCompliant`. A reviewed `-replace` plan must replace the captured remediation resource. The harness requires the replacement task's Azure `createdOn` to be later than the prior task, at least one successful deployment with no failed deployments, restored `CostCentre`, unchanged `Owner`, a subsequent resource-scoped `Compliant` state and a converged Terraform plan. The policy assignment remains present throughout this transition. These are live assertions, not fixture evidence until the run succeeds.

The minimal flow verifies the initial `audit-sub` assignment, then changes `assignment_owner` from `platform-governance` to `security-governance`. It saves and reads the real provider plan JSON, requires an in-place `update` at the existing assignment address, applies that exact plan, verifies the same Azure assignment ID and updated owner metadata, and requires convergence. It then changes `assignment_key` to `audit-sub-replacement`; the provider plan must delete the old assignment and contract-guard addresses and create replacement addresses at the same subscription scope. The harness captures both assignment IDs, verifies the old ID is absent and the new assignment has the expected owner, then requires convergence. Candidate Azure names are `audit-sub-subscription-built-in-audit` and `audit-sub-replacement-subscription-built-in-audit`.

The harness captures `terraform output -json lifecycle_resource_ids` as the source of resource IDs, including nested role-assignment values. The minimal example also persists its `resolved_assignment_review` output map to read assignment IDs and names by key. Null planned IDs are not treated as evidence of absence. IDs, actual Terraform provider plan actions, and evaluated time/expiry inputs are persisted after every mutation boundary so cleanup can resume safely.

Polling uses bounded retries: role grants 20 × 15 seconds, policy evaluation 30 × 30 seconds, remediation 20 × 30 seconds, tag read-back 10 × 30 seconds, and absence read-back 20 × 15 seconds. A not-found response is the only accepted evidence of absence; access, authentication, network and parse failures remain inconclusive. Repeat remediation additionally compares Azure's task creation timestamps and fails closed when the API does not prove a distinct execution.

## Cleanup and recovery

Each run selects a unique Terraform workspace and records its expected state path. A pre-existing default `terraform.tfstate` is allowed only when it is valid JSON with zero managed resources. The harness records its exact hash, lineage and serial, plus the hash of any existing `.backup` file. It verifies those files remain byte-for-byte unchanged before and after cleanup; it never adopts, migrates, edits or deletes them. Before final destroy, the harness inventories the active workspace's state addresses and Azure IDs and refuses to continue unless every managed Azure ID belongs to the run's captured manifest and resource types/addresses are allowlisted.

Cleanup proceeds in these boundaries:

1. Read the persisted exact-ID manifest. Parse each policy resource ID and verify its subscription, resource group and resource type against the run profile.
2. Delete only captured IDs with the matching Azure CLI command, in dependency order: exemption, remediation, assignment, role assignment, policy set definition, policy definition. Read each ID back until Azure confirms absence. No wildcard deletion is used.
3. Verify the source and protected variable snapshot are unchanged, verify the isolated Terraform state path/address inventory, then run Terraform destroy using the recorded variables.
4. Verify the run's resource group and every captured ID are absent. Compare resource-group and policy-resource inventories to their pre-run baseline.
5. Remove the Terraform workspace only after all absence and baseline checks pass.

`-CleanupOnly` resumes at recorded boundaries. Already absent Azure IDs are verified and skipped; incomplete or inconclusive boundaries remain recorded, and Terraform destroy is not invoked until exact-ID deletion and state isolation checks pass. Preserve the ignored local status file, log and state until cleanup has been independently reviewed.

Relevant command references: [Azure CLI policy state scan and filter](https://learn.microsoft.com/en-us/cli/azure/policy/state?view=azure-cli-latest), [Azure CLI tag merge](https://learn.microsoft.com/en-us/cli/azure/tag?view=azure-cli-latest), [policy remediation delete](https://learn.microsoft.com/en-us/cli/azure/policy/remediation?view=azure-cli-latest), [policy exemption delete](https://learn.microsoft.com/en-us/cli/azure/policy/exemption?view=azure-cli-latest), [policy assignment delete](https://learn.microsoft.com/en-us/cli/azure/policy/assignment?view=azure-cli-latest), [policy set-definition delete](https://learn.microsoft.com/en-us/cli/azure/policy/set-definition?view=azure-cli-latest), and [policy definition delete](https://learn.microsoft.com/en-us/cli/azure/policy/definition?view=azure-cli-latest).

## Deterministic checks and evidence

These checks use the checked-in JSON fixtures and must never invoke Azure CLI or Terraform:

```powershell
pwsh -NoProfile -File tests/integration/run-live.ps1 -HarnessFixtureDemo
pwsh -NoProfile -File tests/integration/run-live.ps1 -StatusPathDemo
```

The fixture demo exercises output capture, recovery inputs, assignment and grant assertions, remediation status and distinct-execution timestamp checks, exemption-present/absent read-backs, noncompliance scan gates, tag ownership/re-enforcement, minimal owner metadata expectations and exact CLI command selection. It is contract-fixture evidence, not provider-backed or live Azure evidence. Record the exact command, PowerShell version, result and worktree source in the local delivery record.

Test and cleanup statuses remain separate: exit codes 0 (both pass), 1 (test fails), 2 (cleanup fails), and 3 (both fail). `<ArtifactRoot>` (outside the working tree) holds raw recovery IDs, logs and inventory snapshots; logs redact the approved subscription ID. Do not publish these artefacts.

## Public package smoke check

`smoke-public-package.ps1` checks that the public source is self-contained. It copies the files that Git lists as tracked or not ignored into a new snapshot directory outside the working tree, writes a manifest of the copied paths beside it, and then runs these checks inside the snapshot: `terraform fmt -check -recursive .`, backend-disabled `init` and `validate` for every root in the `validate_roots` group of `scripts/tf-inventory.json`, and `scripts/repository_gate.py` against that manifest. It makes no Azure call and does not run `terraform test`. It prints the Terraform version that the inventory declares but does not compare it with the installed version.

Run it from the repository root with `pwsh`, with Terraform, Git and Python on the PATH:

```powershell
pwsh -NoProfile -File tests/integration/smoke-public-package.ps1
```

`-SourceRoot` and `-SnapshotRoot` override the source tree and the snapshot directory. The snapshot directory must not already exist and must lie outside the source tree, or the script exits 2. The script exits 0 when every check passes, 1 when a check fails and 2 when the snapshot cannot be built. Terraform downloads the providers that the roots declare during `init`, so a first run needs network access. The script leaves the snapshot and its manifest in place.
