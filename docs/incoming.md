# Query incoming source references

Before moving a guide, replacing an image or consolidating a directory, use
`DocTree::incoming(target,recursive=false,profile=CommonMark)` to locate the
URL destinations that would need review. The target is an existing file or
directory path; `.` or an empty string selects the inventory root. Exact
selection includes only links to that target; recursive selection additionally
includes descendant targets. No extension/index-page or site-route inference
is performed. Non-Markdown files remain opaque resources.

```text
moon run cmd/main --target wasm -- incoming examples/vscode/tree example.mjs
moon run cmd/main --target wasm -- incoming DOCS assets --recursive --profile static-html-root
```

The CLI reads the complete tree and prints deterministic JSON, without writing
files. Exit 0 means the complete query succeeded (possibly zero matches), 1
is a diagnostic/I/O failure, 2 is usage error. Invalid/absent targets, broken
local references, unsupported syntax and unsafe input refuse the complete
report, even if some references would not match the selector. Nothing is
silently omitted to make a partial report appear complete.

`IncomingReferences::references()` returns a copied array of immutable
`Reference` values: source `path`, exclusive UTF-16 `start/end`, exact `raw`
source, parser-cooked `url`, resolved `target`, decoded optional `fragment`.
Root targets use the empty string; missing fragments are `None`, an explicit
empty `#` is `Some("")`. Query/fragment-only and empty destinations refer to the
current document. Fragment names are opaque identifiers, not inferred heading
slugs or validated heading existence. Invalid escapes, non-UTF-8 fragments,
control characters and fragments above 4096 UTF-16 units refuse.

Reported locations are **destination spans**: repeated reference-style uses
share the reference definition's URL location. Unused definitions are included.
Code spans/fences and external/scheme/network URLs are excluded as before.
Static HTML/media/srcset and rooted URLs require their explicit profiles.
BOM/CRLF/emoji and URL entity/percent spelling remain represented exactly.

The public `max_references` budget is 1..65536 (default 65536). It counts all
scanned local destinations, including unmatched ones. Excess refuses with
`ReferenceLimit`, never truncation. Use a smaller complete tree or raise a
caller-specified smaller budget when appropriate. Ordinary tree/path/Markdown
limits apply. The report is not a plan or an authorization to edit later files.

Wire report: `["mndocmove-incoming",1,profile,target,recursive,rows]`, where each
row is `[path,start,end,raw,url,resolved_target,fragment_or_null]`. No report
loader exists; executable plan loaders refuse it. Run the normal planner
against the exact current tree for a guarded migration.

`moon run scripts/incoming-e2e.mbtx -- wasm` (or `native`) queries the pinned
MIT Microsoft README/example and an authored fragment link, validates every
source range, migrates the tree, queries the moved resource, checks the final
snapshot and restores all original bytes. Existing fixture source/licenses
remain in THIRD_PARTY.md. No new external code, fixtures or dependencies.
