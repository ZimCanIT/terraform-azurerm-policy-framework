mock_provider "azurerm" {}

run "computed_target_ids_keep_execution_keys_plan_known" {
  command = plan

  module {
    source = "./tests/fixtures/plan-known-target-ids"
  }

  assert {
    condition = toset(output.planned_operation_keys) == toset([
      "execute_resource",
      "execute_resource_group",
    ])
    error_message = "Provider-computed resource-group and resource target IDs must not make remediation resource keys unknown during planning."
  }
}
