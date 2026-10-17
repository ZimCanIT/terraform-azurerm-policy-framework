variable "assignments" {
  description = "Canonical resolved assignment records keyed by stable assignment key."
  type        = any
  default     = {}

  validation {
    condition     = can(keys(var.assignments)) && !can(tolist(var.assignments))
    error_message = "assignments must be a keyed object or map of resolved assignment records."
  }
}

variable "evaluation_time" {
  description = "Optional RFC3339 instant used to classify expiry. When omitted, Terraform evaluation time is used."
  type        = string
  default     = null

  validation {
    condition     = var.evaluation_time == null || can(formatdate("YYYY-MM-DD'T'hh:mm:ss'Z'", var.evaluation_time))
    error_message = "evaluation_time must be null or a valid RFC3339 timestamp."
  }
}

variable "exemptions" {
  description = "Governed exemption requests keyed by stable request key."
  type        = any
  default     = {}

  validation {
    condition     = can(keys(var.exemptions)) && !can(tolist(var.exemptions))
    error_message = "exemptions must be a keyed object or map of exemption request objects."
  }

  validation {
    condition = try(alltrue([
      for key, exemption in var.exemptions :
      trimspace(key) != "" && can(keys(exemption))
    ]), false)
    error_message = "Each exemption request must use a non-blank key and an object value."
  }

  validation {
    condition = try(alltrue([
      for _, exemption in var.exemptions :
      length(setsubtract(toset(keys(exemption)), toset([
        "request_mode", "assignment_id", "scope", "owner", "reason", "approval_reference",
        "ticket_reference", "category", "compensating_control", "expires_on",
        "policy_definition_reference_ids", "selectors", "display_name", "description"
      ]))) == 0
    ]), false)
    error_message = "Exemption requests may contain only fields from the governed exemption contract."
  }
}
