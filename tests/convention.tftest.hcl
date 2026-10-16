# ------------------------------------------------------------------------------------------------
# The convention selector.
#
# var.convention is validated against an allow-list, and every allowed value needs a matching
# convention/<name>.naming.yaml. The list once contained "other" with no such file, so the value
# passed validation and then failed in file() with a much worse error - hence the rejection test.
# ------------------------------------------------------------------------------------------------

variables {
  parameters = {
    location    = "westeurope"
    environment = "development"
    name        = "myapp"
  }
}

run "default_convention_is_accepted" {
  command = plan

  variables {
    convention = "default"
  }

  assert {
    condition     = output.index_modifier == 1
    error_message = "the default convention did not load, got: ${output.index_modifier}"
  }
}

run "convention_defaults_to_default" {
  command = plan

  assert {
    condition     = output.abbreviations.Azure["Microsoft.Network/virtualNetworks::default"] == "vnet"
    error_message = "omitting var.convention did not load the default convention"
  }
}

run "rejects_unknown_convention" {
  command = plan

  variables {
    convention = "nonexistent"
  }

  expect_failures = [var.convention]
}
