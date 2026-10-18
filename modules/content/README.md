# Content module

`modules/content` is the Azure Policy content boundary. It creates custom policy definitions, passes built-in policy definitions through the same canonical output contract, resolves initiative members against those definitions and creates deterministic Azure Policy set definitions (initiatives). It owns the content state: definitions and initiatives are created here and nowhere else. Assignments, assignment identities, role grants and operations (remediations and exemptions) belong to other modules.

It intentionally does not store or read policy source files. User-authored policy content belongs under the repository catalogue, for example `catalogue/custom-definitions` and `catalogue/built-in-references`. Source adapters and catalogue normalisation belong in `modules/catalogue` before this module. Downstream modules consume the `definitions` and `initiatives` outputs instead of caring whether a definition was custom or built-in. Created definition IDs are read inside this module, so a caller passes the two canonical maps and never wires definition outputs into an initiative input.

## Example

Catalogue-fed wiring, the shape used by the composite root:

```hcl
module "catalogue" {
  source = "./modules/catalogue"

  custom_definition_directory  = "${path.root}/catalogue/custom-definitions"
  built_in_reference_directory = "${path.root}/catalogue/built-in-references"
  initiative_directory         = "${path.root}/catalogue/initiatives"
}

module "content" {
  source      = "./modules/content"
  definitions = module.catalogue.definitions
  initiatives = module.catalogue.initiatives
}
```

Inline definitions, without a catalogue:

```hcl
module "content" {
  source = "./modules/content"

  definitions = {
    allowed_locations = {
      source_type          = "built_in"
      policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c"
      display_name         = "Allowed locations"
      mode                 = "Indexed"
      supported_effects    = ["Audit", "Deny", "Disabled"]
      version_constraint   = "1.*.*"
    }

    require_cost_centre_tag = {
      source_type  = "custom"
      name         = "require-cost-centre-tag"
      display_name = "Require cost centre tag"
      description  = "Audit resources that do not have a cost centre tag."
      mode         = "Indexed"

      metadata = {
        category = "Tags"
        version  = "1.0.0"
      }

      parameters = {
        tagName = {
          type = "String"
          metadata = {
            displayName = "Tag name"
          }
          defaultValue = "costCentre"
        }
      }

      policy_rule = {
        if = {
          field  = "[concat('tags[', parameters('tagName'), ']')]"
          exists = "false"
        }
        then = {
          effect = "audit"
        }
      }

      supported_effects = ["Audit", "Disabled"]
    }
  }
}
```

## Contract

| Input | Type | Default | Behaviour |
| --- | --- | --- | --- |
| `definitions` | `any` | `{}` | Canonical definition objects keyed by stable catalogue key. Custom entries are created; built-in entries are passed through by stable Azure ID. Keyed initiative members resolve their `definition_key` against this map. |
| `initiatives` | `any` | `{}` | Canonical initiative objects keyed by stable catalogue key. Each entry may carry `catalogue_key`, `name`, `display_name`, `description`, `metadata`, `parameters`, `policy_definition_references`, `policy_definition_groups`, `management_group_id`, `governance` and `version`. |

Each input has its own container validation, so a null, list or scalar value for either fails at the variable boundary with a message that names the input. `definitions` is validated at the variable boundary for every rule in the envelope table below. `initiatives` is validated there for its container, entries and top-level field allowlist, and by the ingestion guard described under Composition and validation for the rest.

### Definitions

Each input key is the stable catalogue key. Custom definitions default their Azure name to that key when `name` is omitted. Built-in definitions must provide a stable Azure `policy_definition_id`.

Custom definitions are created with `azurerm_policy_definition`. If `management_group_id` is omitted, AzureRM creates the definition at subscription scope using the provider context. Two custom definitions with the same effective name in the same scope, compared case-insensitively, fail a precondition on the created definition. Built-in definitions are not looked up by this module, which keeps local validation and planning independent of Azure reads.

The `definitions` output is the hand-off to behaviour resolution and the source of the definition IDs that keyed initiative members resolve against inside this module. It includes source type, ID, display metadata, mode, metadata, parameters, policy rule when supplied, role definition IDs, supported effects and version strategy.

Initiative composition happens in this module from the same `definitions` input: member references, parameter mappings, groups, version choices and collision rules are resolved against the definitions created or referenced here (see Initiatives).

Built-in definitions must declare exactly one of `version_constraint` or `pinned_version`. Azure built-in assignment versioning is enforced later by the assignment and behaviour-resolution modules, but the definitions contract records the intended version behaviour early so reviews can detect drift. Custom definitions must declare an exact `version` or `metadata.version`; the module synchronises it into metadata.

For Terraform module version pinning, consumers should pin the final published package address at the call site once the Registry namespace and package name are established. A release pin is separate from Azure Policy built-in version selection, which is represented by `version_constraint` or `pinned_version` in each built-in catalogue entry.

### Initiatives

Each initiative member accepts `reference_id`, one of `definition_key` or `policy_definition_id`, optional `parameter_values`, optional `group_names`, optional `effect` and boolean `required` metadata, and optional `version_constraint` or `pinned_version`. Keyed members resolve through `definitions`; direct IDs pass through unchanged. A direct ID must be a built-in, subscription-scoped custom or management-group-scoped custom policy definition ID. A direct subscription ID is rejected in a management-group initiative and a direct management-group ID in a subscription initiative. A keyed member that references a custom definition must be stored at the initiative's own scope: the same management group, or both at subscription scope. A built-in definition has no scope and is accepted at either scope. This is the module's conservative rule, based on the definition-location rule in the Microsoft Learn article "Details of Azure Policy definition structure basics" (a definition stored in a subscription can be assigned only to resources in that subscription). This repository does not exercise it against Azure. Reference IDs and group names are unique case-insensitively. Direct members require exactly one version selector; keyed members may inherit the canonical definition intent, where the inherited version recorded in outputs is the referenced definition's `version_constraint`, while a definition carrying only an exact pin or a content version records no inherited version; conflicting supplied intent is rejected. A member version reaches AzureRM only in `major.minor.*` form. A `major.*.*` constraint or an exact pin on a member, supplied or inherited from the definition, is preserved in the canonical output and rejected before resource creation, because the provider schema cannot represent it without widening caller intent. A built-in definition that declares `major.*.*` or an exact pin therefore cannot be a keyed initiative member.

## Input and migration reference

The `definitions` input is intentionally an unconstrained top-level map so different policy-rule, parameter and metadata shapes retain their native Terraform types. The module rejects unknown or source-inapplicable envelope fields, validates scalar/object/list types and Azure identity shapes, and leaves policy-language semantics to catalogue and downstream validation.

This README is the shared reference for the envelope. Downstream modules should consume that canonical output rather than recreating these defaults or validations. Initiative member resolution happens inside this module; behaviour resolution and assignments consume its results.

| Field | Default | Applies to | Notes |
| --- | --- | --- | --- |
| `source_type` | required | both | `custom` or `built_in` |
| `display_name` | required | both | Non-blank string of at most 128 characters |
| `name` | catalogue key (custom), GUID of `policy_definition_id` (built-in) | both | Custom: the Azure name, 1 to 64 characters, without `<`, `>`, `%`, `&`, `:`, `\`, `?` or `/` and not ending in a space. Built-in: an optional label that is never sent to Azure |
| `policy_definition_id` | required (built-in), rejected (custom) | built-in | `/providers/Microsoft.Authorization/policyDefinitions/<GUID>` |
| `description` | `""` | both | Maximum 512 characters |
| `mode` | `All` (custom), null (built-in) | both | Custom modes are `All`, `Indexed`, `Microsoft.Kubernetes.Data`, `Microsoft.KeyVault.Data` and `Microsoft.Network.Data`, and default to `All` because the created resource carries that value. A built-in mode should be supplied for accuracy, and an omitted or null built-in mode stays null (unknown) because this module does not look it up in Azure |
| `metadata` | `{}` | both | Preserved as native policy objects |
| `parameters` | `{}` (custom), null (built-in) | both | Preserved as native policy objects; an omitted or null built-in parameters object stays null (unknown) and an explicit `{}` stays a verified absence |
| `policy_rule` | null | custom | An object, required for custom definitions and rejected for built-in ones |
| `management_group_id` | null | custom | `/providers/Microsoft.Management/managementGroups/<id>`. Provider subscription scope when omitted or blank, and rejected for built-in definitions. A consumer-root deployment binding, never portable policy content |
| `role_definition_ids` | `[]` (custom), null (built-in) | both | Candidate roles, not grants or assignment decisions; custom absence becomes `[]` because the created resource carries it, while an omitted or null built-in list stays null (unknown) and an explicit `[]` stays a verified absence. For custom entries the output list also includes `policy_rule.then.details.roleDefinitionIds`, deduplicated |
| `supported_effects` | null (unknown) | both | Catalogue capability data, not an assignment decision; absent stays null, explicit `[]` means verified absence |
| `supported_overrides` | null | both | List of override declaration objects, preserved verbatim for behaviour resolution |
| `selectors` | null | both | List of selector declaration objects, preserved verbatim for assignment and behaviour resolution |
| `non_compliance_messages` | null | both | Object of message declarations, preserved verbatim for assignment review tooling |
| `capabilities` | null | both | Object of capability declarations, preserved verbatim for behaviour resolution |
| `governance` | null | both | Object of ownership and traceability declarations, owned by the governance area |
| `version` | required via `version` or `metadata.version` | custom | Exact content version, synchronised into metadata; rejected for built-in definitions |
| `version_constraint` / `pinned_version` | null | built-in | Exactly one is required; both are rejected for custom definitions |

For built-in entries, `mode`, `parameters` and `role_definition_ids` follow
the same unknown-state rule as the capability declarations: absent or null
means unknown, an explicitly supplied empty value means verified absence, and
supplied values are preserved verbatim. Custom entries keep the `All`, `{}`
and `[]` resource defaults for these three fields because the created
policy-definition resource carries exactly those values. For
`supported_effects`, `supported_overrides`, `selectors`,
`non_compliance_messages`, `capabilities` and `governance`, absent or null
means unknown, an explicitly supplied empty collection means verified absence,
and supplied values are preserved verbatim. The module validates and preserves
the declarations rather than interpreting them; the catalogue module and
downstream consumers own the declaration semantics.

Built-in `version_constraint` accepts `major.*.*` or `major.minor.*` (for example, `1.*.*` or `1.2.*`). `pinned_version` is an exact numeric `major.minor.patch` version. Custom `version` and non-blank `metadata.version` use exact numeric `major.minor.patch` values and must agree when both are supplied.

The output contract contains `catalogue_key`, `source_type`, `id`, `name`, display fields, scope, policy content, candidate role IDs, supported effects, supported overrides, selectors, non-compliance messages, capabilities, governance declarations, custom content version, built-in version intent and `created_by_module`. Supported effects and the capability and governance fields are carried for both custom and built-in entries; absent or null declarations remain null (unknown) and an explicitly supplied empty collection is preserved as verified absence. For custom entries `id` is unknown until apply while the definition is planned for creation or replacement, and `name`, `display_name`, `description` and `mode` are known at plan time unless the input that sets them is unknown; built-in `id` and `name` are available at plan time, while built-in `mode`, `parameters` and `role_definition_ids` follow the unknown-state rule above. `custom_definition_ids` contains only created custom IDs and `built_in_definition_ids` contains only supplied references.

The runnable consumer example is [mixed input](examples/mixed-input/main.tf). It covers a custom definition at subscription scope, a built-in pass-through reference, and the shared output contract. Set the example's optional `management_group_id` variable to place the custom definition at management-group scope; the built-in entry still creates no resource.

Changing a custom key, effective name or management-group scope can replace an Azure definition and affect initiatives or assignments. Review the Terraform plan and downstream references deliberately. The module uses the provider's default replacement ordering and read timeout; it does not claim that either migration ordering is safe without a reviewed plan.

Migration note: the `definitions` output for built-in entries previously carried the defaults `mode = "All"`, `parameters = {}` and `role_definition_ids = []` whenever the capability was not declared. These now remain `null` (unknown) so missing capability information stays distinguishable from a verified absence. Explicitly supplied values and explicit empty declarations are unchanged, as are all custom-entry defaults. Consumers that read these built-in fields must treat `null` as unknown rather than as a real mode, an empty parameter schema or an absence of candidate roles.

## Composition and validation

The output is the resource-output contract consumed by behaviour resolution. Each initiative preserves `parameters` for the source/Azure envelope and also exposes the same set-level schema as `parameter_schema`. Each member preserves its stable reference ID, target object, resolved policy-definition ID, member `parameter_schema`, parameter mappings and values, member effect and required metadata, source type and `created_by_module` provenance for keyed definitions, candidate `role_definition_ids`, capability and list declarations, governance data, inherited and selected version intent, and null-versus-empty values. Set-level and member-level schemas remain distinct. AzureRM receives the selected version exactly; exact pins are not widened. Direct IDs retain unknown capability, schema, role and source-provenance state unless the caller supplies those declarations through a canonical definition.

Validation is performed by attributable preconditions for envelope shape, required fields, reference uniqueness, source selection, direct IDs, scope compatibility, parameter schema and values, parameter mappings and collisions, group membership and version intent. Keyed member version intent must match the referenced definition, and direct member version selectors are mandatory and mutually exclusive. Malformed containers are guarded at the boundary before projection. Null optional containers remain unknown; explicit empty objects and lists remain verified empty.

### Parameter mapping rules

Parameter schemas accept Azure Policy types `String`, `Array`, `Object`, `Boolean`, `Integer`, `Float` and `DateTime` (case-insensitive). Supplied JSON values retain their native type: integers must be integral numbers, floats must be numbers, objects must be JSON objects, and dates must be valid ISO 8601/RFC 3339 date-times. An Array `allowedValues` list constrains each supplied/default array element; it does not require the complete array to equal one allowed item. Object values are checked as JSON objects, but their internal shape is not evaluated as a JSON Schema.

For a keyed definition, every required member parameter without a `defaultValue` needs a mapping, and mappings for undeclared member parameters fail. Literal mappings are checked against the member schema. A string mapping in the supported form `[parameters('name')]` binds to a declared initiative-set parameter and must have a compatible type; Integer may bind to Float. For a constrained member parameter, the set parameter must declare an allowed-value subset compatible with the member allowlist. Other bracket expressions are rejected deliberately; arbitrary Azure Policy expression evaluation is outside this module's contract. Direct policy-definition IDs have no verified member schema, so value/type compatibility remains unknown while mapping structure is still checked.

Both initiative resources explicitly depend on the blocking
`terraform_data.initiative_ingestion_contract`, so a supported targeted resource
operation also evaluates the guard. The guard is a single resource without an
index. The module suite plans a targeted operation against an existing managed
initiative with malformed members, expects the guard to fail it and checks that
the initiative keeps its identity.

## Outputs

| Output | Contents |
| --- | --- |
| `definitions` | Canonical definition outputs keyed by stable catalogue key, for custom and built-in entries alike. This is the hand-off to behaviour resolution. |
| `custom_definition_ids` | Created custom definition IDs keyed by stable catalogue key. |
| `built_in_definition_ids` | Supplied built-in references keyed by stable catalogue key. |
| `initiatives` | Canonical initiative outputs keyed by stable catalogue key, including the created Azure initiative ID, set-level `parameter_schema` and resolved member references with each member's independent schema and capability context. This is the hand-off to behaviour resolution. |
| `initiative_ids` | Azure initiative IDs keyed by stable catalogue key. |
| `policy_definition_references` | Resolved initiative member references keyed by stable catalogue key. |

## Behaviour

The module uses `azurerm_policy_definition` for custom definitions, `azurerm_policy_set_definition` for subscription-scoped initiatives and `azurerm_management_group_policy_set_definition` when an entry supplies `management_group_id`. Names default to the stable catalogue key when `name` is omitted. Two initiatives with the same effective name in the same scope, compared case-insensitively, fail the guard. Scope compatibility between an initiative and its member definitions follows the rules under Initiatives. Groups are mapped to Azure policy definition groups, and member group names are validated against the groups declared on the same initiative. An initiative version is catalogue metadata and is preserved for review; Azure resource versioning is carried by each member `version` argument.

## Replacing the former modules

This module replaces the former `modules/definitions` and `modules/initiatives` modules, which no longer exist. The repository has no published release, so no alias module is provided. Output shapes are unchanged. Resource addresses move into this module:

| Former address | Address in this module |
| --- | --- |
| `module.<definitions>.azurerm_policy_definition.this[key]` | `module.<content>.azurerm_policy_definition.this[key]` |
| `module.<initiatives>.azurerm_policy_set_definition.subscription[key]` | `module.<content>.azurerm_policy_set_definition.subscription[key]` |
| `module.<initiatives>.azurerm_management_group_policy_set_definition.management_group[key]` | `module.<content>.azurerm_management_group_policy_set_definition.management_group[key]` |
| `module.<initiatives>.terraform_data.initiative_ingestion_contract` | `module.<content>.terraform_data.initiative_ingestion_contract` |

A caller with existing state moves each resource with a `moved` block or `terraform state mv` and confirms with a reviewed plan that nothing is replaced. The former initiatives call took the created definitions output, `definitions = module.<definitions>.definitions`. This module reads created definition IDs itself, so pass it the same canonical `definitions` and `initiatives` maps that fed the two former modules.

## Azure permissions

The content state creates policy definitions and initiatives and nothing else. The principal that applies it needs these operations at the scope that holds them, which is the subscription or the management group named by `management_group_id`:

| Resource | Operations |
| --- | --- |
| Custom policy definitions | `Microsoft.Authorization/policyDefinitions/read`, `write` and `delete` |
| Initiatives | `Microsoft.Authorization/policySetDefinitions/read`, `write` and `delete` |

Resource Policy Contributor (`36243c78-bf99-498c-9df9-86d9f8d28608`) is a built-in role that carries them. That role also carries policy assignment, exemption and remediation operations, so a state that must not hold those uses a custom role limited to the two rows above. Contributor is not enough, because it excludes `Microsoft.Authorization/*/Write`.

This state needs no role assignment, identity, policy assignment, exemption or remediation operation. Role contents were read from Microsoft Learn on 17 October 2026. The operations are the ones Microsoft documents for these resource types, and a run with a least-privileged principal has not confirmed that the AzureRM provider needs no others. The module never selects credentials. Provider configuration stays with the caller.

## Separation of duties

Content changes what a control means and never where it applies. Apply it first, from the catalogue at one commit, with a principal limited to the operations in the two rows under Azure permissions (a custom role). Role grants and assignments recompute resolution from the `definitions` and `initiatives` outputs, and operations consume the `resolved_assignments` output of the assignments state. None of them writes definitions. Because the package never reads remote state, the hand-off between states is explicit: pass the two envelopes through `terraform_remote_state` or a pipeline variable, and use the same catalogue commit in every state that recomputes resolution. A principal that can write definitions can change the effect of an existing assignment without touching it, so review definition changes before they are applied.

## Compatibility

The module declares Terraform `>= 1.12.0` and AzureRM `>= 5.0.0, < 6.0.0`. The repository's compatibility workflow runs the module suites on Terraform 1.12.0 with AzureRM 5.0.0 and on Terraform 1.15.9 with AzureRM 5.5.0, selecting each provider with a throwaway override file so `versions.tf` is never rewritten. Member version constraints reach AzureRM in `major.minor.*` form only, as described under Initiatives. The module configures no provider or backend. Callers own provider aliases and credentials, and the local lock selection is validation evidence, not a consumer module pin.

## Validation and tests

Run the non-test checks from the repository root:

```powershell
$env:NO_PROXY = '127.0.0.1,localhost,::1'
terraform fmt -check -recursive modules
terraform -chdir=modules/content init -backend=false -input=false
terraform -chdir=modules/content validate -no-color
terraform -chdir=tests/contracts/catalogue-pipeline init -backend=false -input=false
terraform -chdir=tests/contracts/catalogue-pipeline validate -no-color
```

`terraform validate` checks configuration and provider schema only. It does not evaluate variable validation rules or preconditions. Run `terraform test` from this module directory to exercise definition and initiative normalisation, parameter mapping and the invalid contract cases without Azure credentials. The suites mock AzureRM and do not create Azure resources, and the repository CI workflows run them. Live Azure acceptance testing remains a consumer-environment responsibility because it needs an isolated scope and explicitly authorised credentials.
