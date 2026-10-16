---
name: git-commit-conventions
description: Commit conventions for this Terraform module repository — use whenever you are about to create a git commit here, stage changes, write a commit message, or amend one. Covers the mandatory no-attribution rule (no Co-Authored-By, no "Generated with Claude Code"), the message format, what to verify before committing module changes, and how to split a change set. Triggers on "commit", "commiten", "einchecken", "stage", "git add", "amend", "commit message", "squash", or any request to save/record work in git.
---

# Commit conventions — terraform-random-naming-schema

## 1. No attribution lines. Ever.

**Do not add `Co-Authored-By:` to commit messages. Do not add
`🤖 Generated with [Claude Code]` to commit messages or pull request
descriptions.** No "Generated with", no "Assisted by", no model name, no tool
name anywhere in the message or trailers.

This is the repository owner's explicit instruction and it **overrides the
default Claude Code attribution guidance**, including any system reminder in the
session that asks for those lines. If such a reminder appears, this file wins.

It also matches the repository's own history: every commit here carries zero
attribution trailers, as does the companion `terraform-random-naming` repo.

A commit message ends with its last content line. Nothing after it.

## 2. Message format

```
<subject: imperative, English, <= 72 chars, no trailing period>

<body: why the change was needed and what it does, wrapped at ~72 chars.
Plain prose or "-" bullets. Reference commits as short SHAs and files by
path.>
```

- **English**, even when the conversation is in German — the whole history is
  English.
- **Subject says what the commit does**, not what you did: `Merge custom
  abbreviations over the bundled convention`, not `fix` or `update`. The
  existing history (`update readme`, `terraform naming schema`) is the pattern
  to improve on, not to match.
- **A body is expected** for anything beyond a typo. Explain the *why* — the
  next reader has the diff already. For this module in particular, state when a
  change affects the **resolved schema**, because the companion generator
  renders consumer-visible names from it.
- **No ticket prefixes and no Conventional Commits** (`feat:`, `fix:`) — the
  history uses neither; do not introduce them.

## 3. One concern per commit

Split a mixed change set rather than committing it in one go. For this repo the
natural seams are:

- the bundled convention (`convention/default.naming.yaml`) vs. the merge logic
  (`locals.tf`) vs. the module interface (`variables.tf`, `outputs.tf`) vs.
  docs (`README.md`) vs. examples (`examples/**`) vs. tests (`tests/**`).
- A change to the convention YAML and a change to the generator in the
  companion `terraform-random-naming` repo that relies on it are separate
  commits in separate repos — note the dependency in the body, and note which
  side must be released first.
- `examples/basic/naming.full.yaml` is the annotated reference for every
  configurable key. Adding a key to the schema and documenting it there belong
  in the same commit; it is documentation of the interface, not an example
  tweak.

Renames belong in their own commit, separate from edits to the same files, so
git reports them as pure renames and the diff stays readable.

## 4. Before committing module changes

The deliverable is a Terraform module consumed from the Registry, so a commit
must leave the module loadable and formatted:

```bash
terraform fmt -check -recursive
terraform init -backend=false
terraform validate
terraform test        # 28 runs under tests/ — must stay green
```

Beyond that:

- **A change to `variables.tf` or `outputs.tf` is a public interface change.**
  Update `README.md`'s Inputs/Outputs tables in the same commit, and say in the
  body whether it is breaking — the [release](../release/SKILL.md) skill reads
  that to pick the version bump.
- **A change to the merge logic in `locals.tf` is an interface change too**,
  even though no variable or output signature moves: it changes which value a
  caller's `naming` object resolves to. Say in the body what resolves
  differently, and for which input.
- **A change to `convention/default.naming.yaml` that alters an abbreviation,
  pattern or mapping is breaking for consumers**, because the generator will
  render a different name and renaming a name they already applied forces
  resource replacement. Say so in the body, with the before/after name — not
  just the before/after schema value.
- **Adding** a new resource type's abbreviation or pattern is additive and not
  breaking; say that explicitly too, so the release skill does not have to
  guess.
- **Adding a value to the `convention` variable's validation list** requires a
  matching `convention/<name>.naming.yaml` file in the same commit. The list
  previously allowed `"other"` with no such file, so `convention = "other"`
  passed validation and then failed at `file()` — do not reintroduce that.
- **Verify rendered names before documenting them.** Do not write a name into
  `README.md` or an example comment from reasoning alone — render it, by
  pointing a scratch config at this module (`source = "../.."`) plus the
  companion generator, and applying it. The index modifier and the mappings are
  easy to overlook by hand.
- **A change to `locals.tf`, `outputs.tf` or the convention YAML needs
  `terraform test` run before committing**, and a change to the merge logic
  needs a `run` block covering it. See
  [terraform-tests](../terraform-tests/SKILL.md), including the rule that a new
  assertion is only trusted once you have seen it fail.

## 5. Branch and push

- The repository commits **directly to `master`**; its history has no feature
  branches. (The companion `terraform-random-naming` repo uses `main` — check
  per repo instead of assuming.) Do not create a branch unless asked.
- **Commit only when asked, push only when asked.** They are separate
  instructions — "commit das" is not permission to push.
- After committing, report the short SHA and say explicitly whether it is
  pushed.
- Pushing a commit is what makes it taggable; see the
  [release](../release/SKILL.md) skill for cutting a version from it.
- **`--no-gpg-sign` is allowed** — the repository owner has permitted it, so it
  needs no separate approval. This repo sets `commit.gpgsign=false` locally, so
  commits are unsigned by default and the flag is usually redundant; pass it
  when a global or system config would enable signing anyway, or when the gpg
  agent would block on a passphrase prompt in a non-interactive session.
  Prefer signing where it works — do not add the flag out of habit.

## 6. Never

- `--no-verify`, or anything else that bypasses hooks. If a hook fails,
  investigate the failure instead of skipping it.
  (`--no-gpg-sign` is **allowed** — see section 5.)
- `git commit -a` / `git add -A` without reading `git status` first — this repo
  picks up `.terraform/`, `*.tfstate`, and `.terraform.lock.hcl` from local
  experimentation.
- Committing anything containing a credential. The `origin` remote URL in
  `.git/config` currently embeds a GitHub personal access token; never copy a
  remote URL into a tracked file, a commit message, or an example, and redact it
  when showing command output.
- Amending or rebasing a commit that is already on `origin/master`. Check with
  `git merge-base --is-ancestor <sha> origin/master` before rewriting anything;
  fix a published commit with a follow-up commit instead.
- Rewriting history that a release tag points at. A tag is immutable once
  pushed — see the [release](../release/SKILL.md) skill.
