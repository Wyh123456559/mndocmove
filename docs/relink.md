# Repair links after files were already renamed

Use this when files/directories have already been moved (for example by `git mv`)
and **Markdown bytes still use the old path coordinates**. Supply the complete
simultaneous old-to-current rename map, plus the complete current tree. The API
`plan_relinks(current, already_renamed, profile=CommonMark)` reconstructs a
logical old tree, validates it, then recomputes preserved-source URL edits.
This removes the need to physically undo/repeat a set of renames just to obtain
a guarded migration plan. It is separate from `plan_moves`, whose moves are pending.

```text
moon run cmd/main --target wasm -- relink CURRENT_DOCS already-renamed.json repair-plan.json
moon run cmd/main --target wasm -- review repair-plan.json
moon run cmd/main --target wasm -- replay CURRENT_DOCS repair-plan.json repaired-output
moon run cmd/main --target wasm -- check repaired-output repair-plan.json --result
moon run cmd/main --target wasm -- restore repaired-output repair-plan.json restored-before-repair
```

The JSON map has the existing `[["old/path","current/path"],...]` shape. Add
`--static-html` to repair supported responsive images and embedded media.
Outputs remain unused paths outside CURRENT_DOCS; no in-place source writes.

For a staged pure Git rename, create an unfiltered binary name-status file as
described in [Git input](git.md), then use the current, already-moved doc root:

```text
git diff --cached --no-ext-diff --no-textconv --no-relative --name-status -z --find-renames=100% --output=renames.z BASE -- docs
moon run cmd/main --target wasm -- relink-git docs renames.z docs repair-plan.json
```

`relink-git CURRENT_ROOT STATUS PREFIX NEW_PLAN [--static-html]` uses the same
strict R100 importer. It does not execute Git or prove that working-tree bytes
match the Git index. Callers must supply unchanged old-coordinate Markdown;
partially hand-updated links, arbitrary content edits or incomplete historical
maps are outside the contract. Invalid reconstructed references refuse; the
planner never guesses between old/new namespace resolutions. If edited input
happens to be valid in the old namespace, the tool cannot infer its author's
intent. Keep those edits separately or use a verified unchanged snapshot.

Correctness and failure boundary:

- Each destination prefix must exist in the current inventory and destinations
  cannot overlap, including ASCII case aliases. Otherwise reversing paths would
  have multiple possible owners (`MissingRenamedTarget` / `RelinkAmbiguity`).
- Reconstructing old paths must preserve every file distinctly. An old path still
  occupied by an unmoved file refuses rather than overwriting either payload.
  Source-prefix ambiguity, classification changes and ordinary limits remain
  subject to the existing planner checks. No bytes or fields are dropped.
- Planning validates targets and reparses all rewritten references in the logical
  old-to-current mapping, then checks the projected inventory has exactly the
  current paths. Only supported Markdown URL spans change. Binary/media/track
  bytes, BOM/CRLF, spelling outside URL spans and all file paths are preserved.
- `MovePlan::moves()` is empty for a repair; `relinks()` returns a copy of its
  historical declarations. Edits name current source files/UTF-16 offsets;
  `old_target` refers to the logical old namespace, `new_target` to current paths.
  Preview magic is `mndocmove-relink-preview`; review labels declarations
  `already-renamed` and explicitly says no physical moves remain.
- Replay checks the whole pre-repair current snapshot. Restore checks the whole
  repaired result, then returns **exact pre-repair current paths and bytes**,
  including old URL spellings. It does not reverse the historical physical move
  or merge later edits. Snapshot check works on either endpoint as usual.

Saved repair wire: `["mndocmove-relink",1,profile,current_files,historical_moves]`.
Files retain the existing `[path,uppercase_hex_bytes]` encoding; loading strictly
reconstructs/replans instead of trusting edit offsets. Unknown/extra data refuses.
Ordinary plan wire and review outputs remain unchanged. Empty repair declarations
canonicalize to an ordinary no-op plan, preserving bytes without parsing.

A repair can start an ordered chain via `then_moves` / CLI `extend`; later
stages operate in the repaired result namespace. The compact chain wire embeds
the repair as its first plan; exact wire-size preflight counts its longer magic
and historical map before allocating hex strings. Parallel `merge` refuses repair
plans (`MergeRelink`) because historical and pending intents cannot be unioned.

Run `moon run scripts/git-e2e.mbtx -- wasm` (or `native`) for the documented
offline demonstration. A real temporary `git mv` of the licensed Microsoft
README/example feeds both Git and JSON repair inputs, checks identical plans,
review/no pending moves, both snapshot sides, export/exact pre-repair restoration,
an additional ordered move stage and refusal after a later real content edit.
No Git commits, author configuration, network or private infrastructure is used.
