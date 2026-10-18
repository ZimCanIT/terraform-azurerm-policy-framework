variable "definitions" {
  description = "Canonical policy definition entries keyed by stable catalogue key. Custom entries are created; built-in entries are passed through as references. Keyed initiative members resolve against the resulting definition IDs inside this module."
  type        = any
  default     = {}

  validation {
    condition     = can(keys(var.definitions)) && !can(tolist(var.definitions))
    error_message = "definitions must be a keyed object or map of definition objects with non-blank string keys."
  }

  validation {
    condition = try(alltrue([
      for key, _ in var.definitions :
      trimspace(key) != ""
    ]), false)
    error_message = "Each definition must have a non-blank catalogue key. Offending definition keys: ${try(join(", ", sort([for key, _ in var.definitions : key if !try(trimspace(key) != "", false)])), "<invalid input container>")}."
  }

  validation {
    condition = try(alltrue([
      for key, definition in var.definitions :
      can(keys(definition))
    ]), false)
    error_message = "Each definition must be an object. Offending definition keys: ${try(join(", ", sort([for key, definition in var.definitions : key if !try(can(keys(definition)), false)])), "<invalid input container>")}."
  }

  validation {
    condition = try(alltrue([
      for key, definition in var.definitions :
      length(setsubtract(toset(keys(definition)), toset([
        "source_type", "name", "policy_definition_id", "display_name", "description", "mode",
        "metadata", "parameters", "policy_rule", "management_group_id", "role_definition_ids",
        "supported_effects", "supported_overrides", "selectors", "non_compliance_messages",
        "capabilities", "governance", "version", "version_constraint", "pinned_version"
      ]))) == 0
    ]), false)
    error_message = "Definitions may contain only fields from the canonical definitions contract. Offending definition keys: ${try(join(", ", sort([for key, definition in var.definitions : key if !try(length(setsubtract(toset(keys(definition)), toset([
      "source_type", "name", "policy_definition_id", "display_name", "description", "mode",
      "metadata", "parameters", "policy_rule", "management_group_id", "role_definition_ids",
      "supported_effects", "supported_overrides", "selectors", "non_compliance_messages",
      "capabilities", "governance", "version", "version_constraint", "pinned_version"
    ]))) == 0, false)])), "<invalid input container>")}."
  }

  validation {
    condition = try(alltrue([
      for key, definition in var.definitions :
      can(regex("^\".*\"$", jsonencode(definition.source_type))) &&
      contains(["custom", "built_in"], definition.source_type)
    ]), false)
    error_message = "source_type must be the string custom or built_in. Offending definition keys: ${try(join(", ", sort([for key, definition in var.definitions : key if !try(
      can(regex("^\".*\"$", jsonencode(definition.source_type))) &&
      contains(["custom", "built_in"], definition.source_type),
    false)])), "<invalid input container>")}."
  }

  validation {
    condition = try(alltrue([
      for key, definition in var.definitions :
      can(regex("^\".*\"$", jsonencode(definition.display_name))) &&
      trimspace(definition.display_name) != "" &&
      length(definition.display_name) <= 128
    ]), false)
    error_message = "display_name must be a non-blank string of 128 characters or fewer. Offending definition keys: ${try(join(", ", sort([for key, definition in var.definitions : key if !try(
      can(regex("^\".*\"$", jsonencode(definition.display_name))) &&
      trimspace(definition.display_name) != "" &&
      length(definition.display_name) <= 128,
    false)])), "<invalid input container>")}."
  }

  validation {
    condition = try(alltrue([
      for key, definition in var.definitions :
      alltrue([
        try(definition.name == null, true) || can(regex("^\".*\"$", jsonencode(definition.name))),
        try(definition.description == null, true) || can(regex("^\".*\"$", jsonencode(definition.description))),
        try(definition.mode == null, true) || (can(regex("^\".*\"$", jsonencode(definition.mode))) && try(trimspace(definition.mode), "") != ""),
        try(definition.policy_definition_id == null, true) || can(regex("^\".*\"$", jsonencode(definition.policy_definition_id))),
        try(definition.management_group_id == null, true) || can(regex("^\".*\"$", jsonencode(definition.management_group_id))),
        try(definition.version == null, true) || can(regex("^\".*\"$", jsonencode(definition.version))),
        try(definition.version_constraint == null, true) || can(regex("^\".*\"$", jsonencode(definition.version_constraint))),
        try(definition.pinned_version == null, true) || can(regex("^\".*\"$", jsonencode(definition.pinned_version))),
        try(definition.metadata.version == null, true) || can(regex("^\".*\"$", jsonencode(definition.metadata.version)))
      ])
    ]), false)
    error_message = "Optional scalar envelope fields must be strings when supplied, and mode must not be blank. Offending definition keys: ${try(join(", ", sort([for key, definition in var.definitions : key if !try(alltrue([
      try(definition.name == null, true) || can(regex("^\".*\"$", jsonencode(definition.name))),
      try(definition.description == null, true) || can(regex("^\".*\"$", jsonencode(definition.description))),
      try(definition.mode == null, true) || (can(regex("^\".*\"$", jsonencode(definition.mode))) && try(trimspace(definition.mode), "") != ""),
      try(definition.policy_definition_id == null, true) || can(regex("^\".*\"$", jsonencode(definition.policy_definition_id))),
      try(definition.management_group_id == null, true) || can(regex("^\".*\"$", jsonencode(definition.management_group_id))),
      try(definition.version == null, true) || can(regex("^\".*\"$", jsonencode(definition.version))),
      try(definition.version_constraint == null, true) || can(regex("^\".*\"$", jsonencode(definition.version_constraint))),
      try(definition.pinned_version == null, true) || can(regex("^\".*\"$", jsonencode(definition.pinned_version))),
      try(definition.metadata.version == null, true) || can(regex("^\".*\"$", jsonencode(definition.metadata.version)))
    ]), false)])), "<invalid input container>")}."
  }

  validation {
    condition = try(alltrue([
      for key, definition in var.definitions :
      try(definition.description == null, true) || try(length(definition.description) <= 512, false)
    ]), false)
    error_message = "Descriptions must be 512 characters or fewer. Offending definition keys: ${try(join(", ", sort([for key, definition in var.definitions : key if !try(try(definition.description == null, true) || try(length(definition.description) <= 512, false), false)])), "<invalid input container>")}."
  }

  validation {
    condition = try(alltrue([
      for key, definition in var.definitions :
      try(definition.source_type != "custom", true) || try(
        length(try(trimspace(definition.name), "") != "" ? trimspace(definition.name) : key) <= 64,
        false
      )
    ]), false)
    error_message = "Custom effective names must be 64 characters or fewer. Offending definition keys: ${try(join(", ", sort([for key, definition in var.definitions : key if !try(
      try(definition.source_type != "custom", true) || try(
        length(try(trimspace(definition.name), "") != "" ? trimspace(definition.name) : key) <= 64,
        false
      ),
    false)])), "<invalid input container>")}."
  }

  validation {
    condition = try(alltrue([
      for key, definition in var.definitions :
      try(definition.source_type != "custom", true) || try(
        can(regex("^[^<>%&:\\\\?/]*[^<>%&:\\\\?/ ]+$", try(trimspace(definition.name), "") != "" ? trimspace(definition.name) : key)),
        false
      )
    ]), false)
    error_message = "Custom effective names cannot be empty, contain <, >, %, &, :, \\, ?, / or end with a space. Offending definition keys: ${try(join(", ", sort([for key, definition in var.definitions : key if !try(
      try(definition.source_type != "custom", true) || try(
        can(regex("^[^<>%&:\\\\?/]*[^<>%&:\\\\?/ ]+$", try(trimspace(definition.name), "") != "" ? trimspace(definition.name) : key)),
        false
      ),
    false)])), "<invalid input container>")}."
  }

  validation {
    condition = try(alltrue([
      for key, definition in var.definitions :
      (try(definition.source_type != "custom", true) || try(definition.policy_rule != null && can(keys(definition.policy_rule)), false))
    ]), false)
    error_message = "Custom definitions require a policy-rule object. Offending definition keys: ${try(join(", ", sort([for key, definition in var.definitions : key if !try(
      (try(definition.source_type != "custom", true) || try(definition.policy_rule != null && can(keys(definition.policy_rule)), false)),
    false)])), "<invalid input container>")}."
  }

  validation {
    condition = try(alltrue([
      for key, definition in var.definitions :
      (try(definition.metadata == null, true) || can(keys(definition.metadata))) &&
      (try(definition.parameters == null, true) || can(keys(definition.parameters)))
    ]), false)
    error_message = "Metadata and parameters, when supplied, must be objects. Offending definition keys: ${try(join(", ", sort([for key, definition in var.definitions : key if !try(
      (try(definition.metadata == null, true) || can(keys(definition.metadata))) &&
      (try(definition.parameters == null, true) || can(keys(definition.parameters))),
    false)])), "<invalid input container>")}."
  }

  validation {
    condition = try(alltrue([
      for key, definition in var.definitions :
      try(definition.source_type != "custom", true) || try(
        try(trimspace(definition.policy_definition_id), "") == "" &&
        try(trimspace(definition.version_constraint), "") == "" &&
        try(trimspace(definition.pinned_version), "") == "",
        false
      )
    ]), false)
    error_message = "Custom definitions cannot use built-in policy_definition_id, version_constraint or pinned_version fields. Offending definition keys: ${try(join(", ", sort([for key, definition in var.definitions : key if !try(
      try(definition.source_type != "custom", true) || try(
        try(trimspace(definition.policy_definition_id), "") == "" &&
        try(trimspace(definition.version_constraint), "") == "" &&
        try(trimspace(definition.pinned_version), "") == "",
        false
      ),
    false)])), "<invalid input container>")}."
  }

  validation {
    condition = try(alltrue([
      for key, definition in var.definitions :
      try(definition.source_type != "built_in", true) || try(
        try(definition.policy_rule, null) == null &&
        try(trimspace(definition.management_group_id), "") == "" &&
        try(definition.version, null) == null,
        false
      )
    ]), false)
    error_message = "Built-in definitions cannot use policy_rule, management_group_id or top-level version fields. Offending definition keys: ${try(join(", ", sort([for key, definition in var.definitions : key if !try(
      try(definition.source_type != "built_in", true) || try(
        try(definition.policy_rule, null) == null &&
        try(trimspace(definition.management_group_id), "") == "" &&
        try(definition.version, null) == null,
        false
      ),
    false)])), "<invalid input container>")}."
  }

  validation {
    condition = try(alltrue([
      for key, definition in var.definitions :
      try(definition.source_type != "custom", true) || try(definition.mode == null, true) || try(
        contains(["All", "Indexed", "Microsoft.Kubernetes.Data", "Microsoft.KeyVault.Data", "Microsoft.Network.Data"], definition.mode),
        false
      )
    ]), false)
    error_message = "Custom definition mode must be a supported Azure Policy custom-definition mode. Offending definition keys: ${try(join(", ", sort([for key, definition in var.definitions : key if !try(
      try(definition.source_type != "custom", true) || try(definition.mode == null, true) || try(
        contains(["All", "Indexed", "Microsoft.Kubernetes.Data", "Microsoft.KeyVault.Data", "Microsoft.Network.Data"], definition.mode),
        false
      ),
    false)])), "<invalid input container>")}."
  }

  validation {
    condition = try(alltrue([
      for key, definition in var.definitions :
      try(definition.source_type != "custom", true) || try(
        try(trimspace(definition.management_group_id), "") == "" ||
        can(regex(local.management_group_id_pattern, try(trimspace(definition.management_group_id), ""))),
        false
      )
    ]), false)
    error_message = "Custom management_group_id must be null, blank, or /providers/Microsoft.Management/managementGroups/<group-id>. Offending definition keys: ${try(join(", ", sort([for key, definition in var.definitions : key if !try(
      try(definition.source_type != "custom", true) || try(
        try(trimspace(definition.management_group_id), "") == "" ||
        can(regex(local.management_group_id_pattern, try(trimspace(definition.management_group_id), ""))),
        false
      ),
    false)])), "<invalid input container>")}."
  }

  validation {
    condition = try(alltrue([
      for key, definition in var.definitions :
      try(definition.source_type != "built_in", true) || try(
        can(regex(local.built_in_definition_id_pattern, trimspace(definition.policy_definition_id))),
        false
      )
    ]), false)
    error_message = "Built-in definitions require /providers/Microsoft.Authorization/policyDefinitions/<GUID> as policy_definition_id. Offending definition keys: ${try(join(", ", sort([for key, definition in var.definitions : key if !try(
      try(definition.source_type != "built_in", true) || try(
        can(regex(local.built_in_definition_id_pattern, trimspace(definition.policy_definition_id))),
        false
      ),
    false)])), "<invalid input container>")}."
  }

  validation {
    condition = try(alltrue([
      for key, definition in var.definitions :
      try(definition.source_type != "built_in", true) || (
        (try(trimspace(definition.version_constraint), "") != "" && try(trimspace(definition.pinned_version), "") == "") ||
        (try(trimspace(definition.version_constraint), "") == "" && try(trimspace(definition.pinned_version), "") != "")
      )
    ]), false)
    error_message = "Built-in definitions require exactly one non-blank version_constraint or pinned_version. Offending definition keys: ${try(join(", ", sort([for key, definition in var.definitions : key if !try(
      try(definition.source_type != "built_in", true) || (
        (try(trimspace(definition.version_constraint), "") != "" && try(trimspace(definition.pinned_version), "") == "") ||
        (try(trimspace(definition.version_constraint), "") == "" && try(trimspace(definition.pinned_version), "") != "")
      ),
    false)])), "<invalid input container>")}."
  }

  validation {
    condition = try(alltrue([
      for key, definition in var.definitions :
      try(definition.source_type != "built_in", true) || (
        (try(trimspace(definition.version_constraint), "") == "" || can(regex("^[0-9]+\\.([0-9]+|\\*)\\.\\*$", trimspace(definition.version_constraint)))) &&
        (try(trimspace(definition.pinned_version), "") == "" || can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", trimspace(definition.pinned_version))))
      )
    ]), false)
    error_message = "version_constraint must be major.*.* or major.minor.*; pinned_version must be an exact three-part numeric version. Offending definition keys: ${try(join(", ", sort([for key, definition in var.definitions : key if !try(
      try(definition.source_type != "built_in", true) || (
        (try(trimspace(definition.version_constraint), "") == "" || can(regex("^[0-9]+\\.([0-9]+|\\*)\\.\\*$", trimspace(definition.version_constraint)))) &&
        (try(trimspace(definition.pinned_version), "") == "" || can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", trimspace(definition.pinned_version))))
      ),
    false)])), "<invalid input container>")}."
  }

  validation {
    condition = try(alltrue([
      for key, definition in var.definitions :
      try(definition.source_type != "custom", true) || try(
        try(trimspace(definition.version), "") != "" || try(trimspace(definition.metadata.version), "") != "",
        false
      )
    ]), false)
    error_message = "Custom definitions require a version or metadata.version. Offending definition keys: ${try(join(", ", sort([for key, definition in var.definitions : key if !try(
      try(definition.source_type != "custom", true) || try(
        try(trimspace(definition.version), "") != "" || try(trimspace(definition.metadata.version), "") != "",
        false
      ),
    false)])), "<invalid input container>")}."
  }

  validation {
    condition = try(alltrue([
      for key, definition in var.definitions :
      try(definition.source_type != "custom", true) || try(
        !(try(trimspace(definition.version), "") != "" && try(trimspace(definition.metadata.version), "") != "" && trimspace(definition.version) != trimspace(definition.metadata.version)),
        false
      )
    ]), false)
    error_message = "Custom version and metadata.version must agree when both are supplied. Offending definition keys: ${try(join(", ", sort([for key, definition in var.definitions : key if !try(
      try(definition.source_type != "custom", true) || try(
        !(try(trimspace(definition.version), "") != "" && try(trimspace(definition.metadata.version), "") != "" && trimspace(definition.version) != trimspace(definition.metadata.version)),
        false
      ),
    false)])), "<invalid input container>")}."
  }

  validation {
    condition = try(alltrue([
      for key, definition in var.definitions :
      try(definition.source_type != "custom", true) || try(
        (try(definition.version == null, true) || try(trimspace(definition.version), "") == "" || can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", trimspace(definition.version)))) &&
        (try(definition.metadata.version == null, true) || try(trimspace(definition.metadata.version), "") == "" || can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", trimspace(definition.metadata.version)))),
        false
      )
    ]), false)
    error_message = "Custom version and metadata.version must be exact major.minor.patch values when supplied. Offending definition keys: ${try(join(", ", sort([for key, definition in var.definitions : key if !try(
      try(definition.source_type != "custom", true) || try(
        (try(definition.version == null, true) || try(trimspace(definition.version), "") == "" || can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", trimspace(definition.version)))) &&
        (try(definition.metadata.version == null, true) || try(trimspace(definition.metadata.version), "") == "" || can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", trimspace(definition.metadata.version)))),
        false
      ),
    false)])), "<invalid input container>")}."
  }

  validation {
    condition = try(alltrue([
      for key, definition in var.definitions :
      (try(definition.role_definition_ids == null, true) || try(alltrue([
        for id in tolist(definition.role_definition_ids) :
        can(regex("^\".*\"$", jsonencode(id))) && trimspace(id) != ""
      ]), false)) &&
      (try(definition.supported_effects == null, true) || (
        !can(keys(definition.supported_effects)) &&
        try(alltrue([
          for effect in definition.supported_effects :
          can(regex("^\".*\"$", jsonencode(effect))) && trimspace(effect) != ""
        ]), false)
      )) &&
      (try(definition.policy_rule.then.details.roleDefinitionIds == null, true) || try(alltrue([
        for id in tolist(definition.policy_rule.then.details.roleDefinitionIds) :
        can(regex("^\".*\"$", jsonencode(id))) && trimspace(id) != ""
      ]), false))
    ]), false)
    error_message = "role_definition_ids, supported_effects and policy_rule.then.details.roleDefinitionIds must be lists of non-blank strings when supplied. Offending definition keys: ${try(join(", ", sort([for key, definition in var.definitions : key if !try(
      (try(definition.role_definition_ids == null, true) || try(alltrue([
        for id in tolist(definition.role_definition_ids) :
        can(regex("^\".*\"$", jsonencode(id))) && trimspace(id) != ""
      ]), false)) &&
      (try(definition.supported_effects == null, true) || (
        !can(keys(definition.supported_effects)) &&
        try(alltrue([
          for effect in definition.supported_effects :
          can(regex("^\".*\"$", jsonencode(effect))) && trimspace(effect) != ""
        ]), false)
      )) &&
      (try(definition.policy_rule.then.details.roleDefinitionIds == null, true) || try(alltrue([
        for id in tolist(definition.policy_rule.then.details.roleDefinitionIds) :
        can(regex("^\".*\"$", jsonencode(id))) && trimspace(id) != ""
      ]), false)),
    false)])), "<invalid input container>")}."
  }

  validation {
    condition = try(alltrue([
      for key, definition in var.definitions :
      (try(definition.supported_overrides == null, true) || try(
        !can(keys(definition.supported_overrides)) &&
        alltrue([
          for override in definition.supported_overrides :
          can(keys(override))
        ]),
        false
      )) &&
      (try(definition.selectors == null, true) || try(
        !can(keys(definition.selectors)) &&
        alltrue([
          for selector in definition.selectors :
          can(keys(selector))
        ]),
        false
      ))
    ]), false)
    error_message = "supported_overrides and selectors must be lists of objects. Offending definition keys: ${try(join(", ", sort([for key, definition in var.definitions : key if !try(
      (try(definition.supported_overrides == null, true) || try(
        !can(keys(definition.supported_overrides)) &&
        alltrue([
          for override in definition.supported_overrides :
          can(keys(override))
        ]),
        false
      )) &&
      (try(definition.selectors == null, true) || try(
        !can(keys(definition.selectors)) &&
        alltrue([
          for selector in definition.selectors :
          can(keys(selector))
        ]),
        false
      )),
    false)])), "<invalid input container>")}."
  }

  validation {
    condition = try(alltrue([
      for key, definition in var.definitions :
      (try(definition.non_compliance_messages == null, true) || can(keys(definition.non_compliance_messages))) &&
      (try(definition.capabilities == null, true) || can(keys(definition.capabilities))) &&
      (try(definition.governance == null, true) || can(keys(definition.governance)))
    ]), false)
    error_message = "non_compliance_messages, capabilities and governance must be objects when supplied. Offending definition keys: ${try(join(", ", sort([for key, definition in var.definitions : key if !try(
      (try(definition.non_compliance_messages == null, true) || can(keys(definition.non_compliance_messages))) &&
      (try(definition.capabilities == null, true) || can(keys(definition.capabilities))) &&
      (try(definition.governance == null, true) || can(keys(definition.governance))),
    false)])), "<invalid input container>")}."
  }
}

variable "initiatives" {
  description = "Canonical policy initiative entries keyed by stable catalogue key. Entries come from modules/catalogue and preserve member references, groups, parameters, governance and version intent. Keyed members resolve against the definitions input."
  type        = any
  default     = {}

  validation {
    condition     = can(keys(var.initiatives)) && !can(tolist(var.initiatives))
    error_message = "initiatives must be a keyed object or map of initiative objects."
  }

  validation {
    condition = try(alltrue([
      for key, _ in var.initiatives :
      trimspace(key) != ""
    ]), false)
    error_message = "Each initiative must have a non-blank catalogue key. Offending initiative keys: ${try(join(", ", sort([for key, _ in var.initiatives : key if !try(trimspace(key) != "", false)])), "<invalid input container>")}."
  }

  validation {
    condition = try(alltrue([
      for key, initiative in var.initiatives :
      can(keys(initiative))
    ]), false)
    error_message = "Each initiative must have an object value. Offending initiative keys: ${try(join(", ", sort([for key, initiative in var.initiatives : key if !try(can(keys(initiative)), false)])), "<invalid input container>")}."
  }

  validation {
    condition = try(alltrue([
      for key, initiative in var.initiatives :
      length(setsubtract(toset(keys(initiative)), toset([
        "catalogue_key", "name", "display_name", "description", "metadata", "parameters",
        "policy_definition_references", "policy_definition_groups", "management_group_id", "governance", "version"
      ]))) == 0
    ]), false)
    error_message = "Initiatives may contain only fields from the canonical initiatives contract. Offending initiative keys: ${try(join(", ", sort([for key, initiative in var.initiatives : key if !try(length(setsubtract(toset(keys(initiative)), toset([
      "catalogue_key", "name", "display_name", "description", "metadata", "parameters",
      "policy_definition_references", "policy_definition_groups", "management_group_id", "governance", "version"
    ]))) == 0, false)])), "<invalid input container>")}."
  }
}
