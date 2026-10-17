# Complete policy lifecycle example: all eight child modules composed through
# the published root module.
#
# Catalogue fixtures in content.tf flow through definitions and initiatives;
# assignment.tf declares the Modify assignment intent; operations.tf declares
# the explicit remediation request and the stage-sequenced governed exemption.
# The environments/uat profile supplies real scope values in live runs.

module "framework" {
  source = "../.."

  catalogue = {
    native_definitions = local.policy_native_definitions
    native_initiatives = local.policy_native_initiatives
  }

  assignments          = local.tag_assignment
  remediation_requests = local.remediation_requests
  exemptions           = local.exemptions
  evaluation_time      = var.evaluation_time

  requirements = {
    "req-tag-governance" = {
      title           = "Tag storage accounts with a cost centre"
      owner           = "platform-governance"
      rationale       = "Attributable cost governance for the disposable example target, demonstrated end to end through remediation and a governed exemption."
      control_keys    = ["add-costcentre-tag"]
      assignment_keys = ["modify-tag-rg"]
      review_date     = "2026-12-31"
      status          = "implemented"
    }
  }
}
