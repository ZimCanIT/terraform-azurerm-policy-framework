locals {
  # Names are derived from run_id, never generated, so every state computes the
  # same values and a rerun finds the same resources.
  resource_group_name  = "rg-zctfp-${var.run_id}"
  storage_account_name = "zctfp${var.run_id}store"
  subscription_scope   = "/subscriptions/${var.subscription_id}"
  resource_group_id    = "${local.subscription_scope}/resourceGroups/${local.resource_group_name}"

  # Tag Contributor is the least-privilege built-in role for tag modification.
  # The subscription-prefixed form is deliberate: Azure normalises tenant-level
  # role definition IDs to it on read-back when the grant scope carries a
  # subscription, so the tenant-level form would show as drift.
  role_definition_id = "${local.subscription_scope}/providers/Microsoft.Authorization/roleDefinitions/4a9ae827-6dc8-4573-8ac7-8239d42aa03f"

  # The assignment intents. The role-grant state and the assignment state each
  # resolve these records for themselves, so they must read one copy. The map
  # key is the stable assignment key: renaming it replaces the assignment.
  assignments = {
    "modify-tag-rg" = {
      target = {
        reference_id   = "add-costcentre-tag-member"
        initiative_key = "tag-governance"
      }

      scope = {
        type = "resource_group"
        id   = local.resource_group_id
      }

      # These are the tag-governance initiative's own parameters.
      parameters = {
        costCentreTagName  = "CostCentre"
        costCentreTagValue = "zctfp-states"
      }

      enforcement_mode = "Default"

      # Modify needs a user-assigned identity. The intent supplies placement
      # only; the resolver decides whether one is required.
      identity = {
        strategy            = "user_assigned"
        location            = var.location
        resource_group_name = local.resource_group_name
      }

      # The key must equal the definition's candidate role ID exactly.
      role_grant_scopes = {
        (local.role_definition_id) = local.resource_group_id
      }
    }
  }
}
