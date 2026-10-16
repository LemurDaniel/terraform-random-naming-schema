# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Module Does

This module resolves a **naming schema** — it does not generate names. It loads a YAML naming
convention (a bundled one, or the caller's own), deep-merges the caller's overrides over it, and
exposes the resolved result as outputs. Rendering an actual resource name from that schema is the
job of the companion module in `terraform-random-naming`
([`LemurDaniel/naming/random`](https://registry.terraform.io/modules/LemurDaniel/naming/random/latest)),
which consumes these outputs.

The bundled convention follows Microsoft's Cloud Adoption Framework (CAF) abbreviations. Because
everything — patterns, abbreviations, mappings, settings — lives in YAML, a new resource type is
added without touching HCL.

Published on the Terraform Registry as
[`LemurDaniel/naming-schema/random`](https://registry.terraform.io/modules/LemurDaniel/naming-schema/random/latest).

## Commands

```bash
# Initialize (required before validate/test — the module uses the random provider)
terraform init -backend=false

terraform validate
terraform fmt -check -recursive

# Run tests (28 runs across four files under tests/)
terraform test
```

To see what the module actually resolves, point a scratch config at it with `source = "../.."`
(or an absolute path) and `terraform apply` it — the module creates only a `random_uuid`, so this
is free and offline. Do that rather than deriving a resolved value by hand; see
[.claude/skills/terraform-tests/SKILL.md](.claude/skills/terraform-tests/SKILL.md).

## Repository Layout

This is a **single root module** — there are no submodules. Everything at the repository root is
the module:

| File | Role |
|---|---|
| `variables.tf` | The three inputs: `convention`, `naming`, `parameters`. |
| `locals.tf` | Loads the convention YAML and performs every merge. All the logic lives here. |
| `outputs.tf` | The seven outputs that make up the resolved schema. |
| `provider.tf` | `required_version >= 1.13`, `hashicorp/random >= 3.0`. |
| `convention/default.naming.yaml` | The bundled convention. |
| `examples/basic/` | Runnable example: a custom YAML overlay on the bundled convention. |

`examples/basic/` is a scratchpad config exercising the module, not a consumable module.

## Inputs and Outputs

Inputs (`variables.tf`):

- **`convention`** (string, default `"default"`) — selects `convention/<name>.naming.yaml`.
  Validated against an explicit allow-list. **Every allowed value needs a matching file**: the
  list once contained `"other"` with no such file, which passed validation and then failed in
  `file()`. Extend the list and add the file in the same commit.
- **`naming`** (object, nullable) — the caller's partial override. Every attribute is
  `optional()`, so a caller may pass nothing, a partial object, or explicit nulls.
- **`parameters`** (`map(any)`, default `{}`) — runtime parameters (`location`, `environment`,
  `name`, …) merged on top of `default_parameters`.

Outputs (`outputs.tf`): `random`, `index_modifier`, `enforce_lower_case`, `abbreviations`,
`mappings`, `patterns`, `default_parameters`.

`random` wraps the `random_uuid.id` resource and is what feeds the generator's `<UNIQUE_ID_n>`
token. It is **unknown at plan time** — relevant when writing tests.

## Merge Semantics

This is the heart of the module, and the part worth being careful with. `locals.tf` first
normalises `var.naming` into `local.custom`, mapping absent attributes and explicit nulls to `{}`,
then merges per key. **The caller's value wins at every level, and untouched siblings survive.**

- **`abbreviations`** / **`mappings`** — merged per top-level key (provider for abbreviations,
  parameter name for mappings), then within it. Overriding one entry under `Azure` keeps every
  other `Azure` entry and every other provider.
- **`patterns`** — merged at all three levels: global strings (`default`), provider strings
  (`Azure.default`), and per-resource-type objects (`Azure["Microsoft.Storage/storageAccounts"]`).
  Overriding one kind under one type keeps the sibling kinds.
- **`enforce_lower_case`** — mixes scalars (`default: true`) with nested objects
  (`Azure: {...}`) at the same level. A single `for` expression cannot yield both value types, so
  `locals.tf` builds `elc_scalars` and `elc_providers` separately and merges them. Keep that split
  when editing.
- **`index_modifier`** — `coalesce(custom, default)`. A custom `0` is a legal override; `null`
  falls back.
- **`default_parameters`** — three layers, later winning: bundled convention <
  `naming.default_parameters` < `var.parameters`.

A plain `merge()` of the two top-level objects would be wrong twice over — it is shallow, so
supplying one entry under `Azure` would drop the rest, and with the default passed last the
default would overwrite the caller. Both were real bugs; the comments in `locals.tf` record them.
Do not "simplify" these comprehensions back into a `merge()`.

**A change to the merge logic is a public interface change**, even though no variable or output
signature moves: it changes which value a caller's `naming` object resolves to.

## Naming Convention YAML

`convention/default.naming.yaml` has six top-level keys:

- **`default_parameters`** — parameter defaults the caller can override via `var.parameters`.
- **`index_modifier`** — `1`, so rendered indices start at `01`.
- **`enforce_lower_case`** — `default: true`, plus optional per-provider / per-resource-type
  overrides. Add a type as `false` to keep its input casing.
- **`patterns`** — see the token table below.
- **`mappings`** — per-parameter lookup tables applied before the pattern renders, matched
  case-insensitively by the generator (`westeurope` → `we`, `development` → `dev`). Location codes
  follow the Azure Verified Modules `geo_code` convention. Unmapped values pass through unchanged.
- **`abbreviations`** — keyed `<provider>` → `<Namespace>/<type>::<kind>` → abbreviation, e.g.
  `Microsoft.Compute/disks::os: osdisk`. The `::<kind>` suffix is how one resource type gets
  several abbreviations.

To add a resource type: add an entry under `abbreviations`, and a pattern under `patterns` only if
the global/provider default does not suit it.

> The provider key must be the one used in the resource identifier
> (`Azure::Microsoft.Storage/storageAccounts` → `Azure`). An `enforce_lower_case` block keyed on
> `azurerm` with `azurerm_*`-style resource names was dead configuration left from the old
> identifier format — nothing matched it. Do not reintroduce that style.

## Pattern Token Syntax

Patterns are authored here but **rendered by the companion generator**, so this table is a
reference for editing the YAML, not a description of code in this repo:

| Token | Meaning |
|---|---|
| `<PARAM>` | Required parameter — errors if missing |
| `<?PARAM;-separator%s>` | Optional parameter with inline separator |
| `<PARAM;%02s>` | Printf-formatted parameter |
| `<TYPE>` | Resolved abbreviation for the resource |
| `<INDEX;%02s>` | Numeric index (shifted by `index_modifier`) |
| `<UNIQUE_ID_n>` | First *n* chars of the `random` output's uuid |

Resolution order for a pattern, first match winning:
`<provider>.<resource type>` → `<provider>.default` → `default`. Keys below a provider are
matched against the resource type with `*` expanded to `.*`, so `Microsoft.Storage/*` matches
`Microsoft.Storage/storageAccounts`. The abbreviation cascade (`::naming_id` → `::kind` →
`::default`) and this matching both happen in the generator repo.

## Tests

`tests/` holds 28 runs across four files, driven entirely through the three root variables:

| File | Covers |
|---|---|
| `tests/defaults.tftest.hcl` | What a consumer gets with no `naming` override — settings, abbreviations, the `::kind` suffix, mappings, all three pattern levels, both providers. Doubles as a regression guard on the convention YAML. |
| `tests/overlay.tftest.hcl` | The merge contract: caller wins, siblings survive, omitted keys fall back, per-level pattern overrides, parameter precedence, and the degenerate inputs (`{}`, explicit nulls, `null`). |
| `tests/convention.tftest.hcl` | The `convention` allow-list, including `expect_failures` on an unknown name. |
| `tests/random.tftest.hcl` | The one `command = apply` case, asserting `random.uuid` is a well-formed uuid. |

Rules when extending the suite:

- **Assert resolved schema values, never finished resource names.** Names are rendered by the
  generator and belong in that repo's tests.
- **`command = plan` for everything except `random`.** `random_uuid.id` is unknown at plan time,
  so an assertion touching `output.random` needs `apply` (which is free and offline).
- **Interpolate the actual value into every `error_message`** — `terraform test` prints the
  message but not the computed value. Use `jsonencode()` for collections.
- **Verify a new test actually fails when the behaviour breaks.** Mutating the merge direction,
  the merge depth, the `patterns` fallback, the parameter precedence and the `index_modifier`
  coalesce each make exactly one run fail. One known gap is documented in
  `tests/overlay.tftest.hcl`: collapsing the `enforce_lower_case` two-pass build into a plain
  `merge()` is currently undetectable, because the bundled convention ships no nested provider
  block for a caller key to collide with.

More detail in [.claude/skills/terraform-tests/SKILL.md](.claude/skills/terraform-tests/SKILL.md).

## Repository Conventions

Three skills under [.claude/skills/](.claude/skills/) carry the working rules — read the relevant
one before acting:

- **[git-commit-conventions](.claude/skills/git-commit-conventions/SKILL.md)** — commits carry
  **no attribution trailers** (no `Co-Authored-By`, no "Generated with Claude Code"); English
  imperative subject; one concern per commit; default branch is `master`.
- **[release](.claude/skills/release/SKILL.md)** — the Registry discovers versions from git tags
  (`v`-prefixed semver). A changed resolved schema value is a breaking change.
- **[terraform-tests](.claude/skills/terraform-tests/SKILL.md)** — the fixture patterns and the
  plan-vs-apply split.

The `origin` remote URL embeds a GitHub personal access token — never copy a remote URL into a
tracked file, a commit message, or command output you paste back.

## Companion Repository

`terraform-random-naming` (published as `LemurDaniel/naming/random`) consumes this module's
outputs and renders the names. Its default branch is **`main`**; this repo's is **`master`**.
Release this module first, then bump its constraint there — never the other way round.
