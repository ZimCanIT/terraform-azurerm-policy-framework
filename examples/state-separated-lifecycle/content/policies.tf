# Synthetic policy content: one custom Modify definition and one initiative
# that composes it. The shapes follow the catalogue source envelope. No value
# embeds a real tenant or subscription identity.

locals {
  native_definitions = {
    "add-costcentre-tag" = {
      source_type  = "custom"
      name         = "add-costcentre-tag"
      display_name = "Add cost centre tag to storage accounts"
      description  = "Adds the configured cost centre tag to storage accounts so tag attribution and Modify remediation can be shown end to end."
      mode         = "Indexed"
      version      = "1.0.0"
      metadata     = { category = "Tags" }

      parameters = {
        tagName = {
          type         = "String"
          defaultValue = "costCentre"
          metadata     = { displayName = "Tag name", description = "Name of the tag to add, such as costCentre." }
        }
        tagValue = {
          type         = "String"
          defaultValue = "example-cost-centre"
          metadata     = { displayName = "Tag value", description = "Value of the tag to add, such as a synthetic cost centre code." }
        }
      }

      supported_effects   = ["Modify"]
      role_definition_ids = [module.shared.role_definition_id]

      # The rule effect is the literal value because behaviour resolution reads
      # it before normalising. The rule repeats the role definition ID because
      # the Azure Policy engine needs it to evaluate the assignment identity.
      policy_rule = {
        if = {
          allOf = [
            { field = "type", equals = "Microsoft.Storage/storageAccounts" },
            { field = "[concat('tags[', parameters('tagName'), ']')]", exists = "false" }
          ]
        }
        then = {
          effect = "Modify"
          details = {
            roleDefinitionIds = [module.shared.role_definition_id]
            operations = [{
              operation = "add"
              field     = "[concat('tags[', parameters('tagName'), ']')]"
              value     = "[parameters('tagValue')]"
            }]
          }
        }
      }
    }
  }

  native_initiatives = {
    "tag-governance" = {
      display_name = "Tag governance"
      description  = "Composes the example's custom Modify definition through the catalogue contract."
      version      = "1.0.0"
      metadata     = { category = "Tags" }

      # The set parameters promote the member's tagName and tagValue. Azure
      # rejects assignment parameters that the set definition does not declare,
      # and the contract forbids a set parameter named like a member parameter.
      parameters = {
        costCentreTagName = {
          type         = "String"
          defaultValue = "CostCentre"
          metadata     = { displayName = "Cost centre tag name", description = "Name of the tag the member adds, such as CostCentre." }
        }
        costCentreTagValue = {
          type         = "String"
          defaultValue = "zctfp-states"
          metadata     = { displayName = "Cost centre tag value", description = "Value of the tag the member adds, such as a synthetic cost centre code." }
        }
      }

      policy_definition_references = [{
        reference_id   = "add-costcentre-tag-member"
        definition_key = "add-costcentre-tag"

        parameter_values = {
          tagName  = { value = "[parameters('costCentreTagName')]" }
          tagValue = { value = "[parameters('costCentreTagValue')]" }
        }
      }]
    }
  }
}
