# Disposable governed target for the complete policy lifecycle example.
#
# The storage account starts without the CostCentre tag, so it is non-compliant
# with the Modify assignment. Terraform keeps its Owner tag; the remediation
# request in operations.tf supplies the policy-managed CostCentre change.

resource "azurerm_resource_group" "target" {
  name     = var.target_resource_group_name
  location = var.target_location
}

resource "azurerm_storage_account" "target" {
  name                     = var.target_storage_account_name
  resource_group_name      = azurerm_resource_group.target.name
  location                 = azurerm_resource_group.target.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  tags = {
    Owner = "terraform"
  }

  # After remediation Azure Policy owns CostCentre. Ignore only that key;
  # Terraform still owns Owner and every other declared property.
  lifecycle {
    ignore_changes = [tags["CostCentre"]]
  }
}
