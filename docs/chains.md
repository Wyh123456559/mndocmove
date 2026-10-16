# Ordered migrations without intermediate exports

A documentation reorganization often happens in stages: move guides first,
then reorganize images/examples using their new paths. `MovePlan::then_moves`
starts an immutable `MoveChain`; `MoveChain::then_moves` appends a stage. Every
stage is a complete normal plan against the preceding result. Moves within a
stage remain simultaneous; stages themselves execute in order.

Use the original documentation root for all CLI operations:

```text
moon run cmd/main --target wasm -- plan examples/vscode/tree examples/vscode/moves.json first.json
moon run cmd/main --target wasm -- extend examples/vscode/tree first.json examples/vscode/second-moves.json chain.json
moon run cmd/main --target wasm -- review chain.json
moon run cmd/main --target wasm -- replay examples/vscode/tree chain.json relocated-chain
moon run cmd/main --target wasm -- check relocated-chain chain.json --result
moon run cmd/main --target wasm -- restore relocated-chain chain.json restored-chain
```

The second move list renames the first result's `manual` and `samples` folders
to `guides` and `assets`. There is no intermediate filesystem export. `extend`
verifies the original source snapshot and writes a new plan exclusively outside
that source. It accepts either a single plan or a saved chain. Later move sources
refer to the last projected tree, not the original tree. This is not rebasing or
merging changes made after preview.

Profiles default to the preceding stage's profile. `extend` accepts an explicit
`--static-html` or `--commonmark` override; the library uses `profile=...`.
Unsupported syntax in any stage refuses the complete append and reports its
stage number. A refused append leaves the previous plan/chain usable.

`stages()` returns an independent array of immutable `MovePlan` values for
custom inspection. `review(context=...)` shows all stage manifests/hunks in
execution order, with paths relative to each stage's input. It is review text,
not a flattened runnable patch. A move followed by its reversal retains both
stages even if the final tree happens to equal the original.

`replay` compares the complete original snapshot and returns only the final
tree. `restore` compares the complete final snapshot and returns the exact
original paths/bytes. `check(side=Source|Result)` also compares these endpoints;
intermediate snapshots are available through individual stage plans. Existing
source/result guards, byte preservation and verified exclusive export apply.

Chain version 1 has this exact shape:

```text
["mndocmove-chain",1,first_single_plan,[[profile,move_pairs],...]]
```

Only the first plan stores original bytes. Every additional stage stores its
profile and move pairs; loading recomputes all edits and intermediate snapshots.
There are no trusted serialized offsets. Unknown fields, versions or profiles,
invalid moves and nested chain bases fail. `MoveChain::from_json_string` also
accepts an existing single-plan v1 as one stage; re-encoding uses the chain
envelope. `MovePlan` serialization and its strict single-plan loader are unchanged.

Limits: eight stages; 128 MiB logical bytes summed across the original and all
stage results; existing per-tree limits. Serialization checks the exact wire
size before allocating hex snapshot strings and raises `PlanLimit` above the
existing 200,000,000 UTF-16-unit limit. `to_json_string` therefore raises
`MoveError`; an over-limit in-memory chain is not silently truncated or written
as an unreadable plan. Stages are retained for evidence, so large trees may reach
the logical snapshot budget before eight stages. Wire plans contain source data.

`moon run scripts/chain-e2e.mbtx -- wasm` or `-- native` executes three stages
using the real Microsoft fixture. It verifies review order, endpoint checks,
exact asset bytes/restoration, stale-source refusal and no overwrite of an
existing saved chain. CI executes the full legacy workflows too.
