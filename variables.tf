variable "catalogue" {
  description = "Catalogue source inputs: optional flat JSON directories for initiatives, custom definitions and built-in references, plus native HCL definitions and initiatives keyed by stable catalogue key."
  type = object({
    initiative_directory         = optional(string)
    custom_definition_directory  = optional(string)
    built_in_reference_directory = optional(string)
    allow_empty_sources          = optional(bool, false)
    native_definitions           = optional(any, {})
    native_initiatives           = optional(any, {})
  })
  default = {}
}

# The policy payload inputs below stay `any` on purpose. Each key carries its
# own parameter, metadata and rule shapes, and a nested `any` inside a typed
# map must unify to one type across every element, which heterogeneous policy
# payloads cannot satisfy. The child modules validate every key and report the
# offending key and rule.
variable "definitions" {
  description = "Canonical definition objects keyed by stable catalogue key. Merged over catalogue output; a matching key overrides the catalogue record."
  type        = any
  default     = {}
}

variable "initiatives" {
  description = "Canonical initiative objects keyed by stable catalogue key. Merged over catalogue output; a matching key overrides the catalogue record."
  type        = any
  default     = {}
}

variable "assignments" {
  description = "Assignment intent keyed by stable assignment key: target, typed scope, effect, version binding, parameters, enforcement, exclusions, selectors, overrides, identity and governance metadata."
  type        = any
  default     = {}
}

variable "remediation_requests" {
  description = "Explicit remediation requests keyed by stable operation key. A request naming an assignment_key created here receives that assignment's Azure ID at apply."
  type        = any
  default     = {}
}

variable "discovery_evidence" {
  description = "Caller-supplied remediation discovery evidence keyed by operation key."
  type        = any
  default     = {}
}

variable "exemptions" {
  description = "Governed exemption requests keyed by stable request key, with owner, category, reason, approval and expiry metadata."
  type        = any
  default     = {}
}

variable "evaluation_time" {
  description = "Optional RFC3339 instant used for exemption expiry classification. Fix it per run so status outputs converge."
  type        = string
  default     = null
}

variable "requirements" {
  description = "Governance requirements and ownership records keyed by stable requirement key."
  type = map(object({
    title           = optional(string)
    owner           = optional(string)
    rationale       = optional(string)
    review_date     = optional(string)
    control_keys    = optional(list(string))
    assignment_keys = optional(list(string))
    status          = optional(string, "proposed")
  }))
  default = {}
}

variable "external_control_keys" {
  description = "Governance control references declared as externally managed rather than present in this root's canonical catalogue."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for key in var.external_control_keys : trimspace(key) != ""])
    error_message = "external_control_keys must contain only non-blank stable keys."
  }
}

variable "external_assignment_keys" {
  description = "Governance assignment references declared as externally managed rather than present in this root's assignment intent."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for key in var.external_assignment_keys : trimspace(key) != ""])
    error_message = "external_assignment_keys must contain only non-blank stable keys."
  }
}
