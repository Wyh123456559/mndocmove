# Restore an unchanged migration

A maintainer may try a documentation reorganization, review it in an editor,
and decide to keep the previous layout. The saved plan contains the complete
original file snapshot and deterministically reconstructs the planned output.
Restoration first proves that the supplied migrated snapshot equals that
output, then returns the original snapshot exactly.

`MovePlan::restore(current : DocTree) -> DocTree raise MoveError` is portable
library functionality. `restore MIGRATED_ROOT PLAN_JSON NEW_OUTPUT_DIRECTORY`
is its Wasm/native filesystem workflow. It does not require the old source
directory or a reverse move list. Wire version 1 is unchanged; plans saved
before restoration was introduced can use the same workflow.

Run the README's plan/replay example, then choose an unused output path:

```text
moon run cmd/main --target wasm -- restore relocated-docs plan.json restored-docs
```

`restored-docs/README.md` and `restored-docs/example.mjs` match the original
fixture bytes. Both `relocated-docs` and the plan remain unchanged. Export
uses [verified staging and no-replace publication](export.md). It never writes
over the original source or an existing output directory.

The guard compares every path and byte, including unchanged files and opaque
assets. `RestoreMismatch` identifies the first differing path in sorted order:
missing file, unexpected file or changed bytes. Exit code is 1 and no export
starts. Preserve later edits separately and choose an unmodified migrated
copy. A refused attempt does not mutate the plan or the input tree; a later
correct input can still succeed.

This is snapshot restoration, not inverse URL normalization. Original BOM,
CRLF, missing final newline, entity spellings, percent escapes, directory/file
swaps and non-UTF-8 asset bytes are recovered from the saved original data.
The immutable result is a separate inventory; changing its returned array
cannot alter the saved plan.

The guard proves equality with a planned result, not execution history or
authenticity of a plan. An identical snapshot is accepted even if no replay
command created it. Restoration neither merges edits nor recovers permissions,
timestamps, ACLs, hard links, empty directories or unsupported input semantics.
It is not crash recovery or an in-place undo command. The same inventory
limits, syntax profiles and external-plan trust boundary apply as for replay.

`moon run scripts/e2e.mbtx -- wasm` and `-- native` migrate and restore both
real fixtures. They compare original file paths/bytes, refuse modified results,
preserve later edits and verify successful retry plus existing-output refusal.
