locals {
  # fileset returns an empty set when an opted-in path is missing or an empty
  # directory, so both states present as zero top-level files and the contract
  # rejects either by default. try remains the dynamic-source guard: it catches
  # unexpected fileset errors (for example an invalid pattern) and still yields
  # the empty list. The recursive ** view keeps nested-only content distinct so
  # it is reported as nested, not as an empty source.
  initiative_json_files      = var.initiative_directory == null ? [] : try(sort(fileset(var.initiative_directory, "*")), [])
  initiative_json_tree_files = var.initiative_directory == null ? [] : try(sort(fileset(var.initiative_directory, "**")), [])

  unsupported_initiative_files = [
    for path in local.initiative_json_files : path
    if !endswith(path, ".json")
  ]

  nested_initiative_files = [
    for path in local.initiative_json_tree_files : path
    if length(split("/", path)) > 1
  ]

  # One decode per JSON file. Each record retains the decoded value and whether
  # decoding succeeded, so malformed JSON (decode_ok = false) stays distinct
  # from a JSON null (decode_ok = true, decoded = null) without a second read.
  # try evaluates the record constructor first; when file or jsondecode raises
  # a dynamic error the fallback record is used, so those cases become stable
  # diagnostics rather than a raw expression failure.
  initiative_json_file_records = {
    for path in local.initiative_json_files :
    path => try(
      {
        decode_ok = true
        decoded   = jsondecode(file("${var.initiative_directory}/${path}"))
      },
      {
        decode_ok = false
        decoded   = null
      }
    )
    if endswith(path, ".json")
  }

  malformed_initiative_json_files = sort([
    for path, record in local.initiative_json_file_records : path
    if !record.decode_ok
  ])

  initiative_documents = {
    for path, record in local.initiative_json_file_records :
    trimsuffix(path, ".json") => record.decoded
    if !endswith(path, "-parameters.json")
  }

  initiative_parameter_file_records = {
    for path, record in local.initiative_json_file_records :
    trimsuffix(path, "-parameters.json") => record
    if endswith(path, "-parameters.json")
  }

  initiative_parameter_documents = {
    for stem, record in local.initiative_parameter_file_records : stem => record.decoded
  }

  # Keys are already-normalised companion stems (the -parameters.json suffix is
  # removed once above). Do not strip another -parameters suffix here: a
  # repeated-suffix filename such as orphan-parameters-parameters.json would
  # collapse onto a different key and later direct map indexing would fail with
  # a raw Invalid index error instead of a deliberate diagnostic.
  initiative_parameter_source_paths = {
    for path in keys(local.initiative_parameter_documents) : path => "${path}-parameters.json"
  }

  orphan_initiative_parameter_files = sort(tolist(setsubtract(
    toset(keys(local.initiative_parameter_documents)),
    toset(keys(local.initiative_documents))
  )))

  initiative_parameter_conflict_stems = sort([
    for stem, document in local.initiative_documents : stem
    if contains(keys(local.initiative_parameter_documents), stem) && try(contains(keys(document), "parameters") && document.parameters != null, false)
  ])

  # Companion records retain decode status: a JSON null companion
  # (decode_ok = true, decoded = null) is a decoded non-object and is rejected
  # here, while malformed JSON is reported by the malformed-file precondition.
  non_object_initiative_parameter_files = sort([
    for stem, record in local.initiative_parameter_file_records :
    local.initiative_parameter_source_paths[stem]
    if record.decode_ok && !can(keys(record.decoded))
  ])

  # Named companion failures. Each string names the source file and the failed
  # rule so the preconditions below assert one rule each with an attributable
  # diagnostic.
  initiative_companion_failures = {
    companion_parent_valid = [
      for path in local.orphan_initiative_parameter_files :
      "json:${local.initiative_parameter_source_paths[path]}: failed companion_parent_valid"
    ]
    companion_conflict_valid = [
      for path in local.initiative_parameter_conflict_stems :
      "json:${path}.json: failed companion_conflict_valid"
    ]
    companion_object_valid = [
      for path in local.non_object_initiative_parameter_files :
      "json:${path}: failed companion_object_valid"
    ]
  }

  # Projection map only: trimming the inline key here cannot rename an
  # accepted identity because the key_valid precondition rejects any key that
  # differs from its trimspace, and the try fallback keeps malformed documents
  # out of direct map indexing.
  json_initiative_key_safe = {
    for path, document in local.initiative_documents :
    path => try(
      can(regex("^\\\".*\\\"$", jsonencode(document.catalogue_key))) ? document.catalogue_key : "__invalid_initiative_${path}",
      "__invalid_initiative_${path}"
    )
  }

  json_initiative_groups = {
    for path, document in local.initiative_documents :
    local.json_initiative_key_safe[path] => {
      name                         = try(document.name, null)
      display_name                 = try(document.display_name, null)
      description                  = try(document.description, null)
      metadata                     = try(document.metadata, null)
      parameters                   = try(local.initiative_parameter_documents[path], document.parameters, null)
      policy_definition_references = try(document.policy_definition_references, null)
      policy_definition_groups     = try(document.policy_definition_groups, null)
      management_group_id          = try(document.management_group_id, null)
      governance                   = try(document.governance, null)
      version                      = try(document.version, null)
    }...
  }

  json_initiatives = {
    for key, initiatives in local.json_initiative_groups : key => initiatives[0]
  }

  initiative_json_keys = values(local.json_initiative_key_safe)

  # One grouping pass keyed by the case-normalised JSON key. Duplicate
  # detection below reads group sizes directly instead of rescanning all keys
  # for each key.
  json_initiative_key_groups = {
    for key in local.initiative_json_keys :
    lower(key) => key...
    if key != ""
  }

  json_duplicate_initiative_keys = sort([
    for normalized_key, keys in local.json_initiative_key_groups : normalized_key
    if length(keys) > 1
  ])

  initiative_envelope_fields = toset([
    "catalogue_key", "name", "display_name", "description", "metadata", "parameters",
    "policy_definition_references", "policy_definition_groups", "management_group_id", "governance", "version"
  ])

  initiative_reference_fields = toset([
    "reference_id", "definition_key", "policy_definition_id", "parameter_values",
    "group_names", "version_constraint", "pinned_version"
  ])

  # Azure policy definitions can be referenced by a root built-in ID or by a
  # fully-qualified externally managed custom definition at subscription or
  # management-group scope. Resource/module IDs and bare custom names are not
  # portable references and are intentionally rejected.
  valid_policy_definition_id = [
    "^/providers/Microsoft\\.Authorization/policyDefinitions/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$",
    "^/subscriptions/[^/]+/providers/Microsoft\\.Authorization/policyDefinitions/[^/]+$",
    "^/providers/Microsoft\\.Management/managementGroups/[^/]+/providers/Microsoft\\.Authorization/policyDefinitions/[^/]+$",
  ]

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

  # Named member reference rules, one record per reference. A malformed
  # container produces one synthetic record with container_ok = false; every
  # semantic rule is marked not applicable on that record so the container
  # defect is the only reported failure rather than cascading rule
  # diagnostics.
  initiative_reference_rule_names = [
    "container_valid",
    "field_allowlist_valid",
    "required_fields_valid",
    "scalar_types_valid",
    "reference_source_valid",
    "direct_definition_id_valid",
    "parameters_valid",
    "group_names_container_valid",
    "group_names_valid",
    "version_intent_valid",
    "version_format_valid",
  ]

  initiative_reference_validation_records = [
    for record in local.initiative_reference_records : {
      source_id    = record.source_id
      reference_id = try(trimspace(record.reference.reference_id), "")
      rules = {
        # Rule class: reference container. The container must be a list, not
        # an object-keyed map or scalar; container_ok records whether the
        # shape probe accepted the collection and its members iterated.
        container_valid = record.container_ok

        # Rule class: raw-field allowlist.
        field_allowlist_valid = record.container_ok ? try(
          can(keys(record.reference)) &&
          length(setsubtract(toset(keys(record.reference)), local.initiative_reference_fields)) == 0,
          false
        ) : true

        # Rule class: required fields. Every member requires a non-blank
        # reference_id.
        required_fields_valid = record.container_ok ? try(
          can(regex("^\\\".*\\\"$", jsonencode(record.reference.reference_id))) &&
          trimspace(record.reference.reference_id) != "",
          false
        ) : true

        # Rule class: strict scalar types. Member identity fields must be
        # actual strings when supplied; null keeps the absent state and
        # required_fields_valid owns required presence. Strict string check:
        # jsonencode first so only a JSON string matches the surrounding-quote
        # regex; a plain regex would coerce numbers and booleans to text.
        scalar_types_valid = record.container_ok ? (
          (try(record.reference.reference_id, null) == null ||
          can(regex("^\\\".*\\\"$", jsonencode(record.reference.reference_id)))) &&
          (try(record.reference.definition_key, null) == null ||
          can(regex("^\\\".*\\\"$", jsonencode(record.reference.definition_key)))) &&
          (try(record.reference.policy_definition_id, null) == null ||
          can(regex("^\\\".*\\\"$", jsonencode(record.reference.policy_definition_id)))) &&
          (try(record.reference.version_constraint, null) == null ||
          can(regex("^\\\".*\\\"$", jsonencode(record.reference.version_constraint)))) &&
          (try(record.reference.pinned_version, null) == null ||
          can(regex("^\\\".*\\\"$", jsonencode(record.reference.pinned_version))))
        ) : true

        # Rule class: direct-versus-keyed source exclusivity. A member is
        # either a catalogue definition_key or a direct policy_definition_id,
        # never both and never neither.
        reference_source_valid = record.container_ok ? try(
          (
            try(record.reference.definition_key, null) != null &&
            trimspace(record.reference.definition_key) != "" &&
            try(record.reference.policy_definition_id, null) == null
          ) ||
          (
            try(record.reference.definition_key, null) == null &&
            try(record.reference.policy_definition_id, null) != null &&
            trimspace(record.reference.policy_definition_id) != ""
          ),
          false
        ) : true

        # Rule class: direct policy definition ID format. Keyed members
        # inherit the referenced definition's ID and pass this rule.
        direct_definition_id_valid = record.container_ok ? try(
          try(record.reference.definition_key, null) != null && trimspace(record.reference.definition_key) != "" ||
          anytrue([
            for pattern in local.valid_policy_definition_id :
            can(regex(pattern, record.reference.policy_definition_id))
          ]),
          false
        ) : true

        # Rule class: parameter_values container. Null keeps the definition's
        # defaults; a supplied value must be an object.
        parameters_valid = record.container_ok ? (
          try(record.reference.parameter_values, null) == null ||
          can(keys(record.reference.parameter_values))
        ) : true

        # Rule class: group_names container. Null is allowed; a supplied
        # value must be a non-keyed collection whose element iteration is
        # safe. The probe is non-raising so a malformed group_names cannot
        # abort the member-container try fallback and misreport the member
        # container.
        group_names_container_valid = record.container_ok ? record.group_names_container_ok : true

        # Rule class: group_names semantics. Guarded behind
        # group_names_container_valid; a supplied list must hold unique,
        # non-blank strings that name groups declared on the same
        # initiative. Strict string check: jsonencode first so only a JSON
        # string matches the surrounding-quote regex; a plain regex would
        # coerce numbers and booleans to text.
        group_names_valid = record.container_ok ? (
          !record.group_names_container_ok ||
          try(record.reference.group_names, null) == null || (
            alltrue([
              for group_name in record.reference.group_names :
              can(regex("^\\\".*\\\"$", jsonencode(group_name))) &&
              trimspace(group_name) != "" &&
              contains(local.initiative_group_names[record.source_id], lower(trimspace(group_name)))
            ]) &&
            length(distinct([
              for group_name in record.reference.group_names : lower(trimspace(group_name))
            ])) == length([for group_name in record.reference.group_names : group_name])
          )
        ) : true

        # Rule class: version intent. Direct members require exactly one of
        # version_constraint or pinned_version; keyed members inherit the
        # referenced definition's intent when both are omitted.
        version_intent_valid = record.container_ok ? try(
          try(trimspace(record.reference.definition_key), "") != "" ||
          (
            (
              try(trimspace(record.reference.version_constraint), "") != "" &&
              try(trimspace(record.reference.pinned_version), "") == ""
            ) ||
            (
              try(trimspace(record.reference.version_constraint), "") == "" &&
              try(trimspace(record.reference.pinned_version), "") != ""
            )
          ),
          false
        ) : true

        # Rule class: version format. Whichever intent is supplied must match
        # its documented format; supplying both is rejected by
        # version_intent_valid and by this rule.
        version_format_valid = record.container_ok ? (
          (
            try(trimspace(record.reference.version_constraint), "") == "" ||
            can(regex("^[0-9]+\\.([0-9]+|\\*)\\.\\*$", trimspace(record.reference.version_constraint)))
          ) &&
          (
            try(trimspace(record.reference.pinned_version), "") == "" ||
            can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", trimspace(record.reference.pinned_version)))
          ) &&
          !(
            try(trimspace(record.reference.version_constraint), "") != "" &&
            try(trimspace(record.reference.pinned_version), "") != ""
          )
        ) : true
      }
    }
  ]

  # Named group rules, one record per declared group. A malformed container
  # produces no group records; group_container_valid on the entry reports it.
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

  # One failure string per failing entry, member or group and rule. Each
  # string names the source key or file and the failed rule.
  initiative_entry_rule_failures = {
    for rule in local.initiative_entry_rule_names :
    rule => [
      for source_id, record in local.initiative_entry_validation_records :
      "${record.source_id} (catalogue key ${jsonencode(record.catalogue_key)}): failed ${rule}"
      if !record.rules[rule]
    ]
  }

  initiative_reference_rule_failures = {
    for rule in local.initiative_reference_rule_names :
    rule => [
      for record in local.initiative_reference_validation_records :
      "${record.source_id} member ${jsonencode(record.reference_id)}: failed ${rule}"
      if !record.rules[rule]
    ]
  }

  initiative_group_rule_failures = {
    for rule in local.initiative_group_rule_names :
    rule => [
      for record in local.initiative_group_validation_records :
      "${record.source_id} group ${jsonencode(record.group_name)}: failed ${rule}"
      if !record.rules[rule]
    ]
  }

  # The preconditions read their text from these aliases so the initiative
  # diagnostics resolve to the matching rule list.
  initiative_entry_failure_text     = local.catalogue_failure_text.initiative_entry
  initiative_reference_failure_text = local.catalogue_failure_text.initiative_reference
  initiative_group_failure_text     = local.catalogue_failure_text.initiative_group
  initiative_companion_failure_text = local.catalogue_failure_text.initiative_companion

  initiative_sources = {
    native = local.native_initiatives
    json   = local.json_initiatives
  }

  # Key origins, grouping and duplicate detection compare the same key text
  # for both authoring formats: the key_valid precondition above rejects any
  # key whose trimspace differs, so an accepted JSON inline key equals its
  # trimmed form and an accepted native outer key is retained verbatim.
  initiative_key_origins = flatten([
    for source, initiatives in local.initiative_sources : [
      for key in keys(initiatives) : {
        source         = source
        key            = key
        normalized_key = lower(key)
      }
    ]
  ])

  # One grouping pass keyed by the case-normalised key. Duplicate detection
  # below reads group sizes directly instead of rescanning every origin for
  # each distinct key. Group membership and map iteration are deterministic,
  # and only the group sizes feed the duplicate diagnostics.
  initiative_key_groups = {
    for origin in local.initiative_key_origins :
    origin.normalized_key => "${origin.source}:${origin.key}"...
  }

  duplicate_initiative_keys = sort([
    for normalized_key, origins in local.initiative_key_groups : normalized_key
    if length(origins) > 1
  ])

  initiatives = merge(
    local.initiative_sources.native,
    local.initiative_sources.json,
  )
}

output "initiatives" {
  description = "Canonical policy initiative entries keyed by stable catalogue key; pass to the future modules/initiatives.initiatives input. Catalogue preserves stable keys, member references and declared version intent only; the future initiatives module owns version inheritance and effective-version decisions."
  value       = local.initiatives

  precondition {
    condition     = length(local.duplicate_initiative_keys) == 0
    error_message = "Initiative catalogue keys must be unique across native HCL and JSON sources (case-insensitive collisions: ${join(", ", local.duplicate_initiative_keys)})."
  }
}

resource "terraform_data" "initiative_ingestion_contract" {
  # Deliberately no input: this resource exists only to evaluate the blocking
  # preconditions below. Storing the catalogue payload in instance state would
  # make policy content part of a resource whose purpose is validation and
  # create content-change plans. The preconditions reference the same locals,
  # so they still evaluate and still block invalid sources.
  lifecycle {
    precondition {
      condition     = var.initiative_directory == null || var.allow_empty_sources || length(local.initiative_json_tree_files) > 0
      error_message = "initiative_directory was opted in but contains no files (the path may be missing or empty); add a top-level JSON envelope or set allow_empty_sources = true explicitly."
    }

    precondition {
      condition     = length(local.nested_initiative_files) == 0
      error_message = "Initiative JSON source directories are flat; nested files are unsupported: ${join(", ", local.nested_initiative_files)}."
    }

    precondition {
      condition     = length(local.unsupported_initiative_files) == 0
      error_message = "Initiative JSON source directories may contain only top-level .json files: ${join(", ", local.unsupported_initiative_files)}."
    }

    precondition {
      condition     = length(local.malformed_initiative_json_files) == 0
      error_message = "Malformed initiative JSON source envelope(s): ${join(", ", local.malformed_initiative_json_files)}."
    }

    precondition {
      condition = length(local.initiative_companion_failures.companion_object_valid) == 0
      error_message = join("", [
        "Initiative parameter companion files must contain a JSON object; null, arrays, strings, numbers and booleans are unsupported. ",
        "Failures: ${local.initiative_companion_failure_text.companion_object_valid}",
      ])
    }

    precondition {
      condition     = length(local.initiative_companion_failures.companion_parent_valid) == 0
      error_message = "Each initiative *-parameters.json file must have a matching initiative envelope JSON file. Failures: ${local.initiative_companion_failure_text.companion_parent_valid}"
    }

    precondition {
      condition = length(local.initiative_companion_failures.companion_conflict_valid) == 0
      error_message = join("", [
        "An initiative envelope and its *-parameters.json companion cannot both contain non-null parameters; remove one source. ",
        "Failures: ${local.initiative_companion_failure_text.companion_conflict_valid}",
      ])
    }

    # Named initiative envelope rules. Each precondition asserts one rule from
    # initiatives.tf so a failure names the rule and the offending source key
    # or file.
    precondition {
      condition     = length(local.initiative_entry_rule_failures.field_allowlist_valid) == 0
      error_message = "Initiative envelopes may use only documented fields. Failures: ${local.initiative_entry_failure_text.field_allowlist_valid}"
    }

    precondition {
      condition = length(local.initiative_entry_rule_failures.key_valid) == 0
      error_message = join("", [
        "Initiative catalogue keys must be non-blank strings with no surrounding whitespace; native outer keys and JSON inline keys use the same rule. ",
        "Failures: ${local.initiative_entry_failure_text.key_valid}",
      ])
    }

    precondition {
      condition = length(local.initiative_entry_rule_failures.required_fields_valid) == 0
      error_message = join("", [
        "Initiative envelopes require a display name and at least one policy_definition_references member. ",
        "Failures: ${local.initiative_entry_failure_text.required_fields_valid}",
      ])
    }

    precondition {
      condition     = length(local.initiative_entry_rule_failures.scalar_types_valid) == 0
      error_message = "Initiative documented string fields must be strings when supplied. Failures: ${local.initiative_entry_failure_text.scalar_types_valid}"
    }

    precondition {
      condition     = length(local.initiative_entry_rule_failures.metadata_valid) == 0
      error_message = "Initiative metadata must be an object when supplied. Failures: ${local.initiative_entry_failure_text.metadata_valid}"
    }

    precondition {
      condition     = length(local.initiative_entry_rule_failures.parameters_valid) == 0
      error_message = "Initiative parameters must be an object when supplied. Failures: ${local.initiative_entry_failure_text.parameters_valid}"
    }

    precondition {
      condition     = length(local.initiative_entry_rule_failures.governance_valid) == 0
      error_message = "Initiative governance must be an object when supplied. Failures: ${local.initiative_entry_failure_text.governance_valid}"
    }

    precondition {
      condition     = length(local.initiative_entry_rule_failures.version_valid) == 0
      error_message = "Initiative version must be an exact three-part version when supplied. Failures: ${local.initiative_entry_failure_text.version_valid}"
    }

    precondition {
      condition     = length(local.initiative_entry_rule_failures.group_container_valid) == 0
      error_message = "Initiative policy_definition_groups must be a list of group objects when supplied. Failures: ${local.initiative_entry_failure_text.group_container_valid}"
    }

    precondition {
      condition     = length(local.initiative_entry_rule_failures.group_names_unique_valid) == 0
      error_message = "Initiative group names must be unique case-insensitively within each initiative. Failures: ${local.initiative_entry_failure_text.group_names_unique_valid}"
    }

    precondition {
      condition     = length(local.initiative_entry_rule_failures.reference_ids_unique_valid) == 0
      error_message = "Initiative member reference_id values must be unique case-insensitively within each initiative. Failures: ${local.initiative_entry_failure_text.reference_ids_unique_valid}"
    }

    # Named member reference rules.
    precondition {
      condition     = length(local.initiative_reference_rule_failures.container_valid) == 0
      error_message = "Initiative policy_definition_references must be a list of member objects. Failures: ${local.initiative_reference_failure_text.container_valid}"
    }

    precondition {
      condition     = length(local.initiative_reference_rule_failures.field_allowlist_valid) == 0
      error_message = "Initiative member references may use only documented fields. Failures: ${local.initiative_reference_failure_text.field_allowlist_valid}"
    }

    precondition {
      condition     = length(local.initiative_reference_rule_failures.required_fields_valid) == 0
      error_message = "Each initiative member requires a non-blank reference_id. Failures: ${local.initiative_reference_failure_text.required_fields_valid}"
    }

    precondition {
      condition     = length(local.initiative_reference_rule_failures.scalar_types_valid) == 0
      error_message = "Initiative member identity fields must be strings when supplied. Failures: ${local.initiative_reference_failure_text.scalar_types_valid}"
    }

    precondition {
      condition = length(local.initiative_reference_rule_failures.reference_source_valid) == 0
      error_message = join("", [
        "Each initiative member must be either a keyed definition_key or a direct policy_definition_id, never both and never neither. ",
        "Failures: ${local.initiative_reference_failure_text.reference_source_valid}",
      ])
    }

    precondition {
      condition = length(local.initiative_reference_rule_failures.direct_definition_id_valid) == 0
      error_message = join("", [
        "Direct initiative member policy_definition_id values must be a built-in root ID, a subscription-scoped ID or a ",
        "management-group-scoped ID. Failures: ${local.initiative_reference_failure_text.direct_definition_id_valid}",
      ])
    }

    precondition {
      condition     = length(local.initiative_reference_rule_failures.parameters_valid) == 0
      error_message = "Initiative member parameter_values must be an object when supplied. Failures: ${local.initiative_reference_failure_text.parameters_valid}"
    }

    precondition {
      condition     = length(local.initiative_reference_rule_failures.group_names_container_valid) == 0
      error_message = "Initiative member group_names must be null or a list when supplied. Failures: ${local.initiative_reference_failure_text.group_names_container_valid}"
    }

    precondition {
      condition = length(local.initiative_reference_rule_failures.group_names_valid) == 0
      error_message = join("", [
        "Initiative member group_names must be unique non-blank names of groups declared on the same initiative. ",
        "Failures: ${local.initiative_reference_failure_text.group_names_valid}",
      ])
    }

    precondition {
      condition = length(local.initiative_reference_rule_failures.version_intent_valid) == 0
      error_message = join("", [
        "Direct initiative members require exactly one of version_constraint or pinned_version; keyed members may omit both (inheritance). ",
        "Failures: ${local.initiative_reference_failure_text.version_intent_valid}",
      ])
    }

    precondition {
      condition = length(local.initiative_reference_rule_failures.version_format_valid) == 0
      error_message = join("", [
        "Initiative member version_constraint must be major.*.* or major.minor.* and pinned_version must be an exact x.y.z; ",
        "supplying both is rejected. Failures: ${local.initiative_reference_failure_text.version_format_valid}",
      ])
    }

    # Named group rules.
    precondition {
      condition     = length(local.initiative_group_rule_failures.field_allowlist_valid) == 0
      error_message = "Initiative group records may use only name, display_name, description and metadata. Failures: ${local.initiative_group_failure_text.field_allowlist_valid}"
    }

    precondition {
      condition     = length(local.initiative_group_rule_failures.required_fields_valid) == 0
      error_message = "Initiative group records require a non-blank name and display_name. Failures: ${local.initiative_group_failure_text.required_fields_valid}"
    }

    precondition {
      condition     = length(local.initiative_group_rule_failures.scalar_types_valid) == 0
      error_message = "Initiative group name, display_name and description must be strings when supplied. Failures: ${local.initiative_group_failure_text.scalar_types_valid}"
    }

    precondition {
      condition     = length(local.initiative_group_rule_failures.metadata_valid) == 0
      error_message = "Initiative group metadata must be an object when supplied. Failures: ${local.initiative_group_failure_text.metadata_valid}"
    }

    precondition {
      condition     = length(local.json_duplicate_initiative_keys) == 0
      error_message = "JSON initiative catalogue keys must be unique case-insensitively (collisions: ${join(", ", local.json_duplicate_initiative_keys)})."
    }
  }
}
