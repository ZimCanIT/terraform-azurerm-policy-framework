# Assignment intent for the complete policy lifecycle example.
#
# The synthetic defaults keep the example portable and credential free.
# Real runs supply the caller's own subscription and resource group through
# these variables, for example from environments/uat.

locals {
  # Single assignment intent consumed by behaviour-resolution. The map key is
  # the stable assignment key: the resolver derives the deterministic identity
  # name basis and the Azure assignment name from it, so renaming the key is a
  # replacement event.
  tag_assignment = {
    "modify-tag-rg" = {
      target = {
        # Member targeting through the initiative: reference_id must match a
        # member reference of the tag-governance initiative.
        reference_id   = "add-costcentre-tag-member"
        initiative_key = "tag-governance"
      }

      scope = {
        type = "resource_group"
        id   = var.target_resource_group_id
      }

      # Initiative-target assignment parameters are the tag-governance set
      # parameters (Azure validates the keys against the set schema).
      parameters = {
        costCentreTagName  = "CostCentre"
        costCentreTagValue = "zctfp-uat"
      }

      enforcement_mode = "Default"

      # Modify requires a user-assigned identity. Intent supplies placement
      # only; the resolver owns required, strategy default and name basis.
      identity = {
        strategy            = "user_assigned"
        location            = var.identity_location
        resource_group_name = var.identity_resource_group_name
      }

      # Tag Contributor (built-in role GUID 4a9ae827-6dc8-4573-8ac7-8239d42aa03f,
      # Microsoft Learn Azure built-in roles, checked 27 September 2026) is the
      # least-privilege role for tag remediation. The key must match the
      # definition's candidate role ID exactly, so both build on
      # policy_subscription_id and move with the target subscription in real
      # runs. The subscription-prefixed form is deliberate: Azure normalises
      # tenant-level role-definition IDs to this form on read-back when the
      # grant scope carries a subscription, so the tenant-level form would
      # drift.
      role_grant_scopes = {
        "/subscriptions/${var.policy_subscription_id}/providers/Microsoft.Authorization/roleDefinitions/4a9ae827-6dc8-4573-8ac7-8239d42aa03f" = var.target_resource_group_id
      }
    }
  }
}
