# ------------------------------------------------------------------------------------------------
# The merge contract: `naming` overrides the bundled convention per key, the caller's value wins,
# and everything the caller does not mention survives.
#
# Both halves of that sentence were once broken - the default used to be passed last to merge(),
# so custom abbreviations were silently ignored, and the merges were shallow, so overriding one
# entry dropped its siblings. Each run below pins one half of one key.
# ------------------------------------------------------------------------------------------------

variables {
  convention = "default"
  parameters = {
    location    = "westeurope"
    environment = "development"
    name        = "myapp"
  }
}

# ----- abbreviations ----------------------------------------------------------------------------

run "custom_abbreviation_wins" {
  command = plan

  variables {
    naming = {
      abbreviations = {
        Azure = {
          "Microsoft.Storage/storageAccounts::default" = "stg"
        }
      }
    }
  }

  assert {
    condition     = output.abbreviations.Azure["Microsoft.Storage/storageAccounts::default"] == "stg"
    error_message = "custom abbreviation was overwritten by the bundled one, got: ${output.abbreviations.Azure["Microsoft.Storage/storageAccounts::default"]}"
  }
}

run "sibling_abbreviations_survive_override" {
  command = plan

  variables {
    naming = {
      abbreviations = {
        Azure = {
          "Microsoft.Storage/storageAccounts::default" = "stg"
        }
      }
    }
  }

  # A shallow merge would have replaced the whole Azure table with the single custom entry.
  assert {
    condition     = output.abbreviations.Azure["Microsoft.Network/virtualNetworks::default"] == "vnet"
    error_message = "sibling entry under the overridden provider was dropped, got: ${jsonencode(output.abbreviations.Azure)}"
  }

  # ...and the other kind of the very type being overridden must survive too.
  assert {
    condition     = output.abbreviations.Azure["Microsoft.Storage/storageAccounts::vm"] == "stvm"
    error_message = "sibling kind of the overridden type was dropped, got: ${output.abbreviations.Azure["Microsoft.Storage/storageAccounts::vm"]}"
  }
}

run "untouched_providers_survive_override" {
  command = plan

  variables {
    naming = {
      abbreviations = {
        Azure = {
          "Microsoft.Storage/storageAccounts::default" = "stg"
        }
      }
    }
  }

  assert {
    condition     = output.abbreviations.AzureAD["Groups::m365"] == "grpm"
    error_message = "an untouched provider was dropped, got: ${jsonencode(keys(output.abbreviations))}"
  }
}

run "custom_provider_is_added" {
  command = plan

  variables {
    naming = {
      abbreviations = {
        Custom = {
          "Some.Namespace/things::default" = "thing"
        }
      }
    }
  }

  assert {
    condition     = output.abbreviations.Custom["Some.Namespace/things::default"] == "thing"
    error_message = "a provider absent from the convention was not added, got: ${jsonencode(keys(output.abbreviations))}"
  }

  assert {
    condition     = output.abbreviations.Azure["Microsoft.Network/virtualNetworks::default"] == "vnet"
    error_message = "adding a provider disturbed the bundled ones, got: ${jsonencode(keys(output.abbreviations))}"
  }
}

# ----- mappings ---------------------------------------------------------------------------------

run "custom_mapping_wins_and_siblings_survive" {
  command = plan

  variables {
    naming = {
      mappings = {
        location = {
          westeurope = "euwe"
        }
      }
    }
  }

  assert {
    condition     = output.mappings.location.westeurope == "euwe"
    error_message = "got: ${output.mappings.location.westeurope}"
  }

  assert {
    condition     = output.mappings.location.northeurope == "ne"
    error_message = "sibling location mapping was dropped, got: ${output.mappings.location.northeurope}"
  }

  assert {
    condition     = output.mappings.environment.development == "dev"
    error_message = "an untouched mapping table was dropped, got: ${jsonencode(keys(output.mappings))}"
  }
}

# ----- patterns ---------------------------------------------------------------------------------

# Previously the patterns output was the caller's value passed straight through, so a `naming`
# object without `patterns` produced null and broke the generator downstream.
run "omitted_patterns_fall_back_entirely" {
  command = plan

  variables {
    naming = {
      abbreviations = {
        Azure = {
          "Microsoft.Storage/storageAccounts::default" = "stg"
        }
      }
    }
  }

  assert {
    condition     = output.patterns.default == "<TYPE>-<LOCATION>-<ENVIRONMENT>-<NAME>-<INDEX;%02s>-<UNIQUE_ID_4>"
    error_message = "global default pattern did not fall back, got: ${jsonencode(output.patterns.default)}"
  }

  assert {
    condition     = output.patterns.Azure["Microsoft.Storage/storageAccounts"].default == "<TYPE><LOCATION><ENVIRONMENT><NAME><INDEX;%02s>"
    error_message = "type-level pattern did not fall back, got: ${jsonencode(output.patterns.Azure["Microsoft.Storage/storageAccounts"])}"
  }
}

run "pattern_override_at_kind_level" {
  command = plan

  variables {
    naming = {
      patterns = {
        Azure = {
          "Microsoft.Storage/storageAccounts" = {
            default = "<TYPE><ENVIRONMENT><NAME><INDEX;%02s>"
          }
        }
      }
    }
  }

  assert {
    condition     = output.patterns.Azure["Microsoft.Storage/storageAccounts"].default == "<TYPE><ENVIRONMENT><NAME><INDEX;%02s>"
    error_message = "got: ${output.patterns.Azure["Microsoft.Storage/storageAccounts"].default}"
  }

  # The sibling kind under the very type being overridden.
  assert {
    condition     = output.patterns.Azure["Microsoft.Storage/storageAccounts"].vm_pattern == "<TYPE><LOCATION><ENVIRONMENT><NAME><INDEX;%02s>"
    error_message = "sibling kind was dropped, got: ${jsonencode(output.patterns.Azure["Microsoft.Storage/storageAccounts"])}"
  }

  # The sibling type under the same provider.
  assert {
    condition     = output.patterns.Azure["Microsoft.KeyVault/vaults"].default == "<TYPE>-<ENVIRONMENT>-<NAME>-<UNIQUE_ID_4>"
    error_message = "sibling type was dropped, got: ${jsonencode(output.patterns.Azure["Microsoft.KeyVault/vaults"])}"
  }

  # The provider's own default string, which sits at the same level as the type objects.
  assert {
    condition     = output.patterns.Azure.default == "<TYPE>-<LOCATION>-<ENVIRONMENT>-<NAME><?SUBNAME;-%s>-<INDEX;%02s>"
    error_message = "provider default was dropped, got: ${jsonencode(output.patterns.Azure.default)}"
  }
}

run "pattern_override_at_provider_level" {
  command = plan

  variables {
    naming = {
      patterns = {
        Azure = {
          default = "<TYPE>-<NAME>"
        }
      }
    }
  }

  assert {
    condition     = output.patterns.Azure.default == "<TYPE>-<NAME>"
    error_message = "got: ${output.patterns.Azure.default}"
  }

  # Overriding the provider default must not flatten the type objects beneath it.
  assert {
    condition     = output.patterns.Azure["Microsoft.Storage/storageAccounts"].default == "<TYPE><LOCATION><ENVIRONMENT><NAME><INDEX;%02s>"
    error_message = "type-level patterns were dropped, got: ${jsonencode(output.patterns.Azure)}"
  }

  assert {
    condition     = output.patterns.default == "<TYPE>-<LOCATION>-<ENVIRONMENT>-<NAME>-<INDEX;%02s>-<UNIQUE_ID_4>"
    error_message = "global default was disturbed, got: ${output.patterns.default}"
  }
}

# A full patterns block mixes a string ("default") with objects ("Azure", "AzureAD") at the same
# level. Normalising such a value with coalesce() or a conditional fails with "all arguments must
# have the same type", because both unify their argument types - which broke every caller passing
# a complete patterns block, examples/basic among them. The homogeneous overrides above do not
# catch it, so this run passes the mixed shape explicitly.
run "patterns_may_mix_strings_and_objects_at_top_level" {
  command = plan

  variables {
    naming = {
      patterns = {
        default = "<TYPE>-<NAME>"
        AzureAD = {
          default = "<TYPE>-<ENVIRONMENT>-<NAME>"
        }
        Azure = {
          default = "<TYPE>-<LOCATION>-<NAME>"
          "Microsoft.Storage/storageAccounts" = {
            default = "<TYPE><NAME>"
          }
        }
      }
    }
  }

  assert {
    condition     = output.patterns.default == "<TYPE>-<NAME>"
    error_message = "got: ${output.patterns.default}"
  }

  assert {
    condition     = output.patterns.AzureAD.default == "<TYPE>-<ENVIRONMENT>-<NAME>"
    error_message = "got: ${output.patterns.AzureAD.default}"
  }

  assert {
    condition     = output.patterns.Azure.default == "<TYPE>-<LOCATION>-<NAME>"
    error_message = "got: ${output.patterns.Azure.default}"
  }

  assert {
    condition     = output.patterns.Azure["Microsoft.Storage/storageAccounts"].default == "<TYPE><NAME>"
    error_message = "got: ${output.patterns.Azure["Microsoft.Storage/storageAccounts"].default}"
  }

  # The sibling kind under the overridden type still comes from the convention.
  assert {
    condition     = output.patterns.Azure["Microsoft.Storage/storageAccounts"].vm_pattern == "<TYPE><LOCATION><ENVIRONMENT><NAME><INDEX;%02s>"
    error_message = "got: ${jsonencode(output.patterns.Azure["Microsoft.Storage/storageAccounts"])}"
  }
}

# Same hazard, other key: a bool next to an object under enforce_lower_case.
run "enforce_lower_case_may_mix_scalar_and_object_in_one_input" {
  command = plan

  variables {
    naming = {
      enforce_lower_case = {
        default = false
        Azure = {
          "Microsoft.Storage/*" = true
        }
      }
    }
  }

  assert {
    condition     = output.enforce_lower_case.default == false
    error_message = "got: ${jsonencode(output.enforce_lower_case)}"
  }

  assert {
    condition     = output.enforce_lower_case.Azure["Microsoft.Storage/*"] == true
    error_message = "got: ${jsonencode(output.enforce_lower_case)}"
  }
}

run "pattern_override_at_global_level" {
  command = plan

  variables {
    naming = {
      patterns = {
        default = "<TYPE>-<NAME>"
      }
    }
  }

  assert {
    condition     = output.patterns.default == "<TYPE>-<NAME>"
    error_message = "got: ${output.patterns.default}"
  }

  assert {
    condition     = output.patterns.Azure.default == "<TYPE>-<LOCATION>-<ENVIRONMENT>-<NAME><?SUBNAME;-%s>-<INDEX;%02s>"
    error_message = "provider patterns were dropped, got: ${jsonencode(output.patterns.Azure.default)}"
  }
}

# ----- enforce_lower_case -----------------------------------------------------------------------

# This key mixes a scalar (`default: true`) with nested objects at the same level, which locals.tf
# has to build in two passes (elc_scalars / elc_providers). A regression there typically breaks
# one and not the other.
#
# KNOWN GAP: replacing that two-pass build with a plain
# merge(default_naming.enforce_lower_case, custom.enforce_lower_case) passes every test below.
# The two differ only when the caller and the convention supply the *same* provider key, where
# the plain merge drops the convention's nested entries - and the bundled convention currently
# ships no nested provider block at all (the dead `azurerm` one was removed), so no collision is
# constructible from outside. Add a collision case here as soon as the convention gains a nested
# enforce_lower_case block.
run "enforce_lower_case_mixes_scalars_and_objects" {
  command = plan

  variables {
    naming = {
      enforce_lower_case = {
        Azure = {
          "Microsoft.Compute/virtualMachines*" = false
        }
      }
    }
  }

  assert {
    condition     = output.enforce_lower_case.default == true
    error_message = "scalar default was lost when a nested object was added, got: ${jsonencode(output.enforce_lower_case)}"
  }

  assert {
    condition     = output.enforce_lower_case.Azure["Microsoft.Compute/virtualMachines*"] == false
    error_message = "nested exception did not survive, got: ${jsonencode(output.enforce_lower_case)}"
  }
}

run "enforce_lower_case_scalar_override" {
  command = plan

  variables {
    naming = {
      enforce_lower_case = {
        default = false
      }
    }
  }

  assert {
    condition     = output.enforce_lower_case.default == false
    error_message = "custom scalar was overwritten by the bundled one, got: ${jsonencode(output.enforce_lower_case)}"
  }
}

# ----- index_modifier ---------------------------------------------------------------------------

# coalesce() is used here, so 0 has to survive as a real override rather than reading as "unset".
run "index_modifier_zero_is_a_valid_override" {
  command = plan

  variables {
    naming = {
      index_modifier = 0
    }
  }

  assert {
    condition     = output.index_modifier == 0
    error_message = "index_modifier 0 fell back to the default, got: ${output.index_modifier}"
  }
}

run "omitted_index_modifier_falls_back" {
  command = plan

  variables {
    naming = {
      enforce_lower_case = {
        default = true
      }
    }
  }

  assert {
    condition     = output.index_modifier == 1
    error_message = "got: ${output.index_modifier}"
  }
}

# ----- default_parameters -----------------------------------------------------------------------

run "parameter_precedence" {
  command = plan

  variables {
    naming = {
      default_parameters = {
        environment = "from_naming"
        name        = "from_naming"
      }
    }
    parameters = {
      location = "westeurope"
      name     = "from_parameters"
    }
  }

  # var.parameters beats naming.default_parameters...
  assert {
    condition     = output.default_parameters.name == "from_parameters"
    error_message = "var.parameters should win, got: ${jsonencode(output.default_parameters)}"
  }

  # ...and naming.default_parameters is kept where var.parameters says nothing.
  assert {
    condition     = output.default_parameters.environment == "from_naming"
    error_message = "naming.default_parameters was dropped, got: ${jsonencode(output.default_parameters)}"
  }

  assert {
    condition     = output.default_parameters.location == "westeurope"
    error_message = "got: ${jsonencode(output.default_parameters)}"
  }
}

# ----- degenerate inputs ------------------------------------------------------------------------

# Every attribute of `naming` is optional() with no default, so a caller may pass explicit nulls.
# locals.tf normalises those to {} - assert it, so the normalisation is not refactored away.
run "explicit_nulls_fall_back" {
  command = plan

  variables {
    naming = {
      index_modifier     = null
      enforce_lower_case = null
      mappings           = null
      patterns           = null
      abbreviations      = null
      default_parameters = null
    }
  }

  assert {
    condition     = output.index_modifier == 1
    error_message = "got: ${output.index_modifier}"
  }

  assert {
    condition     = output.abbreviations.Azure["Microsoft.Network/virtualNetworks::default"] == "vnet"
    error_message = "got: ${jsonencode(keys(output.abbreviations))}"
  }

  assert {
    condition     = output.patterns.default == "<TYPE>-<LOCATION>-<ENVIRONMENT>-<NAME>-<INDEX;%02s>-<UNIQUE_ID_4>"
    error_message = "got: ${jsonencode(output.patterns.default)}"
  }

  assert {
    condition     = output.mappings.location.westeurope == "we"
    error_message = "got: ${output.mappings.location.westeurope}"
  }
}

run "empty_naming_object_falls_back" {
  command = plan

  variables {
    naming = {}
  }

  assert {
    condition     = output.index_modifier == 1
    error_message = "got: ${output.index_modifier}"
  }

  assert {
    condition     = output.patterns.Azure["Microsoft.Storage/storageAccounts"].default == "<TYPE><LOCATION><ENVIRONMENT><NAME><INDEX;%02s>"
    error_message = "got: ${jsonencode(output.patterns.Azure["Microsoft.Storage/storageAccounts"])}"
  }
}

run "null_naming_falls_back" {
  command = plan

  variables {
    naming = null
  }

  assert {
    condition     = output.index_modifier == 1
    error_message = "got: ${output.index_modifier}"
  }

  assert {
    condition     = output.abbreviations.Azure["Microsoft.Storage/storageAccounts::default"] == "st"
    error_message = "got: ${output.abbreviations.Azure["Microsoft.Storage/storageAccounts::default"]}"
  }
}
