run "rejects_missing_custom_definition_directory_by_default" {
  command = plan

  variables {
    custom_definition_directory = "tests/fixtures/json_ingestion/does-not-exist"
  }

  expect_failures = [terraform_data.json_ingestion_contract]
}

run "rejects_missing_built_in_reference_directory_by_default" {
  command = plan

  variables {
    built_in_reference_directory = "tests/fixtures/json_ingestion/does-not-exist"
  }

  expect_failures = [terraform_data.json_ingestion_contract]
}

run "rejects_missing_initiative_directory_by_default" {
  command = plan

  variables {
    initiative_directory = "tests/fixtures/initiative_ingestion/does-not-exist"
  }

  expect_failures = [terraform_data.initiative_ingestion_contract]
}

run "rejects_empty_custom_definition_directory_by_default" {
  command = plan

  variables {
    custom_definition_directory = "tests/fixtures/json_ingestion/empty-source"
  }

  expect_failures = [terraform_data.json_ingestion_contract]
}

run "rejects_empty_built_in_reference_directory_by_default" {
  command = plan

  variables {
    built_in_reference_directory = "tests/fixtures/json_ingestion/built-in-empty-source"
  }

  expect_failures = [terraform_data.json_ingestion_contract]
}

run "rejects_empty_initiative_directory_by_default" {
  command = plan

  variables {
    initiative_directory = "tests/fixtures/initiative_ingestion/empty-source"
  }

  expect_failures = [terraform_data.initiative_ingestion_contract]
}

run "rejects_nested_only_custom_definition_directory" {
  command = plan

  variables {
    custom_definition_directory = "tests/fixtures/json_ingestion/nested-only"
  }

  expect_failures = [terraform_data.json_ingestion_contract]
}

run "rejects_nested_only_built_in_reference_directory" {
  command = plan

  variables {
    built_in_reference_directory = "tests/fixtures/json_ingestion/built-in-nested-only"
  }

  expect_failures = [terraform_data.json_ingestion_contract]
}

run "rejects_nested_only_initiative_directory" {
  command = plan

  variables {
    initiative_directory = "tests/fixtures/initiative_ingestion/nested-only"
  }

  expect_failures = [terraform_data.initiative_ingestion_contract]
}

run "allows_empty_custom_definition_directory_when_permitted" {
  command = plan

  variables {
    custom_definition_directory = "tests/fixtures/json_ingestion/empty-source"
    allow_empty_sources         = true
  }

  assert {
    condition     = length(keys(output.definitions)) == 0
    error_message = "An explicitly permitted empty custom source must produce an empty definitions map."
  }
}

run "allows_empty_built_in_reference_directory_when_permitted" {
  command = plan

  variables {
    built_in_reference_directory = "tests/fixtures/json_ingestion/built-in-empty-source"
    allow_empty_sources          = true
  }

  assert {
    condition     = length(keys(output.definitions)) == 0
    error_message = "An explicitly permitted empty built-in source must produce an empty definitions map."
  }
}

run "allows_empty_initiative_directory_when_permitted" {
  command = plan

  variables {
    initiative_directory = "tests/fixtures/initiative_ingestion/empty-source"
    allow_empty_sources  = true
  }

  assert {
    condition     = length(keys(output.initiatives)) == 0
    error_message = "An explicitly permitted empty initiative source must produce an empty initiatives map."
  }
}
