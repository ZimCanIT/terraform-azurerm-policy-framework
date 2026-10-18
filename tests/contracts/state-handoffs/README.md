# State hand-offs contract

Provider-backed contract fixture for the three hand-offs between the four
Terraform states of the framework: content to the states that resolve
assignments, role grants to assignment, and assignment to operations.

The root runs the same fixture through two pipelines:

- The direct pipeline wires each module output straight into the next module,
  as the composite root does in one state.
- The separated pipeline passes every hand-off through `jsonencode` and
  `jsondecode`. That drops all Terraform types: lists and sets become tuples
  and maps become objects. It is the least typed form a consumer can receive,
  as when a pipeline supplies a hand-off as a JSON variable. A value read from
  remote state is expected to keep its stored output type, so this is the
  stricter case. The separated pipeline also runs the resolver twice, once as
  the role-grant state and once as the assignment state would.

The test file asserts that:

- the content envelopes cross the boundary unchanged, an unknown capability
  stays null and a verified absence stays an empty collection;
- the resolver output, the identity-rbac output, the assignments output and the
  operations output are identical in both pipelines;
- two resolver instances given the same hand-off and intents are identical;
- a remediation request that omits `policy_assignment_id` still takes it from
  the serialised lifecycle binding, and exemptions verify against it;
- an assignment that needs no identity has no binding in the role-grant
  hand-off or the assignments output, in either pipeline;
- a null assignment ID in the serialised lifecycle hand-off is reported as
  `assignment_id_unknown` and is never read as a match.

Comparisons use `jsonencode` on both sides because Terraform equality compares
types as well as values, so a decoded tuple never equals a list.

The test uses a mock provider and a provider-backed plan. It does not apply
resources, contact Azure or read remote state. Reading a real state file is
shown by the reference roots under `examples/state-separated-lifecycle`.

## Run

```powershell
terraform -chdir=tests/contracts/state-handoffs init -backend=false -input=false
terraform -chdir=tests/contracts/state-handoffs test
```
