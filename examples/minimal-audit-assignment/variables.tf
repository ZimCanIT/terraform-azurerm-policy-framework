variable "assignment_scope_id" {
  description = "Subscription scope resource ID for the audit assignment. The default is a well-formed synthetic subscription ID so that offline plan checks pass; live runs supply the real subscription resource ID through a variable file or -var."
  type        = string
  default     = "/subscriptions/00000000-0000-0000-0000-000000000000"
}

variable "built_in_audit_definition_id" {
  description = "Azure built-in policy definition resource ID assigned with the Audit effect. The default audits VMs that do not use managed disks and requires no parameters."
  type        = string
  default     = "/providers/Microsoft.Authorization/policyDefinitions/06a78e20-9358-41c9-923c-fb736d382a4d"
}

variable "assignment_key" {
  description = "Stable Terraform key for the assignment. Changing it creates a separately named assignment and is an explicit replacement migration."
  type        = string
  default     = "audit-sub"

  validation {
    condition     = trimspace(var.assignment_key) == var.assignment_key && var.assignment_key != "" && can(regex("^[[:print:]]+$", var.assignment_key))
    error_message = "assignment_key must be a non-blank printable string without surrounding whitespace."
  }
}

variable "assignment_owner" {
  description = "Governance owner projected into assignment metadata. Updating it changes the assignment metadata in place."
  type        = string
  default     = "platform-governance"

  validation {
    condition     = trimspace(var.assignment_owner) == var.assignment_owner && var.assignment_owner != "" && can(regex("^[[:print:]]+$", var.assignment_owner))
    error_message = "assignment_owner must be a non-blank printable string without surrounding whitespace."
  }
}
