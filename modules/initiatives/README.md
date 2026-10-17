# Initiatives module

`modules/initiatives` is the Azure Policy initiative resource boundary. It consumes canonical initiative envelopes from `module.catalogue.initiatives` and canonical definition outputs from `module.definitions.definitions`, resolves keyed member references to definition IDs, preserves direct policy-definition IDs and creates deterministic Azure Policy set definitions without reading source files.

## Contract

| Input | Type | Behaviour |
| --- | --- | --- |
| `initiatives` | `any` | Canonical initiative objects keyed by stable catalogue key. Each entry may carry `catalogue_key`, `name`, `display_name`, `description`, `metadata`, `parameters`, `policy_definition_references`, `policy_definition_groups`, `management_group_id`, `governance` and `version`. |
| `definitions` | `any` | Canonical definition objects keyed by stable catalogue key. Keyed initiative members resolve their `definition_key` against this map. |

Each initiative member accepts `reference_id`, one of `definition_key` or `policy_definition_id`, optional `parameter_values`, optional `group_names`, optional `effect` and boolean `required` metadata, and optional `version_constraint` or `pinned_version`. Keyed members resolve through `definitions`; direct IDs pass through unchanged. Member IDs must be valid Azure Policy definition resource IDs, keyed definitions must be scope-compatible, and reference IDs and group names are unique case-insensitively. Direct members require exactly one version selector; keyed members may inherit the canonical definition intent, where the inherited version recorded in outputs is the referenced definition's `version_constraint`, while a definition carrying only an exact pin or a content version records no inherited version; conflicting supplied intent is rejected. AzureRM 5.5.0 accepts only `major.minor.*` member constraints at this boundary. Exact pins are preserved in the canonical output and rejected before resource creation because the provider schema cannot represent them without widening caller intent.

## Example

```hcl
module "catalogue" {
  source = "../catalogue"

  built_in_reference_directory = "${path.root}/catalogue/built-in"
  initiative_directory         = "${path.root}/catalogue/initiatives"
}

module "definitions" {
  source      = "../definitions"
  definitions = module.catalogue.definitions
}

module "initiatives" {
  source      = "./modules/initiatives"
  initiatives = module.catalogue.initiatives
  definitions = module.definitions.definitions
}
```

## Composition and validation

The output is the resource-output contract consumed by behaviour resolution. Each initiative preserves `parameters` for the source/Azure envelope and also exposes the same set-level schema as `parameter_schema`. Each member preserves its stable reference ID, target object, resolved policy-definition ID, member `parameter_schema`, parameter mappings and values, member effect and required metadata, source type and `created_by_module` provenance for keyed definitions, candidate `role_definition_ids`, capability and list declarations, governance data, inherited and selected version intent, and null-versus-empty values. Set-level and member-level schemas remain distinct. AzureRM receives the selected version exactly; exact pins are not widened. Direct IDs retain unknown capability, schema, role and source-provenance state unless the caller supplies those declarations through a canonical definition.

Validation is performed by attributable preconditions for envelope shape, required fields, reference uniqueness, source selection, direct IDs, scope compatibility, parameter schema and values, parameter mappings and collisions, group membership and version intent. Keyed member version intent must match the referenced definition, and direct member version selectors are mandatory and mutually exclusive. Malformed containers are guarded at the boundary before projection. Null optional containers remain unknown; explicit empty objects and lists remain verified empty.

### Parameter mapping rules

Parameter schemas accept Azure Policy types `String`, `Array`, `Object`, `Boolean`, `Integer`, `Float` and `DateTime` (case-insensitive). Supplied JSON values retain their native type: integers must be integral numbers, floats must be numbers, objects must be JSON objects, and dates must be valid ISO 8601/RFC 3339 date-times. An Array `allowedValues` list constrains each supplied/default array element; it does not require the complete array to equal one allowed item. Object values are checked as JSON objects, but their internal shape is not evaluated as a JSON Schema.

For a keyed definition, every required member parameter without a `defaultValue` needs a mapping, and mappings for undeclared member parameters fail. Literal mappings are checked against the member schema. A string mapping in the supported form `[parameters('name')]` binds to a declared initiative-set parameter and must have a compatible type; Integer may bind to Float. For a constrained member parameter, the set parameter must declare an allowed-value subset compatible with the member allowlist. Other bracket expressions are rejected deliberately; arbitrary Azure Policy expression evaluation is outside this module's contract. Direct policy-definition IDs have no verified member schema, so value/type compatibility remains unknown while mapping structure is still checked.

Both initiative resources explicitly depend on the blocking
`terraform_data.initiative_ingestion_contract`, so a supported targeted resource
operation also evaluates the guard. A targeted failure against an existing
managed initiative is still required to demonstrate that malformed input
cannot trigger a destructive change.

## Outputs

| Output | Contents |
| --- | --- |
| `initiatives` | Canonical initiative outputs keyed by stable catalogue key, including the created Azure initiative ID, set-level `parameter_schema` and resolved member references with each member's independent schema and capability context. |
| `initiative_ids` | Azure initiative IDs keyed by stable catalogue key. |
| `policy_definition_references` | Resolved initiative member references keyed by stable catalogue key. |

## Behaviour

The module uses `azurerm_policy_set_definition` for subscription-scoped initiatives and `azurerm_management_group_policy_set_definition` when an entry supplies `management_group_id`. Names default to the stable catalogue key when `name` is omitted. Definition scope must be compatible with initiative scope; direct subscription IDs are rejected for management-group initiatives and management-group IDs are rejected for subscription initiatives. Groups are mapped to Azure policy definition groups, and member group names are validated against the groups declared on the same initiative. An initiative version is catalogue metadata and is preserved for review; Azure resource versioning is carried by each member `version` argument.

## Compatibility

The module declares Terraform `>= 1.12.0` and AzureRM `>= 5.0.0, < 6.0.0`. Authorised regression evidence (implementation-run, self-reported) passes on Terraform 1.15.9 with AzureRM 5.5.0, on the Terraform 1.12.0 minimum, and on a pinned AzureRM 5.0.0 cell; exact commands and dates are recorded in the delivery handoff. AzureRM accepts member version constraints in `major.minor.*` form at this boundary; exact pins are retained as intent but rejected before resource creation because the provider schema cannot represent them without widening caller intent. Provider configuration stays with the caller; the module declares its `required_providers` constraint only.

## Validation

Run the non-test checks from the repository root:

```powershell
$env:NO_PROXY = '127.0.0.1,localhost,::1'
terraform fmt -check -recursive modules
terraform -chdir=modules/initiatives init -backend=false -input=false
terraform -chdir=modules/initiatives validate -no-color
terraform -chdir=tests/contracts/catalogue-pipeline init -backend=false -input=false
terraform -chdir=tests/contracts/catalogue-pipeline validate -no-color
terraform -chdir=tests/contracts/catalogue-pipeline console

git diff --check
```

`terraform validate` checks configuration and provider schema only. Negative contract assertions need plan or console evidence; `terraform test` requires project-owner authorisation, which was granted for the end-to-end architecture closure goal.
