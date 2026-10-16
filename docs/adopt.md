# Verify physical renames against a saved plan

Review a pending move plan, let an editor or `git mv` perform its physical
renames, then finish its URL changes without undoing the moves. Unlike the
baseline-free [relink workflow](relink.md), adoption compares the complete
physically renamed tree against the saved pre-move inventory: every path and
every byte must match. Equal-size Markdown/opaque changes, additions, deletions,
partial renames and already-rewritten URLs all refuse the operation.

Three useful cases are a reviewed README move performed by Git, multiple old
guide directories merged into one `manual` directory, and a simultaneous
directory swap that must retain each original file's ownership. Adoption uses
the exact baseline-to-current mapping per original file, so merged destination
prefixes and existing unmoved destination files need no ambiguous inverse map.
Ordinary planner collision and supported-syntax checks still apply.

```text
moon run cmd/main --target wasm -- plan OLD_DOCS moves.json pending.json
moon run cmd/main --target wasm -- review pending.json
```

Now perform only the declared physical moves, retaining all file bytes. Use the
complete current documentation root, excluding the Git metadata as usual:

```text
moon run cmd/main --target wasm -- check-renamed CURRENT_DOCS pending.json
moon run cmd/main --target wasm -- adopt CURRENT_DOCS pending.json adopted.json
moon run cmd/main --target wasm -- review adopted.json
moon run cmd/main --target wasm -- replay CURRENT_DOCS adopted.json repaired-output
moon run cmd/main --target wasm -- check repaired-output adopted.json --result
moon run cmd/main --target wasm -- restore repaired-output adopted.json before-repair
```

Both new commands read their inputs without modification. `check-renamed`
returns all sorted drift in the existing `mndocmove-check` report format, with
`source` denoting the expected **physical pre-repair input**, rather than the
pending plan's original source. Exit 0 means an exact match; 1 means drift or
an input/I/O diagnostic; 2 means usage error. Invalid inventories are refused
before comparison. `adopt` raises `AdoptionMismatch` at the first differing
path and directs callers to the full report. Correct the unintended changes
and retry with the same pending plan. No partial output plan is written.

The returned plan has no pending `moves()`. Its `relinks()` are the original
historical moves; edits use current file paths and unchanged original UTF-16
offsets. The syntax profile is inherited. Replay is exactly equivalent to the
original pending plan's result, guarded against later changes to the complete
physical input. Restore returns **current paths with exact pre-repair bytes**;
it does not undo physical renames. Review identifies verified adoption and
already-performed moves. Preview uses `mndocmove-adopt-preview`.

Saved wire is `["mndocmove-adopt",1,profile,baseline_files,historical_moves]`.
Only the original pre-move snapshot is stored, using the existing hex encoding.
Loading validates/replans it and derives the physical input with unchanged
bytes; no serialized edits are trusted. Replay subsequently verifies the real
supplied input. This records correspondence to a user-supplied baseline, not
cryptographic authenticity or proof of who performed the moves. Original
`mndocmove` and `mndocmove-relink` encodings are unchanged. Empty moves remain
a canonical ordinary no-op and still require byte-exact adoption input.

Only ordinary single pending plans can be adopted. Repair/adopted plans refuse
with `AdoptPlanKind`; the single-plan loader rejects chains. An adopted plan
can start a chain with `then_moves` / `extend`, retaining its baseline in the
first stage. The existing stage, logical snapshot-byte and exact wire-size
budgets apply. Parallel merge refuses historical repairs as before.

Run `moon run scripts/git-e2e.mbtx -- wasm` (or `native`) from this repository
for the complete offline demonstration. It performs actual Git moves on a
temporary copy of the pinned MIT Microsoft README/example, verifies adoption,
saved-plan review, equivalent export, exact pre-repair restore, refusal of
existing/inside-source output, and drift rejection after a real later edit.
No Git commits, account credentials, network or private infrastructure are
required. Source/fixture bytes are asserted unchanged. Reused fixtures and
dependencies retain their existing [provenance and licenses](../THIRD_PARTY.md);
the adoption implementation/tests are authored here without copied external code.
