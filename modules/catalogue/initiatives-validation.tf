locals {
  # Initiative entry validation: the common entry view for native HCL and JSON
  # initiatives, the member-record plumbing shared with the reference rules,
  # and the per-entry named rules. Member reference rules live in
  # initiatives-references.tf; group rules in initiatives-groups.tf; the
  # failure-string maps in diagnostics.tf.

  initiative_envelope_fields = toset([
    "catalogue_key", "name", "display_name", "description", "metadata", "parameters",
    "policy_definition_references", "policy_definition_groups", "management_group_id", "governance", "version"
  ])

  # Raw keys are retained in the common entry view so the one key rule below
  # can reject blanks, surrounding whitespace and non-string values for both
  # authoring formats before grouping, projection and provenance. Trimming the
  # JSON inline key here would silently rename an identity and diverge from the
  # native outer key.
  initiative_validation_entries = concat(
    [
      for path, document in local.initiative_documents : {
        source_id     = "json:${path}"
        catalogue_key = try(document.catalogue_key, null)
        document      = document
      }
    ],
    [
      for key, document in local.native_initiatives : {
        source_id     = "hcl:${key}"
        catalogue_key = key
        document      = document
      }
    ]
  )

  # Objects are iterable, so iteration success alone cannot prove the member
  # container is a list. The shape probe rejects keyed collections (keys
  # succeed) and non-indexed collections (index 0 fails). An empty string
  # probes as an empty container but still fails iteration, so the try guard
  # below stays. Valid heterogeneous member tuples are iterated directly
  # because tolist cannot convert them.
  initiative_reference_container_shape_ok = {
    for entry in local.initiative_validation_entries :
    entry.source_id => try(
      !can(keys(entry.document.policy_definition_references)) &&
      (
        length(entry.document.policy_definition_references) == 0 ||
        can(entry.document.policy_definition_references[0])
      ),
      false
    )
  }

  # Each member record also carries a non-raising group_names container probe
  # (can guards the element iteration), so a malformed group_names cannot fall
  # into the member-container try fallback and misreport the member container.
  # Synthetic records for malformed containers set the probe true because
  # their group_names is absent and container_valid owns that report.
  #
  # Shape-valid entries iterate their members; shape-invalid entries each
  # contribute exactly one synthetic record. The two record sets are
  # concatenated rather than selected by a conditional: Terraform unifies both
  # results of a conditional, and heterogeneous member tuples carrying
  # dynamic nulls cannot be unified with the synthetic record list, which
  # would raise a raw type error for valid inputs such as omitted versus null
  # or empty group_names. The try fallback still covers the empty-string shape
  # probe edge case where iteration fails.
  initiative_reference_records = concat(
    flatten([
      for entry in local.initiative_validation_entries :
      try(
        [
          for reference in entry.document.policy_definition_references : {
            source_id    = entry.source_id
            reference    = reference
            container_ok = true
            group_names_container_ok = (
              try(reference.group_names, null) == null || (
                can(concat(reference.group_names, [])) &&
                can([for group_name in reference.group_names : group_name])
              )
            )
          }
        ],
        [{
          source_id                = entry.source_id
          reference                = null
          container_ok             = false
          group_names_container_ok = true
        }]
      )
      if local.initiative_reference_container_shape_ok[entry.source_id]
    ]),
    [
      for entry in local.initiative_validation_entries :
      {
        source_id                = entry.source_id
        reference                = null
        container_ok             = false
        group_names_container_ok = true
      }
      if !local.initiative_reference_container_shape_ok[entry.source_id]
    ]
  )

  # Member records grouped once by source, so the uniqueness rule below is a
  # direct lookup instead of a full member-record scan for every initiative.
  initiative_reference_records_by_source = {
    for record in local.initiative_reference_records :
    record.source_id => {
      container_ok = record.container_ok
      reference_id = try(lower(trimspace(record.reference.reference_id)), null)
    }...
  }

  # Sources whose container-valid members cannot all yield a readable
  # reference_id, or whose normalised reference_id values are not unique. An
  # unreadable member shape is recorded as a deliberate uniqueness failure,
  # matching the previous rule's try semantics rather than a raw error.
  initiative_reference_duplicate_sources = {
    for source_id, records in local.initiative_reference_records_by_source :
    source_id => true
    if(
      length([
        for record in records :
        record
        if record.container_ok && record.reference_id == null
      ]) > 0 ||
      length(distinct([
        for record in records :
        record.reference_id
        if record.container_ok
        ])) != length([
        for record in records :
        record
        if record.container_ok
      ])
    )
  }

  initiative_group_names = {
    for entry in local.initiative_validation_entries : entry.source_id => try([
      for group in entry.document.policy_definition_groups : lower(trimspace(group.name))
    ], [])
  }

  # Named envelope rules, one record per initiative. Rules are independent
  # predicates so a failure names the source key or file and the failed rule.
  initiative_entry_rule_names = [
    "field_allowlist_valid",
    "key_valid",
    "required_fields_valid",
    "scalar_types_valid",
    "metadata_valid",
    "parameters_valid",
    "governance_valid",
    "version_valid",
    "group_container_valid",
    "group_names_unique_valid",
    "reference_ids_unique_valid",
  ]

  initiative_entry_validation_records = {
    for entry in local.initiative_validation_entries :
    entry.source_id => {
      source_id     = entry.source_id
      catalogue_key = entry.catalogue_key
      rules = {
        # Rule class: raw-field allowlist. Native entries are allowlisted at
        # the variable boundary and pass here.
        field_allowlist_valid = try(
          can(keys(entry.document)) &&
          length(setsubtract(toset(keys(entry.document)), local.initiative_envelope_fields)) == 0,
          false
        )

        # Rule class: catalogue key identity. One rule for native HCL outer
        # keys and JSON inline keys: the key must be a non-blank string with
        # no surrounding whitespace. Equality against trimspace does not
        # convert numbers or booleans to text, so a non-string key fails here
        # instead of being renamed or silently normalised.
        key_valid = try(
          can(regex("^\\\".*\\\"$", jsonencode(entry.catalogue_key))) &&
          trimspace(entry.catalogue_key) != "" &&
          entry.catalogue_key == trimspace(entry.catalogue_key),
          false
        )

        # Rule class: required fields.
        required_fields_valid = try(
          can(regex("^\\\".*\\\"$", jsonencode(entry.document.display_name))) &&
          trimspace(entry.document.display_name) != "" &&
          length(entry.document.policy_definition_references) > 0,
          false
        )

        # Rule class: strict scalar types. Documented string fields must be
        # actual strings when supplied; null keeps the absent or unknown
        # state and required_fields_valid owns required presence. Strict
        # string check: jsonencode first so only a JSON string matches the
        # surrounding-quote regex; a plain regex would coerce numbers and
        # booleans to text.
        scalar_types_valid = (
          (try(entry.document.name, null) == null ||
          can(regex("^\\\".*\\\"$", jsonencode(entry.document.name)))) &&
          (try(entry.document.display_name, null) == null ||
          can(regex("^\\\".*\\\"$", jsonencode(entry.document.display_name)))) &&
          (try(entry.document.description, null) == null ||
          can(regex("^\\\".*\\\"$", jsonencode(entry.document.description)))) &&
          (try(entry.document.version, null) == null ||
          can(regex("^\\\".*\\\"$", jsonencode(entry.document.version)))) &&
          (try(entry.document.management_group_id, null) == null ||
          can(regex("^\\\".*\\\"$", jsonencode(entry.document.management_group_id))))
        )

        # Rule class: metadata container. Null keeps the unknown state; an
        # explicitly supplied object stays structured.
        metadata_valid = (
          try(entry.document.metadata, null) == null ||
          can(keys(entry.document.metadata))
        )

        # Rule class: parameters container.
        parameters_valid = (
          try(entry.document.parameters, null) == null ||
          can(keys(entry.document.parameters))
        )

        # Rule class: governance container.
        governance_valid = (
          try(entry.document.governance, null) == null ||
          can(keys(entry.document.governance))
        )

        # Rule class: initiative version format. Null means no initiative
        # version; a supplied version must be an exact three-part version.
        version_valid = try(
          entry.document.version,
          null
          ) == null || try(
          can(regex("^\\\".*\\\"$", jsonencode(entry.document.version))) &&
          can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", trimspace(entry.document.version))),
          false
        )

        # Rule class: group container. Null means no groups; a supplied value
        # must be a list, not an object-keyed map or scalar.
        group_container_valid = (
          try(entry.document.policy_definition_groups, null) == null || try(
            can(concat(entry.document.policy_definition_groups, [])) &&
            can([for group in entry.document.policy_definition_groups : group]),
            false
          )
        )

        # Rule class: group name uniqueness within the initiative.
        group_names_unique_valid = (
          try(entry.document.policy_definition_groups, null) == null || try(
            length(distinct([
              for group in entry.document.policy_definition_groups : lower(trimspace(group.name))
            ])) == length([for group in entry.document.policy_definition_groups : group]),
            false
          )
        )

        # Rule class: member reference_id uniqueness. Reference ids must be
        # unique case-insensitively within each initiative; a malformed
        # reference container is reported by the reference rules instead. The
        # grouped duplicate-source map is the direct lookup, so this rule does
        # not rescan every member record for each initiative.
        reference_ids_unique_valid = !contains(keys(local.initiative_reference_duplicate_sources), entry.source_id)
      }
    }
  }
}
