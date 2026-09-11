resource "azurerm_policy_definition" "this" {
  for_each = local.custom_definitions

  name                = each.value.name
  display_name        = each.value.display_name
  description         = each.value.description
  policy_type         = "Custom"
  mode                = each.value.mode
  management_group_id = each.value.management_group_id
  metadata            = length(keys(local.custom_metadata[each.key])) > 0 ? jsonencode(local.custom_metadata[each.key]) : null
  parameters          = length(keys(each.value.parameters)) > 0 ? jsonencode(each.value.parameters) : null
  policy_rule         = jsonencode(each.value.policy_rule)

  lifecycle {
    precondition {
      condition     = length(local.custom_identity_collisions) == 0
      error_message = "Custom definitions must have unique effective names within each management-group or subscription scope."
    }
  }
}