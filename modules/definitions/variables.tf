variable "definitions" {
  description = "Canonical policy definition entries keyed by stable catalogue key. Custom entries are created; built-in entries are passed through as references."
  type        = any
  default     = {}

  validation {
    condition     = can(keys(var.definitions)) && !can(tolist(var.definitions))
    error_message = "definitions must be a keyed object or map of definition objects with non-blank string keys."
  }

  validation {
    condition = try(alltrue([
      for key, definition in var.definitions :
      trimspace(key) != "" && can(keys(definition))
    ]), false)
    error_message = "Each definition must be an object with a non-blank catalogue key."
  }

  validation {
    condition = try(alltrue([
      for _, definition in var.definitions :
      length(setsubtract(toset(keys(definition)), toset([
        "source_type", "name", "policy_definition_id", "display_name", "description", "mode",
        "metadata", "parameters", "policy_rule", "management_group_id", "role_definition_ids",
        "supported_effects", "version", "version_constraint", "pinned_version"
      ]))) == 0
    ]), false)
    error_message = "Definitions may contain only fields from the canonical definitions contract."
  }

  validation {
    condition = try(alltrue([
      for _, definition in var.definitions :
      can(regex("^\".*\"$", jsonencode(definition.source_type))) &&
      contains(["custom", "built_in"], definition.source_type) &&
      can(regex("^\".*\"$", jsonencode(definition.display_name))) &&
      trimspace(definition.display_name) != "" &&
      length(definition.display_name) <= 128 &&
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
    error_message = "Required and optional scalar envelope fields must be non-blank strings when supplied."
  }

  validation {
    condition = try(alltrue([
      for _, definition in var.definitions :
      try(definition.description == null, true) || try(length(definition.description) <= 512, false)
    ]), false)
    error_message = "Descriptions must be 512 characters or fewer."
  }

  validation {
    condition = try(alltrue([
      for key, definition in var.definitions :
      try(definition.source_type != "custom", true) || try(
        length(try(trimspace(definition.name), "") != "" ? trimspace(definition.name) : key) <= 64 &&
        can(regex("^[^<>%&:\\?/]*[^<>%&:\\?/ ]+$", try(trimspace(definition.name), "") != "" ? trimspace(definition.name) : key)),
        false
      )
    ]), false)
    error_message = "Custom effective names must be 64 characters or fewer and cannot contain <, >, %, &, :, \\, ?, / or end with a space."
  }

  validation {
    condition = try(alltrue([
      for _, definition in var.definitions :
      (try(definition.source_type != "custom", true) || try(definition.policy_rule != null && can(keys(definition.policy_rule)), false)) &&
      (try(definition.metadata == null, true) || can(keys(definition.metadata))) &&
      (try(definition.parameters == null, true) || can(keys(definition.parameters)))
    ]), false)
    error_message = "Custom definitions require a policy-rule object; metadata and parameters, when supplied, must be objects."
  }

  validation {
    condition = try(alltrue([
      for _, definition in var.definitions :
      try(definition.source_type != "custom", true) || try(
        try(trimspace(definition.policy_definition_id), "") == "" &&
        try(trimspace(definition.version_constraint), "") == "" &&
        try(trimspace(definition.pinned_version), "") == "",
        false
      )
    ]), false)
    error_message = "Custom definitions cannot use built-in policy_definition_id, version_constraint or pinned_version fields."
  }

  validation {
    condition = try(alltrue([
      for _, definition in var.definitions :
      try(definition.source_type != "built_in", true) || try(
        try(definition.policy_rule, null) == null &&
        try(trimspace(definition.management_group_id), "") == "" &&
        try(definition.version, null) == null,
        false
      )
    ]), false)
    error_message = "Built-in definitions cannot use policy_rule, management_group_id or top-level version fields."
  }

  validation {
    condition = try(alltrue([
      for _, definition in var.definitions :
      try(definition.source_type != "custom", true) || try(definition.mode == null, true) || try(
        contains(["All", "Indexed", "Microsoft.Kubernetes.Data", "Microsoft.KeyVault.Data", "Microsoft.Network.Data"], definition.mode),
        false
      )
    ]), false)
    error_message = "Custom definition mode must be a supported Azure Policy custom-definition mode."
  }

  validation {
    condition = try(alltrue([
      for _, definition in var.definitions :
      try(definition.source_type != "custom", true) || try(
        try(trimspace(definition.management_group_id), "") == "" ||
        can(regex("^/providers/Microsoft\\.Management/managementGroups/[^/]+$", try(trimspace(definition.management_group_id), ""))),
        false
      )
    ]), false)
    error_message = "Custom management_group_id must be null, blank, or /providers/Microsoft.Management/managementGroups/<group-id>."
  }

  validation {
    condition = try(alltrue([
      for _, definition in var.definitions :
      try(definition.source_type != "built_in", true) || try(
        can(regex("^/providers/Microsoft\\.Authorization/policyDefinitions/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", trimspace(definition.policy_definition_id))),
        false
      )
    ]), false)
    error_message = "Built-in definitions require /providers/Microsoft.Authorization/policyDefinitions/<GUID> as policy_definition_id."
  }

  validation {
    condition = try(alltrue([
      for _, definition in var.definitions :
      try(definition.source_type != "built_in", true) || (
        (try(trimspace(definition.version_constraint), "") != "" && try(trimspace(definition.pinned_version), "") == "") ||
        (try(trimspace(definition.version_constraint), "") == "" && try(trimspace(definition.pinned_version), "") != "")
      )
    ]), false)
    error_message = "Built-in definitions require exactly one non-blank version_constraint or pinned_version."
  }

  validation {
    condition = try(alltrue([
      for _, definition in var.definitions :
      try(definition.source_type != "built_in", true) || (
        (try(trimspace(definition.version_constraint), "") == "" || can(regex("^[0-9]+\\.([0-9]+|\\*)\\.\\*$", trimspace(definition.version_constraint)))) &&
        (try(trimspace(definition.pinned_version), "") == "" || can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", trimspace(definition.pinned_version))))
      )
    ]), false)
    error_message = "version_constraint must be major.*.* or major.minor.*; pinned_version must be an exact three-part numeric version."
  }

  validation {
    condition = try(alltrue([
      for _, definition in var.definitions :
      try(definition.source_type != "custom", true) || (
        (try(trimspace(definition.version), "") != "" || try(trimspace(definition.metadata.version), "") != "") &&
        !(try(trimspace(definition.version), "") != "" && try(trimspace(definition.metadata.version), "") != "" && trimspace(definition.version) != trimspace(definition.metadata.version)) &&
        (try(definition.version == null, true) || try(trimspace(definition.version), "") == "" || can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", trimspace(definition.version)))) &&
        (try(definition.metadata.version == null, true) || try(trimspace(definition.metadata.version), "") == "" || can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", trimspace(definition.metadata.version))))
      )
    ]), false)
    error_message = "Custom definitions require an exact version or metadata.version; both must agree when supplied."
  }

  validation {
    condition = try(alltrue([
      for _, definition in var.definitions :
      (try(definition.role_definition_ids == null, true) || try(alltrue([
        for id in tolist(definition.role_definition_ids) :
        can(regex("^\".*\"$", jsonencode(id))) && trimspace(id) != ""
      ]), false)) &&
      (try(definition.supported_effects == null, true) || try(alltrue([
        for effect in tolist(definition.supported_effects) :
        can(regex("^\".*\"$", jsonencode(effect))) && trimspace(effect) != ""
      ]), false)) &&
      (try(definition.policy_rule.then.details.roleDefinitionIds == null, true) || try(alltrue([
        for id in tolist(definition.policy_rule.then.details.roleDefinitionIds) :
        can(regex("^\".*\"$", jsonencode(id))) && trimspace(id) != ""
      ]), false))
    ]), false)
    error_message = "role_definition_ids, supported_effects and policy_rule.then.details.roleDefinitionIds must be lists of non-blank strings when supplied."
  }
}
