variable "initiatives" {
  description = "Canonical policy initiative entries keyed by stable catalogue key. Entries come from modules/catalogue and preserve member references, groups, parameters, governance and version intent."
  type        = any
  default     = {}

  validation {
    condition     = can(keys(var.initiatives)) && !can(tolist(var.initiatives))
    error_message = "initiatives must be a keyed object or map of initiative objects."
  }

  validation {
    condition = try(alltrue([
      for key, initiative in var.initiatives :
      trimspace(key) != "" && can(keys(initiative))
    ]), false)
    error_message = "Each initiative must have a non-blank catalogue key and an object value."
  }

  validation {
    condition = try(alltrue([
      for _, initiative in var.initiatives :
      length(setsubtract(toset(keys(initiative)), toset([
        "catalogue_key", "name", "display_name", "description", "metadata", "parameters",
        "policy_definition_references", "policy_definition_groups", "management_group_id", "governance", "version"
      ]))) == 0
    ]), false)
    error_message = "Initiatives may contain only fields from the canonical initiatives contract."
  }
}

variable "definitions" {
  description = "Canonical policy definition entries keyed by stable catalogue key. Entries come from modules/definitions and provide the resolved definition IDs used by keyed initiative members."
  type        = any
  default     = {}

  validation {
    condition     = can(keys(var.definitions)) && !can(tolist(var.definitions))
    error_message = "definitions must be a keyed object or map of definition objects."
  }

  validation {
    condition = try(alltrue([
      for key, definition in var.definitions :
      trimspace(key) != "" && can(keys(definition))
    ]), false)
    error_message = "Each definition must have a non-blank catalogue key and an object value."
  }

  validation {
    condition = try(alltrue([
      for _, definition in var.definitions :
      length(setsubtract(toset(keys(definition)), toset([
        "catalogue_key", "source_type", "id", "name", "display_name", "description", "mode",
        "metadata", "parameters", "policy_rule", "role_definition_ids", "supported_effects",
        "supported_overrides", "selectors", "non_compliance_messages", "capabilities", "governance",
        "version", "version_constraint", "pinned_version", "management_group_id", "created_by_module"
      ]))) == 0
    ]), false)
    error_message = "Definitions may contain only fields from the canonical definitions output contract."
  }

  validation {
    condition = try(alltrue([
      for _, definition in var.definitions :
      can(regex("^\\\".*\\\"$", jsonencode(definition.id))) && trimspace(definition.id) != "" &&
      can(regex("^\\\".*\\\"$", jsonencode(definition.source_type))) &&
      contains(["custom", "built_in"], definition.source_type)
    ]), false)
    error_message = "Definitions require a non-blank id and a source_type of custom or built_in."
  }
}
