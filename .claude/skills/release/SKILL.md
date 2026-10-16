---
name: release
description: Cut a new version of this Terraform module and tag it so the Terraform Registry picks it up. Use when the user wants to release, publish, cut, bump, or tag a new module version ("release 1.1.0", "neue version", "bump patch", "tag a release", "publish to registry"), or asks which version is current / what changed since the last tag.
---

# Releasing a new module version

This repository is published on the Terraform Registry as
[`LemurDaniel/naming-schema/random`](https://registry.terraform.io/modules/LemurDaniel/naming-schema/random/latest).
The Registry has no "publish" API — **it discovers versions purely from git tags** on the
repository. Cutting a release therefore means: validate, tag with a semver tag, push the tag.

> **Any commit this process creates follows
> [git-commit-conventions](../git-commit-conventions/SKILL.md) — read it before committing.**
> In particular: no `Co-Authored-By` or "Generated with Claude Code" trailers, English
> imperative subject, and a body explaining the why. The same rule applies to the tag's
> annotation message and to any GitHub release notes.

## Tagging rules the Registry enforces

These are not style preferences — get them wrong and the version silently never appears:

- The tag must be **semantic versioning**: `x.y.z`, three numeric segments.
- An optional `v` prefix is allowed (`v1.2.0` and `1.2.0` both work). **This repo uses the `v`
  prefix** (`v1.0.0`, `v1.0.1`, `v1.0.3`) — keep it; never mix the two styles in one repo.
- Tags with a pre-release suffix (`v1.2.0-rc1`) are listed but never resolved as `latest` and
  are not matched by `~>` constraints. Only cut one if the user explicitly asks.
- The tag must be pushed to the remote; a local tag does nothing.
- Never move or delete a published tag. Consumers pin against it and the Registry caches it.
  A mistake is fixed by cutting the next patch version, not by re-tagging.

## Steps

### 1. Establish the current version

```bash
git fetch --tags --prune
git tag --sort=-v:refname | head -5
```

Take the highest tag as the current version. Gaps in the tag history are normal — this repo
has no `v1.0.2`, so the next patch after `v1.0.3` is `v1.0.4`, not a backfill. Always bump from
the **highest** existing tag, not from the count.

The tags also outnumber the commits here, so do not try to infer the released state from
`git log` alone; trust the tags.

### 2. Decide the bump

If the user named a version or a bump level, use it. Otherwise look at what changed and
propose one, stating the reason:

```bash
git log <last-tag>..HEAD --oneline
git diff <last-tag>..HEAD --stat
```

This module's **public interface** is three things: its variables and outputs (`variables.tf`,
`outputs.tf`), the **merge semantics** in `locals.tf` — which value a caller's `naming` object
resolves to — and the **bundled convention** in `convention/default.naming.yaml`, because the
companion generator renders consumer-visible resource names from it.

- **major** — a variable was removed or renamed, a variable became required, a variable's type
  got stricter, an output was removed or renamed, an existing abbreviation, pattern or mapping
  in the bundled convention **changed value**, or the merge semantics changed so that an
  unchanged `naming` input now resolves to a different schema. A changed resolved value changes
  a generated name, and renaming a name a consumer already applied forces resource replacement,
  so treat it as breaking even though no HCL signature moved.
- **minor** — a new optional variable, a new output, a new resource type / abbreviation /
  pattern / mapping **added** to the convention, a new bundled convention file, new
  functionality that leaves existing configs resolving the same.
- **patch** — bug fixes, docs, comments, examples, tests, formatting; nothing a consumer's plan
  would notice.

When unsure between minor and major, ask rather than guess — a wrong major is cosmetic, a
wrong minor breaks pinned consumers. Note that a *bug fix* to the merge logic is still a major
if it changes a resolved schema: the deep-merge rework in `locals.tf` — caller values now
winning, `patterns` merged per level instead of being passed through — fixes genuine bugs and
is nonetheless breaking for anyone already passing `naming`. Check whether that rework is
already released before classifying a change on top of it.

Commit bodies written per [git-commit-conventions](../git-commit-conventions/SKILL.md) state
whether a change is breaking and whether it alters a resolved schema value; read them rather
than re-deriving the answer from the diff. Where a body is missing or says nothing (the older
history does), fall back to the diff of `variables.tf`, `outputs.tf`, `locals.tf` and
`convention/default.naming.yaml`.

### 3. Run the test suite — mandatory gate

**The test suite runs before anything is tagged, and it must pass.** A released tag is
immutable and consumers pin against it, so an untested release cannot be taken back, only
superseded.

```bash
terraform init -backend=false
terraform test
```

- **Green** → continue. The suite is 28 runs across four files under `tests/`.
- **Red** → stop and report which `run` blocks failed. Do not tag. Fix the failure (or the
  test, if the test is what is wrong) and start over.
- **"no test files"** → the suite did not run at all (wrong working directory, or `tests/`
  gone). Say so explicitly, state that the release is therefore **unverified**, and ask whether
  to proceed anyway. Never let an empty suite read as a pass.

See [terraform-tests](../terraform-tests/SKILL.md) for what the suite covers and the merge
behaviour a test has to encode.

### 3b. Remaining pre-release checks

All of these must also pass. Report failures and stop; do not tag a broken tree.

```bash
git status --porcelain              # must be empty — tag only committed state
git rev-parse --abbrev-ref HEAD     # must be master (the companion repo uses main)
git log origin/master..HEAD --oneline   # must be empty — push commits before tagging

terraform fmt -check -recursive
terraform validate
```

### 4. Check version constraints and docs

A release is also a documentation change. Before tagging:

- On a **major** bump, update every `version = "~> X.0"` constraint in `README.md` and in
  `examples/**/*.tf` to the new major. A `~> 1.0` constraint will never resolve a `2.x`
  release, so stale docs silently pin consumers to the old major. Note that
  `examples/basic/main.tf` uses `source = "../.."` with no version — that is correct for a
  local example; do not add one.
- Check that `README.md`'s Inputs and Outputs tables still match `variables.tf` and
  `outputs.tf` — a release is the point where docs drift becomes visible to consumers.
- Check that `examples/basic/naming.full.yaml`, the annotated reference for every configurable
  key, covers anything the release adds to the schema.
- The companion module `LemurDaniel/naming/random` **consumes** this one, so this side is
  released **first**. If a change here is breaking for it, release this version, then bump its
  constraint there — never the other way round.

Commit any such changes before tagging, so the tag contains them — using
[git-commit-conventions](../git-commit-conventions/SKILL.md) for the message, and splitting
docs/constraint changes from logic changes as that skill requires. Push the commit before
tagging; a tag on an unpushed commit cannot be resolved by the Registry.

### 5. Tag and push

Use an **annotated** tag — the Registry and `git describe` both prefer them, and the message
becomes the release note. Write the annotation the way
[git-commit-conventions](../git-commit-conventions/SKILL.md) describes a commit message:
English, imperative, no attribution trailers.

```bash
git tag -a v1.0.4 -m "v1.0.4

- <change one>
- <change two>"

git push origin v1.0.4
```

Push the tag by name, not with `--tags`, so a stray local tag is never published by accident.

### 6. Confirm

- The Registry re-scans on a webhook and usually shows the version within a few minutes; it can
  take longer. The new version appears at
  `https://registry.terraform.io/modules/LemurDaniel/naming-schema/random/<version>`.
- If the repo has GitHub releases and the `gh` CLI is available, optionally mirror the tag:
  `gh release create v1.0.4 --notes "..."`. `gh` is **not** required for the Registry to pick
  up the version — skip this if `gh` is not installed.
- Report the tagged version, the bump level with its reason, and what still needs the user's
  attention.

## Related repositories

The companion generator module lives in `terraform-random-naming`, is published as
`LemurDaniel/naming/random`, and is released the same way — but its default branch is
**`main`**, not `master`. Check the branch per repo instead of assuming.
