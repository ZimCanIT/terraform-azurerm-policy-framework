# Disposable governed target. It is applied first because the assignment scope
# and the identity resource group must exist before any later state runs.

module "shared" {
  source = "../shared"

  subscription_id = var.subscription_id
  location        = var.location
  run_id          = var.run_id
}

resource "azurerm_resource_group" "target" {
  name     = module.shared.target.resource_group_name
  location = module.shared.location
}

# The storage account starts without the CostCentre tag, so it is
# non-compliant with the Modify assignment.
resource "azurerm_storage_account" "target" {
  name                     = module.shared.target.storage_account_name
  resource_group_name      = azurerm_resource_group.target.name
  location                 = azurerm_resource_group.target.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  tags = {
    Owner = "terraform"
  }

  # After remediation Azure Policy owns CostCentre. Ignore only that key.
  lifecycle {
    ignore_changes = [tags["CostCentre"]]
  }
}

# Every later state derives the resource group ID from the shared inputs
# instead of reading this state. The check reports a mismatch.
check "shared_scope_matches_created_scope" {
  assert {
    condition     = lower(azurerm_resource_group.target.id) == lower(module.shared.target.resource_group_id)
    error_message = "The resource group ID the shared inputs derive differs from the created resource group ID, so the assignment scope would miss the target."
  }
}
