# Plan migrations from Git exact-renames

`moves_from_git_name_status(bytes, root_prefix="docs")` imports the binary
output of `git diff --name-status -z --find-renames=100%`. It returns reusable
file `Move` values; the ordinary planner then validates targets, rewrites incoming
and outgoing references, and supplies saved-plan review/replay/check/restore.
Git is needed only to produce the input, not to use the library or replay a plan.

A complete workflow for a pure reorganization:

1. Keep an unchanged copy of your complete documentation tree before moving
   anything (outside the Git checkout, including all linked resources).
2. Make the intended file renames on a branch. Do not edit document/asset bytes
   in that rename step; mndocmove will calculate reference edits separately.
3. From the repository root, produce the complete unfiltered name-status diff
   for the documentation scope:

```text
git diff --no-ext-diff --no-textconv --no-relative --name-status -z --find-renames=100% --output=renames.z BASE TARGET -- docs
moon run cmd/main --target wasm -- plan-git baseline-docs renames.z docs git-plan.json
moon run cmd/main --target wasm -- review git-plan.json
moon run cmd/main --target wasm -- replay baseline-docs git-plan.json relocated-docs
moon run cmd/main --target wasm -- restore relocated-docs git-plan.json restored-baseline
```

Use `--cached BASE` in place of `BASE TARGET` for staged moves. Use Git's
`--output` to keep NUL bytes intact across shells. `plan-git ROOT STATUS PREFIX
NEW_PLAN [--static-html]` requires the **old** source tree; using the already
renamed working directory refuses missing sources. `PREFIX` is the exact
repository-relative documentation root (`docs` above), or `.` for no prefix.
Outputs must be unused and outside ROOT. No source tree, Git index or branch is
modified by the CLI. The saved result is an ordinary version-1 plan.

Supported input is a sequence of `R100 NUL old-path NUL new-path NUL`, or empty
bytes for no moves. Every record must be a complete exact rename. Modified,
copied, added, deleted, conflicted or lower-similarity records refuse the entire
input with `UnsupportedGitChange`; none are skipped. Do not hide such records
with `--diff-filter=R` or a pathspec that omits part of a move. The importer
cannot discover changes a caller excluded from the supplied bytes.

Paths must be strict UTF-8 and satisfy the project's portable path rules. Spaces,
Unicode and literal `%` sequences are preserved as filenames, not URL-decoded.
Both endpoints must lie below PREFIX; cross-root moves and prefix lookalikes
refuse. Sources and destinations must each be unique (including ASCII case
aliases). Results sort in the same shortlex order as plans. Limits: 16 MiB input,
4096 records, at most 16384 bytes per raw path field, and the ordinary 4096 UTF-16
path limit. Truncation, invalid UTF-8, non-NUL/quoted formats, extra fields and
unknown data refuse; binary input errors report a byte position in the message
with diagnostic offset `-1` (not a falsely labeled UTF-16 position).

No directory moves are inferred from file records. Directory-navigation links
still receive the ordinary missing-projected-target checks; supply explicit
directory-prefix moves through JSON when that is the intended operation.
Name-status does not carry content, file modes or object identities. Input is
declared rename intent, not proof of repository/current-tree equality; plans
preserve the supplied baseline file bytes/paths, not Git modes or metadata.

Run `moon run scripts/git-e2e.mbtx -- wasm` (or `native`). It creates a temporary
Git repo from the licensed Microsoft README/example, uses real `git mv` and
`write-tree`/`diff` without creating commits or changing any Git identity, then
checks planning, review, output/restore bytes, root-scope/existing-output refusal
and rejection of a real diff containing a later content edit.

The independent parser follows the primary
[Git diff documentation](https://git-scm.com/docs/git-diff) (`-z`, name-status,
exact rename detection and root-relative output), checked 2026-10-16 and verified
with Git 2.54.0 on Windows. No Git implementation, prose or upstream tests copied.
