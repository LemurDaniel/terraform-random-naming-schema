# ------------------------------------------------------------------------------------------------
# The bundled convention resolves on its own, with no `naming` override at all.
#
# These are the values every consumer gets out of the box, so they double as a regression guard
# on convention/default.naming.yaml: changing one of them changes a generated resource name.
# ------------------------------------------------------------------------------------------------

variables {
  convention = "default"
  parameters = {
    location    = "westeurope"
    environment = "development"
    name        = "myapp"
  }
}

run "settings_resolve" {
  command = plan

  assert {
    condition     = output.index_modifier == 1
    error_message = "index_modifier should be 1 so indices start at 01, got: ${output.index_modifier}"
  }

  assert {
    condition     = output.enforce_lower_case.default == true
    error_message = "enforce_lower_case.default should be true, got: ${jsonencode(output.enforce_lower_case)}"
  }
}

run "abbreviations_resolve" {
  command = plan

  assert {
    condition     = output.abbreviations.Azure["Microsoft.Network/virtualNetworks::default"] == "vnet"
    error_message = "got: ${output.abbreviations.Azure["Microsoft.Network/virtualNetworks::default"]}"
  }

  assert {
    condition     = output.abbreviations.Azure["Microsoft.Storage/storageAccounts::default"] == "st"
    error_message = "got: ${output.abbreviations.Azure["Microsoft.Storage/storageAccounts::default"]}"
  }
}

# The ::<kind> suffix is how one resource type carries several abbreviations - the feature the
# generator's `resource = "...::os"` form depends on.
run "kind_suffix_selects_abbreviation" {
  command = plan

  assert {
    condition     = output.abbreviations.Azure["Microsoft.Compute/disks::os"] == "osdisk"
    error_message = "got: ${output.abbreviations.Azure["Microsoft.Compute/disks::os"]}"
  }

  assert {
    condition     = output.abbreviations.Azure["Microsoft.Compute/disks::data"] == "disk"
    error_message = "got: ${output.abbreviations.Azure["Microsoft.Compute/disks::data"]}"
  }
}

run "mappings_resolve" {
  command = plan

  assert {
    condition     = output.mappings.location.westeurope == "we"
    error_message = "got: ${output.mappings.location.westeurope}"
  }

  # Both the slug and the display form of a location map to the same code.
  assert {
    condition     = output.mappings.location["West Europe"] == output.mappings.location.westeurope
    error_message = "display form and slug disagree: ${output.mappings.location["West Europe"]} vs ${output.mappings.location.westeurope}"
  }

  assert {
    condition     = output.mappings.environment.development == "dev"
    error_message = "got: ${output.mappings.environment.development}"
  }
}

run "patterns_resolve_at_every_level" {
  command = plan

  assert {
    condition     = output.patterns.default == "<TYPE>-<LOCATION>-<ENVIRONMENT>-<NAME>-<INDEX;%02s>-<UNIQUE_ID_4>"
    error_message = "got: ${output.patterns.default}"
  }

  assert {
    condition     = output.patterns.Azure.default == "<TYPE>-<LOCATION>-<ENVIRONMENT>-<NAME><?SUBNAME;-%s>-<INDEX;%02s>"
    error_message = "got: ${output.patterns.Azure.default}"
  }

  # Storage accounts allow no hyphens, so their pattern must stay separator-free.
  assert {
    condition     = output.patterns.Azure["Microsoft.Storage/storageAccounts"].default == "<TYPE><LOCATION><ENVIRONMENT><NAME><INDEX;%02s>"
    error_message = "got: ${output.patterns.Azure["Microsoft.Storage/storageAccounts"].default}"
  }
}

# AzureAD resources have no location, so the provider carries its own default pattern.
run "second_provider_resolves" {
  command = plan

  assert {
    condition     = output.abbreviations.AzureAD["Groups::m365"] == "grpm"
    error_message = "got: ${output.abbreviations.AzureAD["Groups::m365"]}"
  }

  assert {
    condition     = output.patterns.AzureAD.default == "<TYPE>-<ENVIRONMENT>-<NAME>-<INDEX;%02s>"
    error_message = "got: ${output.patterns.AzureAD.default}"
  }
}

run "parameters_reach_default_parameters" {
  command = plan

  assert {
    condition     = output.default_parameters.location == "westeurope"
    error_message = "got: ${jsonencode(output.default_parameters)}"
  }

  assert {
    condition     = output.default_parameters.name == "myapp"
    error_message = "got: ${jsonencode(output.default_parameters)}"
  }
}
