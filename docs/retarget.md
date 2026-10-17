# Replace references to existing files

Use `plan_retargets(tree,pairs,profile=CommonMark)` when an obsolete guide is
consolidated into an existing page or a resource is replaced by a newer file.
Unlike a move into an occupied destination, this workflow changes URL spans
while **retaining every file path**, including both old and replacement files.
Old Markdown files may themselves contain references that are updated; their
other text and all opaque file bytes remain unchanged.

```text
moon run cmd/main --target wasm -- retarget DOCS replacements.json retarget-plan.json
moon run cmd/main --target wasm -- review retarget-plan.json
moon run cmd/main --target wasm -- replay DOCS retarget-plan.json replaced-output
moon run cmd/main --target wasm -- check replaced-output retarget-plan.json --result
moon run cmd/main --target wasm -- restore replaced-output retarget-plan.json restored
```

Pairs use the existing JSON shape `[["old.md","manual/new.md"],...]`. Both
endpoints must be existing files in the complete tree. Directories/absent files
refuse with `MissingRetargetSource` / `MissingRetargetTarget`. Identity pairs
and repeated source declarations refuse; several old files may target the same
replacement. Up to 4096 pairs are accepted. Cycles and chains are simultaneous,
one-hop substitutions: A→B and B→C send original A references to B, not C.
No files are deleted, no server redirect is generated and no fragment/heading
existence is inferred. Query/fragment suffixes remain attached as before.

Every Markdown file is validated/reparsed, including unmoved incoming links,
using the selected syntax profile. Unrelated broken/unsupported references
still refuse the whole plan; no unsupported data is silently skipped. Empty
pairs canonicalize to a byte-preserving ordinary no-op without parsing.

`moves()` / `relinks()` are empty; `retargets()` returns a copied intent array.
Review labels the operation `retarget` and lists no physical moves. The saved
schema is `["mndocmove-retarget",1,profile,input_files,replacement_pairs]`;
loading validates the complete input and recomputes edits. Preview magic is
`mndocmove-retarget-preview`. Old move/relink/adoption encodings are unchanged.
Replay guards the whole source snapshot; restore guards the whole result and
returns exact original bytes, including original URL spelling.

A retarget plan can be the first stage of a chain followed by physical moves.
Parallel merge refuses with `MergeRetarget`, and adoption refuses with
`AdoptPlanKind`: existing-file substitution is not a physical rename map.
Chains retain replacement intentions and exact wire-size preflight. Outputs
use the existing unused/outside-root rules and verified export workflow.

Run `moon run scripts/retarget-e2e.mbtx -- wasm` or `native` for the offline
Microsoft README/example workflow. The temporary replacement adds an authored
marker to the MIT example; original/replacement bytes and paths are compared
through review/export/check/restore, including refusal after a later old-file
edit. Existing sources/licenses are in [THIRD_PARTY.md](../THIRD_PARTY.md);
no new external implementation, fixture download or dependency is introduced.
