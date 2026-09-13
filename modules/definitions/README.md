# Azure Policy Definitions Module

This module creates custom Azure Policy definitions and passes built-in policy definitions through the same canonical output contract.

It intentionally does not store or read policy source files. User-authored policy content belongs under the repository catalogue, for example `catalogue/custom-definitions` and `catalogue/built-in-references`. Source adapters and catalogue normalisation belong in `modules/catalogue` before this module. Downstream modules should consume the `definitions` output instead of caring whether a definition was custom or built-in.

## Example

```hcl
module "definitions" {
  source = "./modules/definitions"

  definitions = {
    allowed_locations = {
      source_type         = "built_in"
      policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c"
      display_name        = "Allowed locations"
      mode                = "Indexed"
      supported_effects   = ["Audit", "Deny", "Disabled"]
      version_constraint  = "1.*.*"
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

Each input key is the stable catalogue key. Custom definitions default their Azure name to that key when `name` is omitted. Built-in definitions must provide a stable Azure `policy_definition_id`.

Custom definitions are created with `azurerm_policy_definition`. If `management_group_id` is omitted, AzureRM creates the definition at subscription scope using the provider context. Built-in definitions are not looked up by this module, which keeps local validation and planning independent of Azure reads.

The `definitions` output is the hand-off to initiative, assignment and behaviour-resolution modules. It includes source type, ID, display metadata, mode, metadata, parameters, policy rule when supplied, role definition IDs, supported effects and version strategy.

Initiative composition is intentionally outside this module. A caller passes `module.definitions.definitions` to a separate `modules/initiatives` child module, where member references, parameter mappings, groups, version choices and collision rules are resolved.

Built-in definitions must declare either `version_constraint` or `pinned_version`. Azure built-in assignment versioning is enforced later by the assignment and behaviour-resolution modules, but the definitions contract records the intended version behaviour early so reviews can detect drift. Custom definitions must declare an exact `version` or `metadata.version`; the module synchronises it into metadata.

For Terraform module version pinning, consumers should pin the final published package address at the call site once the Registry namespace and package name are established. A release pin is separate from Azure Policy built-in version selection, which is represented by `version_constraint` or `pinned_version` in each built-in catalogue entry.

## Input and migration reference

The input is intentionally an unconstrained top-level map so different policy-rule, parameter and metadata shapes retain their native Terraform types. The module rejects unknown or source-inapplicable envelope fields, validates scalar/object/list types and Azure identity shapes, and leaves policy-language semantics to catalogue and downstream validation.

This README is the shared reference for the envelope. Future downstream modules should consume that canonical output rather than recreating these defaults or validations.

| Field | Default | Applies to | Notes |
| --- | --- | --- | --- |
| `source_type` | required | both | `custom` or `built_in` |
| `display_name` | required | both | 1-128 characters |
| `name` | catalogue key | both | Custom Azure name |
| `policy_definition_id` | null | built-in | Valid policy-definition resource ID |
| `description` | `""` | both | Maximum 512 characters |
| `mode` | `All` (custom), null (built-in) | both | Custom modes are validated and default to `All` because the created resource carries that value; a built-in mode should be supplied for accuracy, and an omitted or null built-in mode stays null (unknown) because this module does not look it up in Azure |
| `metadata` | `{}` | both | Preserved as native policy objects |
| `parameters` | `{}` (custom), null (built-in) | both | Preserved as native policy objects; an omitted or null built-in parameters object stays null (unknown) and an explicit `{}` stays a verified absence |
| `policy_rule` | null | custom | Required for custom definitions |
| `management_group_id` | null | custom | Provider subscription scope when omitted; a consumer-root deployment binding, never portable policy content |
| `role_definition_ids` | `[]` (custom), null (built-in) | both | Candidate roles, not grants or assignment decisions; custom absence becomes `[]` because the created resource carries it, while an omitted or null built-in list stays null (unknown) and an explicit `[]` stays a verified absence |
| `supported_effects` | null (unknown) | both | Catalogue capability data, not an assignment decision; absent stays null, explicit `[]` means verified absence |
| `supported_overrides` | null | both | List of override declaration objects, preserved verbatim for behaviour resolution |
| `selectors` | null | both | List of selector declaration objects, preserved verbatim for assignment and behaviour resolution |
| `non_compliance_messages` | null | both | Object of message declarations, preserved verbatim for assignment review tooling |
| `capabilities` | null | both | Object of capability declarations, preserved verbatim for behaviour resolution |
| `governance` | null | both | Object of ownership and traceability declarations, owned by the governance area |
| `version` | required via `version` or `metadata.version` | custom | Exact content version, synchronized into metadata |
| `version_constraint` / `pinned_version` | null | built-in | Mutually exclusive version intent |

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

The output contract contains `catalogue_key`, `source_type`, `id`, `name`, display fields, scope, policy content, candidate role IDs, supported effects, supported overrides, selectors, non-compliance messages, capabilities, governance declarations, custom content version, built-in version intent and `created_by_module`. Supported effects and the capability and governance fields are carried for both custom and built-in entries; absent or null declarations remain null (unknown) and an explicitly supplied empty collection is preserved as verified absence. `id`, `name`, `display_name`, `description` and `mode` for custom entries can be unknown until apply; built-in `id` and `name` are available at plan time, while built-in `mode`, `parameters` and `role_definition_ids` follow the unknown-state rule above. `custom_definition_ids` contains only created custom IDs and `built_in_definition_ids` contains only supplied references.

The runnable consumer example is [mixed input](examples/mixed-input/main.tf). It covers a custom definition at subscription scope, a built-in pass-through reference, and the shared output contract. Set the example's optional `management_group_id` variable to place the custom definition at management-group scope; the built-in entry still creates no resource.

Changing a custom key, effective name or management-group scope can replace an Azure definition and affect initiatives or assignments. Review the Terraform plan and downstream references deliberately. The module uses the provider's default replacement ordering and read timeout; it does not claim that either migration ordering is safe without a reviewed plan.

Migration note: the `definitions` output for built-in entries previously carried the defaults `mode = "All"`, `parameters = {}` and `role_definition_ids = []` whenever the capability was not declared. These now remain `null` (unknown) so missing capability information stays distinguishable from a verified absence. Explicitly supplied values and explicit empty declarations are unchanged, as are all custom-entry defaults. Consumers that read these built-in fields must treat `null` as unknown rather than as a real mode, an empty parameter schema or an absence of candidate roles.

The module configures no provider or backend. Callers own provider aliases and credentials. The child requirements are Terraform `>= 1.7.0` and AzureRM `>= 5.0.0, < 6.0.0`; Terraform 1.7 enables the mocked-provider contract tests. The local lock selection is validation evidence, not a consumer module pin.

## Tests

Run `terraform test` from this module directory to exercise mixed-input normalisation and invalid contract cases without Azure credentials. Tests mock AzureRM and do not create Azure resources. Live Azure acceptance testing remains a consumer-environment responsibility because it needs an isolated scope and explicitly authorised credentials.

CI integration is intentionally deferred. Run this module's formatting,
validation and mocked contract tests locally until repository-wide CI is added.
