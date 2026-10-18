mock_provider "azurerm" {}

run "computed_target_ids_keep_execution_keys_plan_known" {
  command = plan

  module {
    source = "./tests/fixtures/plan-known-target-ids"
  }

  assert {
    condition = toset(output.planned_operation_keys) == toset([
      "execute_created_assignment",
      "execute_resource",
      "execute_resource_group",
    ])
    error_message = "Provider-computed target IDs, and an assignment ID that is unknown until apply, must not make remediation resource keys unknown during planning."
  }
}
