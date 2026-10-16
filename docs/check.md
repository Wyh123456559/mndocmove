# Read-only snapshot checks

Replay and restoration refuse a changed snapshot. For a large documentation
migration, finding only the first difference requires repeated investigation.
`MovePlan::check(current, side=Source)` reports every added, removed and modified
file together. `side=Result` checks the complete projected output instead.

The result is an immutable `SnapshotReport`. `is_match()` indicates exact
equality, `changes()` returns an independent array of `SnapshotChange` values,
and `to_json_string()` produces deterministic report-only JSON. Byte equality
is checked even when lengths match. Paths and lengths are included; file
contents are not. Input order does not affect the sorted report. Ordering follows
the existing inventories: UTF-16 path length first, then code-unit order, rather
than locale-dependent alphabetical order.

Run the README migration example, then check either side:

```text
moon run cmd/main --target wasm -- check examples/vscode/tree plan.json
moon run cmd/main --target wasm -- check relocated-docs plan.json --result
moon run scripts/check-e2e.mbtx -- wasm
```

The CLI reads the saved plan and complete tree without creating files. Exit 0
means exact match; exit 1 means drift or a diagnostic/I/O failure; exit 2 means
invalid usage. A valid comparison always prints one JSON report. Invalid
inventories, unsupported filesystem objects or invalid plans produce the normal
diagnostic instead. A report does not authorize replay or restoration: those
operations still recheck their input snapshots.

Report version 1 is an exact array:

```text
["mndocmove-check",1,"source"|"result",expected_file_count,actual_file_count,changes]
["added",path,actual_byte_length]
["removed",path,expected_byte_length]
["modified",path,expected_byte_length,actual_byte_length]
```

Renames appear as removal/addition; no heuristic identity matching is attempted.
An empty tree or zero-byte file is represented exactly. Up to 8192 changes are
possible between two validated 4096-file inventories. The report has no loader
or execution semantics and is refused as a migration plan. Metadata such as
permissions, timestamps, directories and symlinks remain outside the snapshot
model; a matching report cannot prove that a later concurrent edit will not occur.

The offline E2E uses the real Microsoft fixture, verifies a completed export,
then reports modified/missing/extra files from a temporary copy in one result.
It checks JSON values, exit codes, source-byte preservation and report/plan
separation. Both Wasm and native runs execute in the three-system CI matrix.

`MoveChain::check` and the same CLI command also accept ordered saved chains.
Source/result selects the original/final endpoint; use `stages()` to inspect an
intermediate plan. See [ordered migrations](chains.md).
