
locals {
  parent_path    = abspath(format("%s/convention/%s.naming.yaml", path.module, var.convention))
  default_naming = yamldecode(file(local.parent_path))

  /*
    var.naming is optional and every attribute inside it is optional too, so a
    caller may pass nothing, a partial object, or explicit nulls. Normalise all
    of it to empty collections once, so the merges below never have to care.
  */
  raw = {
    index_modifier     = try(var.naming.index_modifier, null)
    enforce_lower_case = try(var.naming.enforce_lower_case, null)
    abbreviations      = try(var.naming.abbreviations, null)
    mappings           = try(var.naming.mappings, null)
    patterns           = try(var.naming.patterns, null)
    default_parameters = try(var.naming.default_parameters, null)
  }

  /*
    Replacing a null with {} has to avoid both coalesce() and the conditional
    operator: each unifies the types of its arguments, and these values mix
    types by design - `patterns` holds a string under "default" next to objects
    under "Azure"/"AzureAD", and `enforce_lower_case` holds a bool next to
    objects. coalesce(<that>, {}) fails outright with "all arguments must have
    the same type", which broke every caller passing a full patterns block,
    examples/basic included.

    Indexing a tuple keeps each element's own type, so it survives the mix.
    This is the same trick the pre-merge version of this file used, for the
    same reason.
  */
  custom = {
    index_modifier     = local.raw.index_modifier
    enforce_lower_case = [local.raw.enforce_lower_case, {}][local.raw.enforce_lower_case == null ? 1 : 0]
    abbreviations      = [local.raw.abbreviations, {}][local.raw.abbreviations == null ? 1 : 0]
    mappings           = [local.raw.mappings, {}][local.raw.mappings == null ? 1 : 0]
    patterns           = [local.raw.patterns, {}][local.raw.patterns == null ? 1 : 0]
    default_parameters = [local.raw.default_parameters, {}][local.raw.default_parameters == null ? 1 : 0]
  }


  /*
    All merges below are per-key deep merges with the CALLER's value winning.

    A plain merge() of the two top-level objects would be wrong twice over: it
    is shallow, so supplying one entry under "Azure" would drop every default
    under "Azure", and with the default passed last it would also let the
    default overwrite the caller's value - which silently ignored every custom
    abbreviation and mapping.
  */

  # ---- abbreviations: <provider> => { "<type>::<kind>" = "<abbr>" } --------
  abbreviations = {
    for provider in toset(concat(
      keys(local.default_naming.abbreviations),
      keys(local.custom.abbreviations),
    )) :
    provider => merge(
      try(local.default_naming.abbreviations[provider], {}),
      try(local.custom.abbreviations[provider], {}),
    )
  }

  # ---- mappings: <parameter> => { "<value>" = "<short>" } -----------------
  mappings = {
    for parameter in toset(concat(
      keys(local.default_naming.mappings),
      keys(local.custom.mappings),
    )) :
    parameter => merge(
      try(local.default_naming.mappings[parameter], {}),
      try(local.custom.mappings[parameter], {}),
    )
  }


  /*
    enforce_lower_case mixes scalars with nested objects:

      default: true                 <- scalar
      Azure:                        <- nested
        default: true
        "Microsoft.Storage/*": true

    A single for-expression cannot produce both, because a comprehension has to
    yield one consistent value type. So scalars and nested objects are built
    separately and merged.
  */
  elc_scalars = merge(
    { for k, v in local.default_naming.enforce_lower_case : k => v if can(tobool(v)) },
    { for k, v in local.custom.enforce_lower_case : k => v if can(tobool(v)) },
  )

  elc_providers = {
    for provider in toset(concat(
      [for k, v in local.default_naming.enforce_lower_case : k if !can(tobool(v))],
      [for k, v in local.custom.enforce_lower_case : k if !can(tobool(v))],
    )) :
    provider => merge(
      try(local.default_naming.enforce_lower_case[provider], {}),
      try(local.custom.enforce_lower_case[provider], {}),
    )
  }

  enforce_lower_case = merge(local.elc_scalars, local.elc_providers)


  /*
    patterns is three levels deep and mixes strings with objects at every
    level:

      default: "<TYPE>-..."                 <- global default (string)
      Azure:
        default: "<TYPE>-..."               <- provider default (string)
        Microsoft.Compute/disks:
          os: "<TYPE>-..."                  <- per-kind (string)

    Previously this output was just the caller's patterns, unmerged - so
    passing `naming` without `patterns` produced null and failed the generator,
    and overriding a single pattern meant copying the entire block. Now each
    level is merged, so a caller can override exactly one pattern.
  */
  pat_default = local.default_naming.patterns
  pat_custom  = local.custom.patterns

  patterns = merge(
    # global-level strings, e.g. "default"
    { for k, v in local.pat_default : k => v if can(tostring(v)) },
    { for k, v in local.pat_custom : k => v if can(tostring(v)) },

    # one entry per provider, e.g. "Azure"
    {
      for provider in toset(concat(
        [for k, v in local.pat_default : k if !can(tostring(v))],
        [for k, v in local.pat_custom : k if !can(tostring(v))],
      )) :
      provider => merge(
        # provider-level strings, e.g. Azure.default
        { for k, v in try(local.pat_default[provider], {}) : k => v if can(tostring(v)) },
        { for k, v in try(local.pat_custom[provider], {}) : k => v if can(tostring(v)) },

        # per-resource-type objects of <kind> => <pattern>
        {
          for type in toset(concat(
            [for k, v in try(local.pat_default[provider], {}) : k if !can(tostring(v))],
            [for k, v in try(local.pat_custom[provider], {}) : k if !can(tostring(v))],
          )) :
          type => merge(
            try(local.pat_default[provider][type], {}),
            try(local.pat_custom[provider][type], {}),
          )
        },
      )
    },
  )
}

resource "random_uuid" "id" {}
