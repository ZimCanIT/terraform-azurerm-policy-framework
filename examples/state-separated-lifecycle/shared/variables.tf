variable "subscription_id" {
  description = "Subscription that hosts the example. Every state derives the same scope and role definition IDs from it. The default is a synthetic GUID for offline validation; real runs supply the authenticated subscription."
  type        = string
  default     = "00000000-0000-0000-0000-000000000000"

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.subscription_id))
    error_message = "subscription_id must be a GUID."
  }
}

variable "location" {
  description = "Azure region for the target resource group and the assignment identity. It must not be global."
  type        = string
  default     = "westeurope"
}

variable "run_id" {
  description = "Short lowercase alphanumeric identifier that keeps concurrent runs apart. It forms part of the resource group and storage account names."
  type        = string
  default     = "example"

  validation {
    condition     = can(regex("^[a-z0-9]{1,14}$", var.run_id))
    error_message = "run_id must be 1 to 14 lowercase letters or digits so the storage account name stays within 24 characters."
  }
}
