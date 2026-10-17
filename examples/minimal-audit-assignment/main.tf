module "framework" {
  source = "../.."

  definitions = {
    built_in_audit = {
      source_type          = "built_in"
      policy_definition_id = var.built_in_audit_definition_id
      display_name         = "Audit VMs that do not use managed disks"
      pinned_version       = "1.0.0"
      mode                 = "All"
      metadata             = null
      parameters           = null
      policy_rule          = null
      role_definition_ids  = []
      supported_effects    = ["Audit"]
      # The real built-in's rule effect is Audit, verified read-only against
      # Azure before the default was chosen. The resolver reads the default
      # effect from this capability so the assignment's requested effect is
      # provably the definition's own default, not an unenforceable request.
      capabilities = { default_effect = "Audit" }
      governance   = null
    }
  }

  assignments = {
    (var.assignment_key) = {
      target = {
        reference_id   = "built_in_audit"
        definition_key = "built_in_audit"
      }

      scope = {
        type = "subscription"
        id   = var.assignment_scope_id
      }

      effect           = "Audit"
      parameters       = null
      enforcement_mode = "Default"
      version_binding  = "unversioned"
      governance       = { owner = var.assignment_owner }
    }
  }
}
