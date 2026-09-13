# Catalogue module

`catalogue` is the source-adapter boundary for the framework. It accepts
native Terraform HCL and constrained JSON policy-library inputs, then produces
canonical definition entries for `modules/definitions` and canonical
initiative entries for the future `modules/initiatives`. It does not configure
providers, perform Azure lookups or create Azure resources.

Catalogue is the only file-reading boundary in the package. It declares and
preserves capability and governance data but does not make behaviour, version,
role or remediation decisions. The source-envelope contract below is
self-contained and matches the `hcl.tf`, `json.tf` and `initiatives.tf`
adapters together with the shared definition model in `definitions.tf`.

## Source-envelope contract

The same canonical envelope requirements apply to native HCL and JSON input.
Catalogue validates required fields, source-type field exclusivity and container
shapes for native HCL and JSON definition entries and for initiatives.
`modules/definitions` still owns deployment validation and defaulting,
including Azure identity rules and provider-facing normalisation.

| Envelope | Required | Version intent |
| --- | --- | --- |
| Custom definition | `catalogue_key`, `display_name`, `policy_rule` | An exact `major.minor.patch` version in `version` or `metadata.version`; when both are supplied they must agree. |
| Built-in reference | `catalogue_key`, `display_name`, a root built-in Azure `policy_definition_id` | Exactly one of `version_constraint` or `pinned_version`. |
| Initiative | `catalogue_key`, `display_name`, at least one well-shaped `policy_definition_references` member | Keyed members may omit version intent and inherit it downstream; direct policy-definition IDs require exactly one of `version_constraint` or `pinned_version`. |

Optional definition fields are `name`, `description`, `mode`, `metadata`,
`parameters`, `role_definition_ids`, `management_group_id` (custom only),
`supported_effects`, `supported_overrides`, `selectors`,
`non_compliance_messages`, `capabilities` and `governance`. Optional initiative
fields are `name`, `description`, `metadata`, `parameters`,
`policy_definition_groups`, `management_group_id`, `governance` and `version`
(an exact `major.minor.patch` when supplied).

Each initiative member (`policy_definition_references`) accepts these fields:

| Field | Required | Rules |
| --- | --- | --- |
| `reference_id` | Yes | Non-blank and unique case-insensitively within the initiative. |
| `definition_key` | One of | Stable catalogue key of a definition entry. Keyed members may omit version intent and inherit it downstream. |
| `policy_definition_id` | One of | Root built-in, subscription-scoped custom or management-group-scoped custom policy-definition ID. Direct IDs require exactly one version intent. |
| `parameter_values` | No | Object of parameter values passed to the member. |
| `group_names` | No | List of non-blank names that must match declared groups, unique case-insensitively within the member. |
| `version_constraint` | No | `major.*.*` or `major.minor.*`; mutually exclusive with `pinned_version`. |
| `pinned_version` | No | Exact `major.minor.patch`; mutually exclusive with `version_constraint`. |

Each initiative group (`policy_definition_groups`) accepts `name` and
`display_name` (both required non-blank; `name` unique case-insensitively within
the initiative) plus optional `description` (string) and `metadata` (object).

Key and source-type conventions differ by authoring format. JSON envelopes
require an inline `catalogue_key` and the adapter sets `source_type` from the
source directory or envelope. Native HCL values use the outer map key as the
stable catalogue key, must not supply an inline `catalogue_key`, and native
definitions additionally require `source_type = "custom"` or `"built_in"` with
the corresponding required fields. Definition keys must be unique
case-insensitively across all definition sources, and initiative keys likewise
across all initiative sources.

Capability and governance declarations are optional. `supported_effects` is a
list of non-blank strings; `supported_overrides` and `selectors` are lists of
objects; `non_compliance_messages`, `capabilities` and `governance` are objects.
Catalogue checks these container shapes only and preserves the values verbatim,
including `false` values and empty nested objects.

For every optional declaration, absent or null means unknown: the downstream
consumer cannot assume the entry lacks the declaration. An explicitly supplied
empty collection means verified absence, for example `supported_overrides = []`.
Catalogue never substitutes a default for an absent declaration.

`management_group_id` is a deployment binding, not portable policy content.
Consumer roots supply it, typically from environment configuration. Catalogue
preserves it verbatim and performs no scope or hierarchy lookup. Portable
catalogue content must never embed a real tenant ID; examples use synthetic
values such as
`/providers/Microsoft.Management/managementGroups/example-platform`.

Companion rules:

- A custom definition or initiative may use an optional
  `<name>-parameters.json` companion for its structured Azure Policy
  parameters object.
- An orphan companion without a matching envelope is rejected.
- A companion and a non-null inline `parameters` object for the same entry are
  rejected; remove one source.
- Companion values keep their JSON types, including numbers, booleans, arrays
  and nested objects.

Flat-directory rules:

- Each source directory is flat and may contain only top-level `.json` files.
- Missing or empty opted-in directories fail with a deliberate diagnostic
  unless `allow_empty_sources = true`.
- Nested files and unsupported extensions are rejected.

Malformed JSON, non-object JSON containers, malformed member or group records
and duplicate keys fail through deliberate validation rather than raw
expression errors.

## Inputs

| Input | Type | Behaviour |
| --- | --- | --- |
| `native_definitions` | `any` | Optional keyed object of definition-shaped HCL values. The key is the stable catalogue key. |
| `native_initiatives` | `any` | Optional keyed object of initiative-shaped HCL values. The key is the stable initiative key. |
| `custom_definition_directory` | `string` | Optional flat directory of custom-definition JSON envelopes and optional `<name>-parameters.json` companions. |
| `built_in_reference_directory` | `string` | Optional flat directory of built-in-reference JSON envelopes. |
| `initiative_directory` | `string` | Optional flat directory of initiative JSON envelopes and optional `<name>-parameters.json` companions. |
| `allow_empty_sources` | `bool` | Defaults to `false`; permits an opted-in source directory to be missing or empty when explicitly set to `true`. |

The HCL variables use `any` at the source boundary so policy rules, parameter
schemas and metadata retain heterogeneous Terraform values.

## Native HCL

Use stable catalogue keys and the definitions canonical envelope. A deployment
binding such as `management_group_id` is supplied by the consumer root:

```hcl
module "catalogue" {
  source = "../../modules/catalogue"

  native_definitions = {
    allowed_locations = {
      source_type          = "built_in"
      display_name         = "Allowed locations"
      policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c"
      version_constraint   = "1.*.*"
      supported_effects    = ["Audit", "Deny", "Disabled"]

      governance = {
        requirement_id = "REQ-LOCATION-001"
        owner          = "platform-team"
      }
    }

    require_cost_centre_tag = {
      source_type         = "custom"
      display_name        = "Require cost centre tag"
      management_group_id = var.management_group_id
      version             = "1.0.0"

      policy_rule = {
        if = {
          field  = "tags['costCentre']"
          exists = "false"
        }
        then = {
          effect = "audit"
        }
      }
    }
  }
}

module "definitions" {
  source      = "../../modules/definitions"
  definitions = module.catalogue.definitions
}
```

`modules/definitions` owns deployment validation and defaulting. Catalogue
only checks the source envelope and preserves structured values.

## JSON library

JSON source directories are opt-in and are read only by this module:

```hcl
module "catalogue" {
  source = "../../modules/catalogue"

  custom_definition_directory  = "${path.root}/catalogue/custom-definitions"
  initiative_directory         = "${path.root}/catalogue/initiatives"
  built_in_reference_directory = "${path.root}/catalogue/built-in-references"
}
```

The source-envelope contract above defines the directory, companion and
envelope rules that apply to every JSON source directory.

## Outputs

| Output | Contents |
| --- | --- |
| `definitions` | Canonical definition entries keyed by stable catalogue key, ready to pass directly to `modules/definitions`. |
| `initiatives` | Canonical initiative envelopes keyed by stable catalogue key, preserved for the future `modules/initiatives` resource module. |
| `source_summary` | Non-sensitive provenance with exactly one record per actual entry (`catalogue_key`, `source_type`, `authoring_format`, `source_path`, `companion_source_path`). Companions are attached to their parent record, never emitted separately. |

`definitions` excludes catalogue file paths and ingestion mechanics, so it can
be passed directly to `modules/definitions`. `initiatives` preserves stable
initiative keys and member definition references; catalogue does not implement
the initiative resource lifecycle.

Deployment scope values such as management-group IDs are supplied by consumer
roots. Portable catalogue content must not embed a real tenant ID.

## Examples

Runnable, provider-free examples with synthetic values:

- [hcl](examples/hcl/README.md): native HCL definitions and an initiative.
- [json](examples/json/README.md): a JSON library with a parameter companion
  and a built-in reference.
- [mixed](examples/mixed/README.md): native HCL plus a JSON definition
  directory in one call.

Each example validates with backend-disabled initialisation:

```powershell
terraform -chdir=modules/catalogue/examples/hcl init -backend=false -input=false
terraform -chdir=modules/catalogue/examples/hcl validate -no-color
```

## Compatibility

Catalogue requires Terraform `>= 1.12.0`; the source adapters rely on nullable
validation guards and validation short-circuiting introduced in that release.
Only Terraform 1.15.9 has been exercised locally, so the minimum is declared
but untested at that version. `modules/definitions` keeps its independent
Terraform `>= 1.7.0` and AzureRM `>= 5.0.0, < 6.0.0` constraint.

## Tests

Run the offline module and contract suites from the repository root:

```powershell
terraform fmt -check -recursive modules/catalogue
terraform -chdir=modules/catalogue init -backend=false -input=false
terraform -chdir=modules/catalogue validate -no-color
terraform -chdir=modules/catalogue test

terraform -chdir=tests/contracts/catalogue init -backend=false -input=false
terraform -chdir=tests/contracts/catalogue test

terraform -chdir=tests/contracts/catalogue-to-definitions init -backend=false -input=false
terraform -chdir=tests/contracts/catalogue-to-definitions test
```

The tests cover native HCL preservation, JSON normalisation, source-directory
and companion rules, malformed and non-object containers, companion type
preservation, HCL/JSON parity, initiative member and group validation,
provenance accuracy, bulk ingestion and the provider-free emission of the
definitions contract envelope. `tests/contracts/catalogue-to-definitions`
wires catalogue into `modules/definitions` with a mocked AzureRM provider.
