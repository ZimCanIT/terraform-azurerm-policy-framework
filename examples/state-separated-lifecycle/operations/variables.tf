variable "subscription_id" {
  description = "Subscription that hosts the example. Pass the same value to every state. The default is a synthetic GUID for offline validation."
  type        = string
  default     = "00000000-0000-0000-0000-000000000000"
}

variable "location" {
  description = "Azure region for the example. Pass the same value to every state."
  type        = string
  default     = "westeurope"
}

variable "run_id" {
  description = "Short lowercase alphanumeric run identifier. Pass the same value to every state."
  type        = string
  default     = "example"
}

variable "create_exemption" {
  description = "Create the governed exemption. Leave false for the first apply so the exemption cannot invalidate the pending remediation, then set true once the remediation has completed."
  type        = bool
  default     = false
}

variable "exemption_expiry" {
  description = "Exemption expiry as a full RFC3339 timestamp. Keep the value across repeated plans and change it only to renew, so an untouched plan never drifts."
  type        = string
  default     = "2027-01-31T00:00:00Z"
}

variable "evaluation_time" {
  description = "RFC3339 instant used to classify exemption expiry. The default is plan-time evaluation, which never converges, so pass one value for every plan and apply of a run."
  type        = string
  default     = null
}
