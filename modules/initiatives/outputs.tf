locals {
  initiative_outputs = merge(
    {
      for key, initiative in local.subscription_initiatives :
      key => {
        catalogue_key                = key
        id                           = azurerm_policy_set_definition.subscription[key].id
        name                         = azurerm_policy_set_definition.subscription[key].name
        display_name                 = initiative.display_name
        description                  = initiative.description
        management_group_id          = null
        metadata                     = initiative.metadata
        parameters                   = initiative.parameters
        parameter_schema             = initiative.parameters
        policy_definition_groups     = initiative.policy_definition_groups
        policy_definition_references = local.initiative_member_resolution[key]
        governance                   = initiative.governance
        version                      = initiative.version
        created_by_module            = true
      } if local.initiative_contract_valid
    },
    {
      for key, initiative in local.management_group_initiatives :
      key => {
        catalogue_key                = key
        id                           = azurerm_management_group_policy_set_definition.management_group[key].id
        name                         = azurerm_management_group_policy_set_definition.management_group[key].name
        display_name                 = initiative.display_name
        description                  = initiative.description
        management_group_id          = initiative.management_group_id
        metadata                     = initiative.metadata
        parameters                   = initiative.parameters
        parameter_schema             = initiative.parameters
        policy_definition_groups     = initiative.policy_definition_groups
        policy_definition_references = local.initiative_member_resolution[key]
        governance                   = initiative.governance
        version                      = initiative.version
        created_by_module            = true
      } if local.initiative_contract_valid
    }
  )
}

output "initiatives" {
  description = "Canonical initiative outputs keyed by stable catalogue key. Each entry preserves the source envelope, resolved member references, governance metadata and created resource identity."
  value       = local.initiative_outputs
}

output "initiative_ids" {
  description = "Azure Policy initiative IDs keyed by stable catalogue key."
  value = {
    for key, initiative in local.initiative_outputs :
    key => initiative.id
  }
}

output "policy_definition_references" {
  description = "Resolved initiative member references keyed by stable catalogue key."
  value = {
    for key, initiative in local.initiative_outputs :
    key => initiative.policy_definition_references
  }
}
