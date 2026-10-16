# ------------------------------------------------------------------------------------------------
# The `random` output.
#
# This is the only part of the module backed by a resource (random_uuid.id), so its value is
# unknown at plan time - an assertion against it needs `command = apply`. Applying is free and
# offline: the random provider creates nothing outside Terraform state.
#
# Never assert a specific uuid; it is regenerated on every apply. A consumer that needs a
# deterministic <UNIQUE_ID_n> passes a literal `random = { uuid = "..." }` schema to the
# generator instead of using this module.
# ------------------------------------------------------------------------------------------------

variables {
  convention = "default"
  parameters = {
    location    = "westeurope"
    environment = "development"
    name        = "myapp"
  }
}

run "random_uuid_is_generated" {
  command = apply

  assert {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", output.random.uuid))
    error_message = "not a uuid: ${output.random.uuid}"
  }

  # The generator slices this string for <UNIQUE_ID_n>, so its length is part of the contract.
  assert {
    condition     = length(replace(output.random.uuid, "-", "")) == 32
    error_message = "got ${length(replace(output.random.uuid, "-", ""))} hex characters: ${output.random.uuid}"
  }
}
