variable "requirements" {
  description = "Governance requirements keyed by stable requirement key."
  type        = any
  default     = {}

  validation {
    condition     = can(keys(var.requirements)) && !can(tolist(var.requirements))
    error_message = "requirements must be a keyed object or map."
  }

  validation {
    condition = try(alltrue([
      for key, requirement in var.requirements :
      trimspace(key) != "" && can(keys(requirement)) &&
      can(tolist(requirement.control_keys)) && requirement.control_keys != null &&
      can(tolist(requirement.assignment_keys)) && requirement.assignment_keys != null &&
      alltrue([for ref in try(tolist(requirement.control_keys), []) : can(regex("^\\\".*\\\"$", jsonencode(ref))) && trimspace(ref) != ""]) &&
      alltrue([for ref in try(tolist(requirement.assignment_keys), []) : can(regex("^\\\".*\\\"$", jsonencode(ref))) && trimspace(ref) != ""]) &&
      length(distinct(try(tolist(requirement.control_keys), []))) == length(try(tolist(requirement.control_keys), [])) &&
      length(distinct(try(tolist(requirement.assignment_keys), []))) == length(try(tolist(requirement.assignment_keys), []))
    ]), false)
    error_message = "Each requirement must have a non-blank key and unique, non-blank string control_keys and assignment_keys. Invalid requirement keys: ${try(join(", ", [for key, requirement in var.requirements : key if !try(trimspace(key) != "" && can(keys(requirement)) && can(tolist(requirement.control_keys)) && requirement.control_keys != null && can(tolist(requirement.assignment_keys)) && requirement.assignment_keys != null && alltrue([for ref in try(tolist(requirement.control_keys), []) : can(regex("^\\\".*\\\"$", jsonencode(ref))) && trimspace(ref) != ""]) && alltrue([for ref in try(tolist(requirement.assignment_keys), []) : can(regex("^\\\".*\\\"$", jsonencode(ref))) && trimspace(ref) != ""]) && length(distinct(try(tolist(requirement.control_keys), []))) == length(try(tolist(requirement.control_keys), [])) && length(distinct(try(tolist(requirement.assignment_keys), []))) == length(try(tolist(requirement.assignment_keys), [])), false)]), "<invalid requirements container>")}."
  }
}

variable "control_inventory" {
  description = "Known internal control keys. Null means the inventory is unknown; an explicit empty set means no internal controls are available."
  type        = set(string)
  default     = null
  nullable    = true

  validation {
    condition     = var.control_inventory == null ? true : alltrue([for key in var.control_inventory : trimspace(key) != ""])
    error_message = "control_inventory keys must be non-blank strings when the inventory is known."
  }

  validation {
    condition     = var.control_inventory == null || length(setintersection(var.control_inventory, var.external_control_keys)) == 0
    error_message = "A control key cannot be classified as both internal and external."
  }
}

variable "assignment_inventory" {
  description = "Known internal assignment keys. Null means the inventory is unknown; an explicit empty set means no internal assignments are available."
  type        = set(string)
  default     = null
  nullable    = true

  validation {
    condition     = var.assignment_inventory == null ? true : alltrue([for key in var.assignment_inventory : trimspace(key) != ""])
    error_message = "assignment_inventory keys must be non-blank strings when the inventory is known."
  }

  validation {
    condition     = var.assignment_inventory == null || length(setintersection(var.assignment_inventory, var.external_assignment_keys)) == 0
    error_message = "An assignment key cannot be classified as both internal and external."
  }
}

variable "external_control_keys" {
  description = "Control reference keys explicitly declared as external to the supplied internal inventory."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for key in var.external_control_keys : trimspace(key) != ""])
    error_message = "external_control_keys must contain only non-blank strings."
  }
}

variable "external_assignment_keys" {
  description = "Assignment reference keys explicitly declared as external to the supplied internal inventory."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for key in var.external_assignment_keys : trimspace(key) != ""])
    error_message = "external_assignment_keys must contain only non-blank strings."
  }
}
