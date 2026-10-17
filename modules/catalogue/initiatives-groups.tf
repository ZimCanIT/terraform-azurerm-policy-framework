locals {
  # Initiative group validation: one named rule record per declared group. The
  # entry view lives in initiatives-validation.tf; a malformed group container
  # produces no group records because group_container_valid on the entry
  # reports it.

  initiative_group_rule_names = [
    "field_allowlist_valid",
    "required_fields_valid",
    "scalar_types_valid",
    "metadata_valid",
  ]

  initiative_group_validation_records = flatten([
    for entry in local.initiative_validation_entries : (
      try(entry.document.policy_definition_groups, null) == null ? [] : try(
        [
          for group in entry.document.policy_definition_groups : {
            source_id  = entry.source_id
            group_name = try(trimspace(group.name), "")
            rules = {
              # Rule class: raw-field allowlist.
              field_allowlist_valid = try(
                can(keys(group)) &&
                length(setsubtract(toset(keys(group)), toset(["name", "display_name", "description", "metadata"]))) == 0,
                false
              )

              # Rule class: required fields.
              required_fields_valid = try(
                trimspace(group.name) != "" &&
                trimspace(group.display_name) != "",
                false
              )

              # Rule class: strict scalar types. Group identity fields must be
              # actual strings when supplied; null keeps the absent state and
              # required_fields_valid owns required presence. This rule is the
              # single owner of group string typing, including description.
              # Strict string check: jsonencode first so only a JSON string
              # matches the surrounding-quote regex; a plain regex would
              # coerce numbers and booleans to text.
              scalar_types_valid = (
                (try(group.name, null) == null ||
                can(regex("^\\\".*\\\"$", jsonencode(group.name)))) &&
                (try(group.display_name, null) == null ||
                can(regex("^\\\".*\\\"$", jsonencode(group.display_name)))) &&
                (try(group.description, null) == null ||
                can(regex("^\\\".*\\\"$", jsonencode(group.description))))
              )

              # Rule class: metadata container.
              metadata_valid = (
                try(group.metadata, null) == null ||
                can(keys(group.metadata))
              )
            }
          }
        ],
        []
      )
    )
  ])
}
