# State-separated lifecycle example

Reference roots that run the framework as separate Terraform states instead of
one. Each root is applied by its own run, owns one class of Azure resources and
reads only what the roots before it published. The one-state equivalent is
`examples/complete-policy-lifecycle`.

| Order | Root | Owns | Reads |
| --- | --- | --- | --- |
| 1 | `target` | The resource group and storage account the policy governs | Nothing |
| 2 | `content` | The custom policy definition and the initiative | Nothing |
| 3 | `identity-rbac` | The assignment identity and its role grant | `content` outputs `definitions` and `initiatives` |
| 4 | `assignments` | The policy assignment | `content` outputs, and the `identity-rbac` output `assignment_bindings` |
| 5 | `operations` | The remediation request and the governed exemption | The `assignments` output `resolved_assignments` |

`shared` is a module, not a state. It holds the values that more than one state
must agree on: the names, the scope and role definition IDs derived from the
subscription, and the assignment intents. The `identity-rbac` and `assignments`
roots each resolve those intents for themselves, so they must read one copy.
Resolution is a pure function of its inputs, so identical inputs give identical
records in both states.

## Hand-offs

| Producer output | Consumer input | Contract |
| --- | --- | --- |
| `content` `definitions` and `initiatives` | `behaviour-resolution` `definitions` and `initiatives` | Canonical envelopes |
| `identity-rbac` `assignment_bindings` | `assignments` `identity_bindings` | Only assignments that need an identity have a binding |
| `assignments` `resolved_assignments` | `operations` `resolved_assignments` | Resolver records with the created assignment ID merged in |

The consumers read these with `terraform_remote_state`. The modules never read
state themselves, so a pipeline can supply the same values from its own
variables or an equivalent. The remediation request omits
`policy_assignment_id`, and the operations module takes it from the lifecycle
binding of the assignment the request names.

## Inputs

Every root declares `subscription_id`, `location` and `run_id` and passes them
to `shared`. Pass the same values to every root. For example:

```powershell
$env:TF_VAR_subscription_id = '<subscription id>'
$env:TF_VAR_run_id = 'demo1'
```

The defaults are synthetic so that every root initialises and validates offline.
`run_id` is 1 to 14 lowercase letters or digits. It forms the resource group
name `rg-zctfp-<run_id>` and the storage account name `zctfp<run_id>store`, so
reruns find the same resources and concurrent runs stay apart.

The `operations` root also takes `create_exemption`, `exemption_expiry` and
`evaluation_time`. Apply it once with `create_exemption` false so the exemption
cannot invalidate the pending remediation, then again with it true. Pass the
same `evaluation_time` to every plan and apply of the run, because the default
is evaluated at plan time and never converges.

## Run

Apply in order and destroy in reverse. A root's plan reads the states above it,
so those states must outlive the root that reads them.

```powershell
$roots = 'target', 'content', 'identity-rbac', 'assignments', 'operations'

foreach ($root in $roots) {
  terraform -chdir=examples/state-separated-lifecycle/$root init
  terraform -chdir=examples/state-separated-lifecycle/$root apply
}

[array]::Reverse($roots)
foreach ($root in $roots) {
  terraform -chdir=examples/state-separated-lifecycle/$root destroy
}
```

Offline validation needs no credentials:

```powershell
terraform -chdir=examples/state-separated-lifecycle/<root> init -backend=false
terraform -chdir=examples/state-separated-lifecycle/<root> validate
```

## State

Each root uses a local backend, so its state is the `terraform.tfstate` file in
its own directory. These files are ignored by git, are not locked and hold
policy content, resource IDs and principal IDs, so treat them as sensitive. They keep the
reference runnable without shared storage. A pipeline replaces the `backend`
block in each root, and the `terraform_remote_state` blocks that read another
root, with its own remote backend.

## What this does not separate

All five roots run here under one operator with one credential. The example
shows the boundaries and the hand-offs. It does not separate duties.
Separation needs a distinct principal for each state, holding the permission
class that the module README for that state lists:

- [content](../../modules/content/README.md)
- [identity-rbac](../../modules/identity-rbac/README.md)
- [assignments](../../modules/assignments/README.md)
- [operations](../../modules/operations/README.md)

Creating those principals and their federated credentials is outside this
repository.
