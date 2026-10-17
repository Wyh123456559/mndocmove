# Batch preflight for a proposed migration

A large guide reorganization can fail in several documents at once. Repeatedly
fixing the first failure and rerunning the planner hides the remaining work.
`audit_moves(tree,moves,profile=CommonMark)` checks the same complete migration
as `plan_moves`, but continues after a document's first content refusal. It
reports one diagnostic per failing Markdown file, in the inventory's shortlex
order (UTF-16 length, then code units). It also checks unmoved documents whose
incoming links may need rewriting. All files resolve against the same original
snapshot and simultaneous move map, never against partially rewritten data.

Use it to prepare a guide directory move, identify profile-incompatible HTML
across README files, or gather missing assets from multiple teams before moving
shared resources. This is migration readiness for a concrete move map, not a
general Markdown linter, site renderer, network checker or all-reference audit.

```text
moon run cmd/main --target wasm -- audit examples/vscode/tree examples/vscode/moves.json
moon run cmd/main --target wasm -- audit DOCS moves.json --static-html
```

CLI exit 0 means ready, 1 means a blocked audit or structural/I/O diagnostic,
2 means usage error. An audit reads files without creating a plan/output or
modifying sources. Fix the reported documents/assets, rerun, then use the normal
`plan` / `review` / `replay` workflow on the corrected tree. The filesystem
inventory includes hidden files and retains existing symlink/special-file/
empty-directory refusal and resource limits; select a documentation subtree.

The immutable `MoveAudit` exposes `is_ready()`, a copied `diagnostics()` array,
`plan()` and `to_json_string()`. Diagnostics retain the ordinary planner's exact
code/path/message and UTF-16 offset (`-1` if unavailable). A ready audit's plan
is byte-for-byte equivalent to `plan_moves` for the same input, including saved
wire and preview. It can be reviewed, serialized, chained, replayed and restored
normally. Replay still checks the entire original snapshot for later edits.
If any document refuses, `plan()` is `None`: successful rewrites are discarded,
and **no incomplete tree or partial edits are exposed as a plan**.

Deliberate limits:

- Each document contributes at most its first refusal, so at most 4096
  diagnostics. Fixing it may uncover additional problems in that document.
- Invalid move maps, path collisions, missing sources, file-kind changes and
  other structural preconditions raise before content scanning, using ordinary
  planner error precedence. Successful rewrites that exceed output tree/file
  budgets raise as usual. These are diagnostics, not completed audit reports.
- Empty moves are an ordinary byte-preserving no-op: ready with zero checked
  Markdown files, including unsupported/invalid-UTF-8 Markdown. Readiness in
  this case does not claim document validity. This preserves existing behavior.
- CommonMark remains the default; supported static HTML/media requires explicit
  `StaticHtml` / `--static-html`. Unsupported content is refused, never skipped.

Report-only JSON version 1 has exact positions:

```text
["mndocmove-audit",1,"ready"|"blocked",profile,total_files,checked_markdown,issues]
[code,path,UTF16_offset,message]
```

The report contains no source file bytes or executable edits. Messages may
include referenced paths. Existing plan/chain loaders refuse report JSON.
There is no report loader; callers rerun the audit on the current complete
snapshot. Ordinary saved-plan wire and fail-fast `plan_moves` semantics remain
unchanged. No extra dependency or external implementation was introduced.

Run `moon run scripts/audit-e2e.mbtx -- wasm` (or `native`) for an offline
workflow using the pinned MIT Microsoft README/example and authored invalid
documents. It checks continued diagnostics, deterministic reporting, read-only
input, structural errors, explicit profiles, recovery after fixes, saved-plan
review/export/result-check and exact restoration of every file. CI runs the
script on both CLI targets on Linux, macOS and Windows. Fixture/dependency
licenses and sources remain recorded in [THIRD_PARTY.md](../THIRD_PARTY.md).
