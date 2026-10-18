# Synthetic policy content for the complete policy lifecycle example.
#
# These locals are the portable catalogue fixture consumed by the root wiring:
# native HCL definitions and initiatives keyed by stable catalogue keys. The
# shapes follow the canonical source-envelope contract in modules/catalogue;
# deployment bindings such as management_group_id are deliberately absent
# because consumer roots supply them, and no value here embeds a real tenant
# or subscription identity.

locals {
  # Tag Contributor (built-in role GUID 4a9ae827-6dc8-4573-8ac7-8239d42aa03f,
  # Microsoft Learn Azure built-in roles, checked 27 September 2026) is the
  # least-privilege built-in role for tag modify operations. The
  # subscription-prefixed form matches the caller's role_grant_scopes key
  # exactly and survives Azure read-back normalisation.
  role_definition_id = "/subscriptions/${var.policy_subscription_id}/providers/Microsoft.Authorization/roleDefinitions/4a9ae827-6dc8-4573-8ac7-8239d42aa03f"

  # One custom Modify definition. policy_rule stays a JSON-shaped HCL object:
  # catalogue requires can(keys(policy_rule)) and modules/content applies
  # jsonencode itself when creating the azurerm_policy_definition resource.
  # then.effect is the literal effect value, not an expression, because
  # behaviour resolution reads the policy rule effect literally before
  # normalising it and checking supported-effect containment.
  policy_native_definitions = {
    "add-costcentre-tag" = {
      source_type  = "custom"
      name         = "add-costcentre-tag"
      display_name = "Add cost centre tag to storage accounts"
      description  = "Adds the configured cost centre tag to storage accounts so tag attribution and Modify remediation can be demonstrated end to end."
      mode         = "Indexed"
      version      = "1.0.0"

      metadata = {
        category = "Tags"
      }

      parameters = {
        # No effect parameter: the rule effect is the literal Modify value the
        # resolver reads, and Azure rejects definition parameters that the
        # rule does not use (UnusedPolicyParameters, observed live).
        tagName = {
          type         = "String"
          defaultValue = "costCentre"

          metadata = {
            displayName = "Tag name"
            description = "Name of the tag to add, such as costCentre."
          }
        }

        tagValue = {
          type         = "String"
          defaultValue = "example-cost-centre"

          metadata = {
            displayName = "Tag value"
            description = "Value of the tag to add, such as a synthetic cost centre code."
          }
        }
      }

      supported_effects = ["Modify"]

      # Candidate roles for identity/RBAC, verified against Azure: Tag
      # Contributor is the least-privilege built-in role for tag modify
      # operations. The policy rule repeats the full role definition ID
      # because the Azure Policy engine requires it to evaluate the
      # assignment identity during remediation.
      role_definition_ids = [
        local.role_definition_id
      ]

      policy_rule = {
        if = {
          allOf = [
            {
              field  = "type"
              equals = "Microsoft.Storage/storageAccounts"
            },
            {
              field  = "[concat('tags[', parameters('tagName'), ']')]"
              exists = "false"
            }
          ]
        }

        then = {
          effect = "Modify"

          details = {
            roleDefinitionIds = [
              local.role_definition_id
            ]

            operations = [
              {
                operation = "add"
                field     = "[concat('tags[', parameters('tagName'), ']')]"
                value     = "[parameters('tagValue')]"
              }
            ]
          }
        }
      }
    }
  }

  # One initiative composing the definition above. The member is keyed and
  # carries no member version constraint: a custom definition carries only a
  # content version, which is not member version intent, and the initiatives
  # contract rejects an inherited constraint that the definition cannot match.
  # Governance is an initiative-level declaration: catalogue member records
  # accept only reference, source, parameter, group and version fields.
  policy_native_initiatives = {
    "tag-governance" = {
      display_name = "Tag governance"
      description  = "Demonstrates a governed initiative composed from the example's custom Modify definition through the catalogue contract."
      version      = "1.0.0"

      metadata = {
        category = "Tags"
      }

      governance = {
        requirement_keys = ["req-tag-governance"]
      }

      # Set-level parameters promote the member's tagName/tagValue for
      # assignment-time values. Azure rejects assignment parameters that the
      # set definition does not declare (UndefinedPolicyParameter, observed
      # live), so the set schema must carry them. The names differ from the
      # member parameter names because the initiatives contract forbids a set
      # parameter colliding with a member-supplied parameter key.
      parameters = {
        costCentreTagName = {
          type         = "String"
          defaultValue = "CostCentre"

          metadata = {
            displayName = "Cost centre tag name"
            description = "Name of the tag the member adds, such as CostCentre."
          }
        }

        costCentreTagValue = {
          type         = "String"
          defaultValue = "zctfp-uat"

          metadata = {
            displayName = "Cost centre tag value"
            description = "Value of the tag the member adds, such as a synthetic cost centre code."
          }
        }
      }

      policy_definition_references = [
        {
          reference_id   = "add-costcentre-tag-member"
          definition_key = "add-costcentre-tag"

          # Member parameters delegate to the set parameters above; the
          # bracketed form is Azure Policy's template expression for
          # assignment-time value resolution. The reference field is
          # parameter_values per the initiatives contract.
          parameter_values = {
            tagName = {
              value = "[parameters('costCentreTagName')]"
            }

            tagValue = {
              value = "[parameters('costCentreTagValue')]"
            }
          }
        }
      ]
    }
  }
}
