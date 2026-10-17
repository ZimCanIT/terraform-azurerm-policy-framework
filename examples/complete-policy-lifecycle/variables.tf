variable "target_resource_group_id" {
  description = "Resource group scope for the Modify assignment and its role grant. Caller supplied in real runs; the default is a synthetic ID for offline validation."
  type        = string
  default     = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-zctfp-example"

  validation {
    condition     = can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+$", var.target_resource_group_id))
    error_message = "target_resource_group_id must be a resource group resource ID of the form /subscriptions/<subscription>/resourceGroups/<name>."
  }
}


variable "identity_location" {
  description = "Azure region for the user-assigned managed identity that the Modify effect requires. Must not be global."
  type        = string
  default     = "westeurope"
}


variable "identity_resource_group_name" {
  description = "Resource group that hosts the user-assigned managed identity. Caller supplied in real runs."
  type        = string
  default     = "rg-zctfp-example"
}


variable "policy_subscription_id" {
  description = "Subscription that qualifies the subscription-prefixed role definition IDs in this fixture. Azure normalises tenant-level role definition IDs to this form on read-back, so the prefixed form keeps the role grant drift free. The default is a synthetic GUID for offline validation; real runs supply the target subscription through the environment profile."
  type        = string
  default     = "00000000-0000-0000-0000-000000000000"

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.policy_subscription_id))
    error_message = "policy_subscription_id must be a GUID."
  }
}


variable "target_resource_group_name" {
  description = "Name of the disposable resource group that hosts the governed target and bounds the assignment, remediation and exemption scopes."
  type        = string
  default     = "rg-zctfp-example"
}


variable "target_location" {
  description = "Azure region for the disposable governed target."
  type        = string
  default     = "westeurope"
}


variable "target_storage_account_name" {
  description = "Deterministic lowercase alphanumeric storage account name, stable across runs so the remediation effect is attributable to a known resource."
  type        = string
  default     = "zctfpexamplestore"
}


variable "create_exemption" {
  description = "Create the governed exemption only in an explicit second stage, after the remediation assertion on the target has completed."
  type        = bool
  default     = false
}


variable "exemption_expiry" {
  description = "Caller-controlled exemption expiry as a full RFC3339 timestamp, which the exemptions contract requires. Persist the value across repeated plans and change it only in the explicit renewal step, so an untouched plan never drifts."
  type        = string
  default     = "2027-01-31T00:00:00Z"
}


variable "exemption_assignment_id" {
  description = "Created policy assignment ID handed over from the stage 1 output and supplied as the exemption assignment_id. Empty in stage 1, where the exemption input is empty."
  type        = string
  default     = ""
}


variable "evaluation_time" {
  description = "RFC3339 instant used for exemption expiry classification; defaults to plan-time evaluation, which never converges."
  type        = string
  default     = null

  validation {
    condition     = var.evaluation_time == null || can(regex("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(Z|[+-][0-9]{2}:[0-9]{2})$", var.evaluation_time))
    error_message = "evaluation_time must be an RFC3339 instant such as 2026-09-27T21:45:00Z."
  }
}
