variable "initiative_directory" {
  description = "Optional flat directory containing top-level initiative JSON envelopes and optional <initiative>-parameters.json companions."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.initiative_directory == null || trimspace(var.initiative_directory) != ""
    error_message = "initiative_directory must be null or a non-blank directory path."
  }
}

variable "allow_empty_sources" {
  description = "Explicitly allow an opted-in catalogue source directory to be missing or empty. Disabled by default so a bad path cannot silently remove downstream entries."
  type        = bool
  default     = false
}

variable "custom_definition_directory" {
  description = "Optional flat directory containing custom-definition JSON envelopes and optional <policy>-parameters.json companions."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.custom_definition_directory == null || trimspace(var.custom_definition_directory) != ""
    error_message = "custom_definition_directory must be null or a non-blank directory path."
  }
}

variable "built_in_reference_directory" {
  description = "Optional flat directory containing built-in-reference JSON envelopes."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.built_in_reference_directory == null || trimspace(var.built_in_reference_directory) != ""
    error_message = "built_in_reference_directory must be null or a non-blank directory path."
  }
}

variable "native_definitions" {
  description = "Definition entries declared in native Terraform HCL, keyed by stable catalogue key. Entries use the definitions canonical envelope."
  type        = any
  default     = {}

  # Field semantics for native entries are enforced by the shared predicates in
  # definitions.tf through the definitions ingestion guard, because a variable
  # validation condition cannot reference locals (a local derived from the same
  # variable is a dependency cycle). Only cheap outer-shape checks stay here:
  # keyed object shape, non-blank keys, object values and the source-specific
  # raw-field allowlist.
  validation {
    condition     = can(keys(var.native_definitions)) && !can(tolist(var.native_definitions))
    error_message = "native_definitions must be a keyed object or map of definition objects."
  }

  validation {
    condition = try(alltrue([
      for key, definition in var.native_definitions :
      trimspace(key) != "" && can(keys(definition))
    ]), false)
    error_message = "Each native definition requires a non-blank catalogue key and an object value."
  }

  validation {
    condition = try(alltrue([
      for _, definition in var.native_definitions :
      length(setsubtract(toset(keys(definition)), toset([
        "source_type", "name", "policy_definition_id", "display_name", "description", "mode",
        "metadata", "parameters", "policy_rule", "management_group_id", "role_definition_ids",
        "supported_effects", "supported_overrides", "selectors", "non_compliance_messages",
        "capabilities", "governance", "version", "version_constraint", "pinned_version"
      ]))) == 0
    ]), false)
    error_message = "Native definitions may contain only fields from the canonical definitions contract."
  }
}

variable "native_initiatives" {
  description = "Initiative entries declared in native Terraform HCL, keyed by stable catalogue key. Members reference definition catalogue keys or explicit Azure policy definition IDs."
  type        = any
  default     = {}

  # Field semantics for native entries are enforced by the shared predicates in
  # initiatives.tf through the initiative ingestion guard
  # (terraform_data.initiative_ingestion_contract), because a variable
  # validation condition cannot reference locals (a local derived from the same
  # variable is a dependency cycle). Only cheap outer-shape checks stay here:
  # keyed object shape, non-blank keys, object values and the source-specific
  # raw-field allowlist.
  validation {
    condition     = can(keys(var.native_initiatives)) && !can(tolist(var.native_initiatives))
    error_message = "native_initiatives must be a keyed object or map of initiative objects."
  }

  validation {
    condition = try(alltrue([
      for key, initiative in var.native_initiatives :
      trimspace(key) != "" && can(keys(initiative))
    ]), false)
    error_message = "Each native initiative requires a non-blank catalogue key and an object value."
  }

  validation {
    condition = try(alltrue([
      for _, initiative in var.native_initiatives :
      length(setsubtract(toset(keys(initiative)), toset([
        "name", "display_name", "description", "metadata", "parameters",
        "policy_definition_references", "policy_definition_groups", "management_group_id", "governance", "version"
      ]))) == 0
    ]), false)
    error_message = "Native initiatives may contain only fields from the canonical initiatives contract."
  }
}
