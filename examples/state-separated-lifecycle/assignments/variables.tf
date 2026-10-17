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
