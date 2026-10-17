output "resource_group_id" {
  description = "Resource group that hosts the governed target and the assignment identity."
  value       = azurerm_resource_group.target.id
}

output "storage_account_id" {
  description = "Storage account the Modify assignment remediates."
  value       = azurerm_storage_account.target.id
}
