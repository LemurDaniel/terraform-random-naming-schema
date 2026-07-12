# Terraform Naming Schema Module

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Terraform Registry](https://img.shields.io/badge/registry-naming--schema%2Frandom-blue)](https://registry.terraform.io/modules/LemurDaniel/naming-schema/random/latest)

A schema-driven approach to consistent resource naming in Terraform. Define your naming conventions once in YAML — patterns, abbreviations, mappings, and settings — and consume the resolved schema from any module or provider.

This module loads and merges a naming convention (a bundled one, or your own YAML) with a set of runtime parameters, and outputs a single resolved schema object that other modules can build resource names from. It only resolves the *schema* — to actually render resource names from it, pair it with the [`LemurDaniel/naming/random`](https://registry.terraform.io/modules/LemurDaniel/naming/random/latest) module, as shown below.

## 🚀 Quick Start

```hcl
module "schema" {
  source  = "LemurDaniel/naming-schema/random"
  version = "~> 1.0"

  naming     = yamldecode(file("${path.root}/naming.yaml"))
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

> [!NOTE]
> This module ([`LemurDaniel/naming-schema/random`](https://registry.terraform.io/modules/LemurDaniel/naming-schema/random/latest)) only produces the resolved schema object. Generating an actual name — like `storage_account_name` above — requires the companion [`LemurDaniel/naming/random`](https://registry.terraform.io/modules/LemurDaniel/naming/random/latest) module, which consumes that schema.

## 📥 Inputs

| Name | Type | Required | Description |
|---|---|---|---|
| `convention` | `string` | No (default `"default"`) | Name of the bundled convention to load from `convention/<name>.naming.yaml`. |
| `naming` | `object` | No | Custom schema, partially overriding the bundled convention. See the [object shape](variables.tf) for `index_modifier`, `enforce_lower_case`, `mappings`, `patterns`, `abbreviations`, `default_parameters`. |
| `parameters` | `map(any)` | No (default `{}`) | Runtime parameters (e.g. `location`, `environment`, `name`) merged on top of `default_parameters`. |

## 📤 Outputs

| Name | Description |
|---|---|
| `random` | A random source (`uuid`) for generating unique naming ids. |
| `index_modifier` | The resolved index offset (e.g. `1` so indices start at `01`). |
| `enforce_lower_case` | The resolved lower-casing settings. |
| `abbreviations` | The merged abbreviations table. |
| `mappings` | The merged mappings table. |
| `patterns` | The resolved patterns table. |
| `default_parameters` | The merged default parameters, combined with `var.parameters`. |

## Examples

A full runnable example lives under [`examples/basic/`](examples/basic/), demonstrating a custom YAML override on top of the bundled `default` convention (see [`naming.basic.yaml`](examples/basic/naming.basic.yaml)), plus a fully annotated reference file covering every configurable key (see [`naming.full.yaml`](examples/basic/naming.full.yaml)).

## License

[MIT](LICENSE)
