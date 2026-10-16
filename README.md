# Terraform Naming Schema Module

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Terraform Registry](https://img.shields.io/badge/registry-naming--schema%2Frandom-blue)](https://registry.terraform.io/modules/LemurDaniel/naming-schema/random/latest)

A schema-driven approach to consistent resource naming in Terraform. Define your naming conventions once in YAML — patterns, abbreviations, mappings, and settings — and consume the resolved schema from any module or provider.

This module loads a naming convention (a bundled one, or your own YAML), merges your overrides over it, and outputs a single resolved schema that other modules can build resource names from. It only resolves the *schema* — to actually render resource names from it, pair it with the [`LemurDaniel/naming/random`](https://registry.terraform.io/modules/LemurDaniel/naming/random/latest) module, as shown below.

## 🚀 Quick Start

```hcl
module "schema" {
  source  = "LemurDaniel/naming-schema/random"
  version = "~> 1.0"

  parameters = {
    location    = "westeurope"
    environment = "development"
    name        = "myapp"
  }
}

module "storage_account_naming" {
  source  = "LemurDaniel/naming/random"
  version = "~> 1.0"

  schema   = module.schema
  resource = "Azure::Microsoft.Storage/storageAccounts"
}

output "storage_account_name" {
  value = module.storage_account_naming.name  # "stwedevmyapp01"
}
```

The bundled `default` convention follows Microsoft's [Cloud Adoption Framework abbreviations](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-best-practices/resource-abbreviations), so `Azure::Microsoft.Network/virtualNetworks` with the same parameters yields `vnet-we-dev-myapp-01`.

> [!NOTE]
> This module ([`LemurDaniel/naming-schema/random`](https://registry.terraform.io/modules/LemurDaniel/naming-schema/random/latest)) only produces the resolved schema. Generating an actual name — like `storage_account_name` above — requires the companion [`LemurDaniel/naming/random`](https://registry.terraform.io/modules/LemurDaniel/naming/random/latest) module, which consumes that schema.

## 🧩 Overriding the convention

Pass a `naming` object to override parts of the bundled convention. **Your values win, and everything you do not mention is kept** — overrides are merged key by key, at every level of the YAML, so you never have to restate the surrounding block.

```yaml
# naming.yaml — change only the storage account abbreviation and pattern
abbreviations:
  Azure:
    Microsoft.Storage/storageAccounts::default: stg

patterns:
  Azure:
    Microsoft.Storage/storageAccounts:
      default: "<TYPE><ENVIRONMENT><NAME><INDEX;%02s>"
```

```hcl
module "schema" {
  source  = "LemurDaniel/naming-schema/random"
  version = "~> 1.0"

  naming = yamldecode(file("${path.root}/naming.yaml"))
  parameters = {
    location    = "westeurope"
    environment = "development"
    name        = "myapp"
  }
}
```

With that overlay, a storage account becomes `stgdevmyapp01`, while every other resource type — and every other storage-account pattern variant — still resolves from the bundled convention, so a virtual network is unchanged at `vnet-we-dev-myapp-01`.

Precedence, per key:

| Key | How it resolves |
|---|---|
| `abbreviations`, `mappings` | Merged per provider / per parameter, then per entry. Your entry wins; siblings are kept. |
| `patterns` | Merged at all three levels (global default, provider default, per resource type and kind). |
| `enforce_lower_case` | Merged, scalars and per-provider objects alike. |
| `index_modifier` | Yours if set (`0` is a valid override); otherwise the convention's. |
| `default_parameters` | Convention, then `naming.default_parameters`, then `parameters` — last one wins. |

## 📥 Inputs

| Name | Type | Required | Description |
|---|---|---|---|
| `convention` | `string` | No (default `"default"`) | Name of the bundled convention to load from `convention/<name>.naming.yaml`. Currently only `"default"` ships with the module. |
| `naming` | `object` | No | Your partial override, merged over the bundled convention as described above. All attributes are optional: `index_modifier`, `enforce_lower_case`, `mappings`, `patterns`, `abbreviations`, `default_parameters`. See the [object shape](variables.tf). |
| `parameters` | `map(any)` | No (default `{}`) | Runtime parameters (e.g. `location`, `environment`, `name`) merged on top of `default_parameters`. |

## 📤 Outputs

| Name | Description |
|---|---|
| `random` | A random source (`uuid`) backing the `<UNIQUE_ID_n>` pattern token. |
| `index_modifier` | The resolved index offset (`1` by default, so indices start at `01`). |
| `enforce_lower_case` | The resolved lower-casing settings. |
| `abbreviations` | The merged abbreviations table. |
| `mappings` | The merged mappings table. |
| `patterns` | The merged patterns table. |
| `default_parameters` | The merged parameters, with `var.parameters` taking precedence. |

Pass the whole module as `schema` to the generator (`schema = module.schema`) rather than wiring the outputs individually.

## 🧱 The convention YAML

`convention/default.naming.yaml` has six top-level keys:

- **`default_parameters`** — parameter defaults, overridable per call via `parameters`.
- **`index_modifier`** — index offset; `1` means the first resource is `01`.
- **`enforce_lower_case`** — `default: true`, with optional per-provider and per-resource-type exceptions. Set a type to `false` to preserve your input casing.
- **`patterns`** — the name templates. Resolution order is `<provider>.<resource type>` → `<provider>.default` → `default`; keys under a provider match the resource type with `*` expanded, so `Microsoft.Storage/*` covers `Microsoft.Storage/storageAccounts`.
- **`mappings`** — per-parameter lookup tables applied before a pattern renders, matched case-insensitively (`westeurope` → `we`, `development` → `dev`). Location codes follow the Azure Verified Modules `geo_code` convention. Unmapped values pass through unchanged.
- **`abbreviations`** — `<provider>` → `<Namespace>/<type>::<kind>` → abbreviation, e.g. `Microsoft.Compute/disks::os: osdisk`. The `::<kind>` suffix lets one resource type carry several abbreviations.

Pattern tokens:

| Token | Meaning |
|---|---|
| `<PARAM>` | Required parameter — errors if missing |
| `<?PARAM;-separator%s>` | Optional parameter with inline separator |
| `<PARAM;%02s>` | Printf-formatted parameter |
| `<TYPE>` | Resolved abbreviation for the resource |
| `<INDEX;%02s>` | Numeric index (shifted by `index_modifier`) |
| `<UNIQUE_ID_n>` | First *n* characters of the `random` output's uuid |

## 📋 Requirements

| Name | Version |
|---|---|
| Terraform | `>= 1.13` |
| `hashicorp/random` | `>= 3.0` |

## Examples

A runnable example lives under [`examples/basic/`](examples/basic/), demonstrating a custom YAML overlay on top of the bundled `default` convention (see [`naming.basic.yaml`](examples/basic/naming.basic.yaml)), plus a fully annotated reference file covering every configurable key (see [`naming.full.yaml`](examples/basic/naming.full.yaml)).

## License

[MIT](LICENSE)
