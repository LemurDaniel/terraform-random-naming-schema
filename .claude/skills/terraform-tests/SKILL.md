---
name: terraform-tests
description: Write, run, and fix the native Terraform tests (.tftest.hcl) for this naming-schema module. Use when adding a test for a convention key, an override or a merge behaviour, when `terraform test` fails, when a resolved schema output needs to be asserted, or when the user asks to test / verify / validate the module ("add a test", "test schreiben", "tests laufen lassen", "warum failt der test"). Covers the missing suite, the plan-vs-apply split forced by random_uuid, and the override-merge traps.
---

# Testing the naming schema

## Running the suite

```bash
terraform init -backend=false
terraform test
```

`terraform test` requires Terraform 1.8+ (this module declares
`required_version >= 1.13` anyway) and runs every `*.tftest.hcl` under `tests/`.
The `init` is mandatory even for `command = plan` runs, because the module
declares a `random_uuid` resource and the `hashicorp/random` provider must be
installed first.

`tests/` holds 28 runs in four files: `defaults.tftest.hcl` (the convention with
no override), `overlay.tftest.hcl` (the merge contract), `convention.tftest.hcl`
(the allow-list) and `random.tftest.hcl` (the single `apply` case). The suite is
green; keep it that way, and extend it in the same shape.

## What is actually under test

The module is a loader, not a generator: it reads
`convention/<var.convention>.naming.yaml`, deep-merges `var.naming` over it in
`locals.tf`, and exposes seven outputs from `outputs.tf`. So a test asserts
**resolved schema values**, never a finished resource name — names are rendered
by the companion `LemurDaniel/naming/random` module and belong in *that* repo's
tests.

Drive a test entirely through the three root variables:

```hcl
variables {
  convention = "default"
  parameters = {
    location    = "westeurope"
    environment = "DEVELOPMENT"
    name        = "TEST"
  }
}

run "default_parameters_take_var_parameters" {
  command = plan

  assert {
    condition     = output.default_parameters.environment == "DEVELOPMENT"
    error_message = "got: ${jsonencode(output.default_parameters)}"
  }
}
```

A file-level `variables` block is shared by every `run` in that file; a
`run`-level block overrides it per case. Keep `convention` and `parameters` at
file level and vary only what the case is about.

## `command = plan` for everything except `random`

The module declares exactly one resource, `random_uuid.id`. Its result is
**unknown at plan time**, so an assertion that touches `output.random` fails
with an unknown-value error rather than a mismatch. Split accordingly:

- `command = plan` — every schema output (`index_modifier`,
  `enforce_lower_case`, `abbreviations`, `mappings`, `patterns`,
  `default_parameters`). Faster, no state.
- `command = apply` — only a case asserting that `output.random.uuid` is a
  well-formed uuid. It creates nothing outside Terraform, so it is safe:

  ```hcl
  run "random_uuid_is_generated" {
    command = apply

    assert {
      condition     = can(regex("^[0-9a-f-]{36}$", output.random.uuid))
      error_message = "got: ${output.random.uuid}"
    }
  }
  ```

Never assert a *specific* uuid — it is regenerated on every apply. Pinning a
deterministic uuid is the companion generator's problem, solved there by passing
a literal `random = { uuid = "..." }` fixture instead of this module.

## Asserting the overlay — what the merges guarantee

The whole point of `locals.tf` is that `var.naming` **deep-merges** over the
bundled convention with the **caller's value winning** at every level, so a
caller can override exactly one abbreviation or one pattern without restating
the block around it. That is the contract tests exist to pin down. One `run`
per guarantee:

- **A custom value overrides the bundled one.** Pass a `naming` object setting a
  single abbreviation that the convention already defines, and assert the custom
  string comes back. This was the original bug — the default used to be passed
  last to `merge()` and silently won — so this test earns its keep.
- **Siblings survive the override.** With that same single-entry `naming`,
  assert that *another* abbreviation under the same provider is still the
  bundled one. A shallow merge would have dropped the whole `Azure` table; this
  is what the per-provider comprehension prevents.
- **Omitting a key falls back entirely.** `naming = { abbreviations = {...} }`
  with no `patterns` must still yield the bundled patterns, not `null` —
  previously the `patterns` output was the caller's value unmerged, which broke
  the generator. Assert `output.patterns.default` is non-null.
- **`patterns` merges at all three levels**: global strings (`default`),
  provider strings (`Azure.default`), and per-type/kind objects
  (`Azure["Microsoft.Compute/disks"].os`). Override one leaf and assert both it
  *and* an untouched sibling leaf. Mixed strings-and-objects at one level is the
  tricky part of that code, so cover a type-level override and a
  provider-default override separately.
- **`enforce_lower_case` mixes scalars and nested objects** (`default = true`
  alongside `azurerm = { ... }`), and `locals.tf` builds those in two passes
  before merging. Assert both a scalar (`output.enforce_lower_case.default`) and
  a nested leaf in the same suite — a regression there typically breaks one and
  not the other.
- **`default_parameters` precedence is bundled < `naming.default_parameters` <
  `var.parameters`.** All three layers in one `run`, since this is the module's
  main purpose.
- **`index_modifier` is `1`** in the bundled convention, which is what makes
  generated indices start at `01`, and a custom `index_modifier = 0` must win.
  Note `coalesce` is used here, so `0` is a legal override but `null` falls back.
- **Explicit nulls are legal input.** `var.naming`'s attributes are all
  `optional()` with no defaults, so a caller may pass
  `naming = { abbreviations = null }`. `locals.tf` normalises those to `{}`;
  assert one such case so the normalisation is not refactored away.

## Testing the convention selector

`var.convention` is validated against the list of bundled convention files
(`["default"]`). Every allowed value must have a matching
`convention/<name>.naming.yaml`; an allowed value without a file passes
validation and then fails in `file()`, which is the bug the old
`["default", "other"]` list had. A test pins the rejection:

```hcl
run "rejects_unknown_convention" {
  command = plan
  variables {
    convention = "nonexistent"
  }

  expect_failures = [var.convention]
}
```

`expect_failures` works for the variable-validation case. A missing *file* for an
allowed name cannot be expressed that way (it is an evaluation error, not a
validation one), so do not try to write a `run` for it — keep the validation
list and the `convention/` directory in sync instead, per
[git-commit-conventions](../git-commit-conventions/SKILL.md).

## Writing assertions that are debuggable

Always interpolate the **actual** value into `error_message`. `terraform test`
prints the message but not the computed value, so without it a failure tells
you nothing. For maps and objects use `jsonencode(...)`:

```hcl
error_message = "got: ${jsonencode(output.abbreviations)}"
```

> [!IMPORTANT]
> A collection output compared against a literal can fail with "LHS and RHS
> values are of different types" even when the elements match, because an HCL
> literal is a tuple/object rather than a list/map. Compare a single looked-up
> value (`output.mappings.location.westeurope == "euwe"`), or compare
> `jsonencode()` of both sides, instead of comparing the collections directly.

## Adding to the suite

One file per concern, one `run` per behaviour, named after it. Derive each
expected value from `convention/default.naming.yaml`, then **run the test to
confirm** — never commit an expected value reasoned out by hand.

Then **verify the test can fail.** A new assertion that passes on the first run
has not yet been shown to test anything. Copy the module to a scratch directory,
break the behaviour it targets, and confirm that run — and ideally only that run
— goes red. The merge direction, the merge depth, the `patterns` fallback, the
parameter precedence and the `index_modifier` coalesce are each covered that way
today.

One gap is known and recorded in `tests/overlay.tftest.hcl`: collapsing the
`enforce_lower_case` two-pass build into a plain `merge()` breaks nothing,
because the bundled convention ships no nested provider block for a caller key
to collide with. Add that case when the convention gains one.

## Related

- A test change is its own commit — see
  [git-commit-conventions](../git-commit-conventions/SKILL.md).
- The suite is a gate before tagging a version — see
  [release](../release/SKILL.md).
