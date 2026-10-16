# Combine parallel migration plans

Two maintainers can plan independent parts of a reorganization from the same
source snapshot: one moves documents, another moves shared images/examples.
`MovePlan::merge(other)` combines their intentions and recomputes every link
against their union. Concatenating two sets of text edits would be incorrect
when both plans change the same URL or the same source line.

Both plans must contain exactly the same original file inventory and bytes and
use the same syntax profile. `MergeSnapshot` names the first differing path;
`MergeProfile` asks the caller to regenerate with a consistent policy. Identical
source/destination pairs coalesce; a source with different destinations produces
`MergeConflict`. Parent/child source mappings, projected collisions, case aliases,
missing projected directories and size/count limits use the ordinary planner's
diagnostics, prefixed with merge context. A valid union is a normal complete
`MovePlan`, with normal save/review/check/replay/restore and chain support.

For compatible plans, merging is commutative and idempotent: canonical saved
bytes do not depend on argument order or inclusion of an identical intention.
Input plans and trees are immutable, including after a refusal. Separate
directory sources can share a destination only if the complete projected file
inventory has no conflict. The union limit is 4096 intentions after coalescing.

CLI (all outputs must be unused and outside ROOT):

```text
moon run cmd/main --target wasm -- merge DOC_ROOT docs-plan.json images-plan.json merged-plan.json
moon run cmd/main --target wasm -- review merged-plan.json
moon run cmd/main --target wasm -- replay DOC_ROOT merged-plan.json merged-output
moon run cmd/main --target wasm -- restore merged-output merged-plan.json restored-input
```

The CLI additionally verifies ROOT still matches the shared source snapshot
before writing the merged plan. Inputs are single simultaneous plans; ordered
chains are not flattened or silently discarded. Use `extend` for ordered stages.
This does not merge document content, reconcile different source revisions or
apply Git patches. A normal result keeps the existing version-1 plan wire format.
Historical link-repair plans refuse with `MergeRelink`; follow such a repair
with an ordered `then_moves` / `extend` stage instead.

Run `moon run scripts/merge-e2e.mbtx -- wasm` (or `native`) for an offline demo
using the real licensed Microsoft README/example: independent document/resource
plans, equivalent reversed merge, review, export, result check, exact restore,
existing output protection and stale-source refusal. No new external fixtures or
upstream code/tests are copied.
