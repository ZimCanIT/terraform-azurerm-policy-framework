locals {
  resolved_records = values(module.behaviour_resolution.assignments)
  scope_types      = [for record in local.resolved_records : try(record.intent.scope.type, null)]

  plan_summary = {
    assignment_count             = length(local.resolved_records)
    scope_types                  = distinct([for type in local.scope_types : type if type != null])
    management_groups            = length([for type in local.scope_types : type if type == "management_group"])
    subscriptions                = length([for type in local.scope_types : type if type == "subscription"])
    resource_groups              = length([for type in local.scope_types : type if type == "resource_group"])
    resources                    = length([for type in local.scope_types : type if type == "resource"])
    management_group_inheritance = contains(local.scope_types, "management_group")
    exclusion_count              = sum(concat([0], [for record in local.resolved_records : try(length(record.resolved.exclusions), 0)]))
    selector_count               = sum(concat([0], [for record in local.resolved_records : try(length(record.resolved.selectors), 0)]))
    rollout_stages               = distinct([for record in local.resolved_records : try(record.intent.rollout.stage, "unspecified")])
    approval_references = distinct([
      for record in local.resolved_records : try(record.intent.rollout.approval_reference, null)
      if try(record.intent.rollout.approval_reference, null) != null
    ])
  }
}
