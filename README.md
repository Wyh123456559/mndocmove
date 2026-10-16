# mndocmove

Move Markdown documents and assets together while keeping local links pointed
at the same objects. A reusable MoonBit library and a filesystem CLI for
maintainers reorganizing README files, guides and image directories.

The planner computes **incoming and outgoing** links against one original
snapshot. It patches destination spans in the original source; it does not
render Markdown. Review a plan, then replay it only if every source file and
asset byte still matches. Replay exports a complete file tree to a **new**
directory. It never modifies the source directory.

## Try it with real documentation

Requires MoonBit stable (validated with moon 0.1.20261012 / moonc v0.10.15),
and Node.js for JS tests. `moon update` downloads declared Mooncakes packages.
The first fixture is an unmodified Microsoft README plus its linked example, with
[MIT license and pinned provenance](examples/vscode/SOURCE.md).

Run from this repository, choosing unused output names:

```text
moon update
moon run cmd/main --target wasm -- plan examples/vscode/tree examples/vscode/moves.json plan.json
moon run cmd/main --target wasm -- review plan.json
moon run cmd/main --target wasm -- replay examples/vscode/tree plan.json relocated-docs
```

The move list relocates `README.md` to `manual/README.md` and `example.mjs` to
`samples/example.mjs`. The README link becomes `../samples/example.mjs`; other
text and the example bytes are unchanged. Supply your own documentation root
and JSON path pairs to use the same CLI on another tree. Store plans outside
that root. Plans contain full source bytes; treat them as source material.

`plan` prints versioned preview JSON: moves and edits with path, UTF-16 start /
exclusive end, before / after, old / new target. `replay` checks the entire
inventory. Exit codes: 0 success, 1 diagnostic / I/O failure, 2 usage error.
An existing plan file or export directory is refused. Export writes into a
reserved sibling staging directory, reads back the complete file inventory and
bytes, then publishes it with a no-replace rename. A write or validation failure
retains that staging directory and reports its path; it does not publish a
partial final tree. See [export and recovery](docs/export.md). Publication is
not a crash-durable transaction: no filesystem flush guarantee is provided.
Do not edit the source or destination concurrently with inventory/export.

For native execution, replace `--target wasm` with `--target native`.
Windows native requires MSVC C++ Build Tools and Windows SDK; MinGW is not
supported by the async dependency. The CLI runs on the Wasm host runtime or
native; JS/Wasm-GC are library embedding targets, without a bundled CLI.

## Library

See the [tested quick start](README.mbt.md) and
[generated public API](pkg.generated.mbti). Add this module as a dependency
after it is published, or use a local module dependency while developing.
This repository has not yet been published to Mooncakes.

- `DocTree::new(Array[Entry])`: bounded, validated immutable snapshot.
- `Move::new(old, new)` and `plan_moves(tree, moves)`: simultaneous file or
  directory-prefix moves, minimal source edits, complete projected inventory.
- `Profile::StaticHtml` via `plan_moves(tree,moves,profile=StaticHtml)`: explicit
  support for quoted `<a href>` / `<img src>` and responsive image candidates
  in Markdown. The default
  `CommonMark` profile retains its conservative HTML refusal.
- `MovePlan::edits/moves/preview`: independent review data.
- `MovePlan::review(context=3)`: complete file-move manifest plus contextual
  before/after Markdown hunks. CLI: `review PLAN_JSON [CONTEXT_LINES]`.
- `MovePlan::replay(current_tree)`: refuses stale content, additions or deletions.
- `MovePlan::check(current_tree, side=Source)`: all sorted snapshot differences;
  use `side=Result` to verify a completed export without changing any files.
- `MovePlan::restore(migrated_tree)`: checks the complete planned result and
  returns exact original paths and bytes; refuses later edits instead of merging.
- `MovePlan::to_json_string/from_json_string`: deterministic, versioned complete
  plan round trip; loading recomputes edits instead of trusting stored offsets.
- `moves_from_json`: strict move-pair input. See [wire format](docs/wire.md).
- `MovePlan::then_moves` / `MoveChain::then_moves`: ordered migration stages
  without intermediate exports; chains support review/check/replay/restore and
  bounded, deterministic saved plans. See [ordered workflows](docs/chains.md).

## Current supported boundary

UTF-8 `.md` files (including `.mbt.md`), CommonMark inline/reference links,
images and definitions, file and directory moves, root-contained relative
paths, valid UTF-8 percent encoding, query/fragment suffixes, simultaneous
swaps. External/scheme URLs and fragment-only URLs remain unchanged. Code
spans / fences, link titles, non-URL text, line endings, BOMs and all opaque
asset bytes are preserved. Unused reference definitions are also updated.
Links to missing targets are refused; include all local targets in your root.

Raw HTML requires the static HTML profile; wiki links and template markers
are refused when planning a nonempty move list. MDX, site routing, extensionless-to-Markdown inference,
heading renames, root-relative URLs, encoded separators/NUL, paths escaping
the root, symlinks, special files and unknown wire semantics are unsupported.
Links to the inventory root through `.` / `..` are supported and stay attached
to that root when documents move. See [root navigation](docs/root-links.md).
Non-Markdown files are opaque assets: references inside JavaScript, HTML,
CSS or configuration are outside this API's scope. The tool cannot prove
that arbitrary text has no application-specific path references.
Moves cannot change the `.md` / opaque-asset classification.

## Static HTML workflow

```text
moon run cmd/main --target wasm -- plan examples/bat/tree examples/bat/moves.json html-plan.json --static-html
moon run cmd/main --target wasm -- replay examples/bat/tree html-plan.json relocated-html
```

This moves a [real bat README header and logo](examples/bat/SOURCE.md), changing
only its local `src` to `../art/logo-header.svg`. The saved plan records the
profile, so replay needs no extra flag. Attribute case, quote style, comments
and non-URL source remain intact. This is a strict static subset: unsupported
tags / attributes, width-based `srcset` / `sizes`, inline styles, scripts, `<base>`, templates,
unquoted attribute values, duplicate attributes and ambiguous entities fail
explicitly. See [exact HTML boundary](docs/html-profile.md).

Responsive images use the same profile and saved-plan workflow:

```text
moon run cmd/main --target wasm -- plan examples/svelte/tree examples/svelte/moves.json responsive-plan.json --static-html
moon run cmd/main --target wasm -- replay examples/svelte/tree responsive-plan.json relocated-responsive
```

This moves a [verbatim Svelte README header and both PNGs](examples/svelte/SOURCE.md).
The dark-mode `source[srcset]` and fallback `img[src]` stay aligned. Multiple
`img/srcset` or `source/srcset` candidates with decimal `x` densities are supported;
their descriptors, separators, media/type metadata and non-URL text are preserved.
Unknown grammars refuse the complete plan. See [responsive subset](docs/srcset.md).

## Review before replay

The `review` command works from the saved plan without reading or writing the
source directory. It lists every individual moved file, including opaque assets,
and shows changed Markdown with 0–20 context lines (default 3). Same-line edits
and nearby hunks are coalesced; repeated text cannot move an edit to another
occurrence. Quoted paths, CRLF and missing-final-newline markers keep the
evidence explicit. Terminal control characters / bare CR refuse text review;
the escaped JSON preview and replay remain available.

The report is **for review**, not a runnable patch: its asset manifest is not
binary patch data. Use `replay` to perform the complete migration and enforce
the snapshot guard. See [report format and checks](docs/review.md).

## Continue a migration in stages

```text
moon run cmd/main --target wasm -- extend examples/vscode/tree plan.json examples/vscode/second-moves.json chain.json
moon run cmd/main --target wasm -- review chain.json
moon run cmd/main --target wasm -- replay examples/vscode/tree chain.json relocated-chain
```

The next moves name paths in the preceding result. All stages retain their
evidence; only the final tree is exported. The original snapshot is still
required to match. Syntax profiles inherit unless explicitly overridden.
See [chain limits, wire format and full restore example](docs/chains.md).

## Check saved snapshots

```text
moon run cmd/main --target wasm -- check examples/vscode/tree plan.json
moon run cmd/main --target wasm -- check relocated-docs plan.json --result
```

These read-only checks list all added, removed and modified files as sorted,
versioned JSON. Equal-length byte changes are detected. Exit 0 means exact
match; exit 1 reports drift or an input/I/O diagnostic. The result is a report,
not an executable plan. See [snapshot check API and report format](docs/check.md).

## Restore a migration

```text
moon run cmd/main --target wasm -- restore relocated-docs plan.json restored-docs
```

This verifies `relocated-docs` against the complete planned result, then exports
the original snapshot to a new `restored-docs` directory. It restores original
URL spellings and all file bytes from the saved plan. It requires no access to
the original source directory. Added, deleted, renamed or edited migrated files
produce `RestoreMismatch` with the first differing path. Preserve those later
edits separately; restoration does not merge them. Existing outputs are refused.
See [restoration semantics and example](docs/restore.md).

Limits: 4096 files, 64 MiB total bytes, 1 MiB per Markdown, 4096 units per
relative path, no duplicate/ASCII-case-alias paths, file/directory conflicts,
Windows device names or ambiguous source mappings. Non-ASCII filesystem case
folding / Unicode normalization are not modeled. CLI inventory includes hidden
files and has no implicit exclusions: use a documentation subtree, not a whole
checkout with `.git` and build artifacts. Empty directories are refused by the
CLI. Export preserves file bytes and paths, not permissions, timestamps, ACLs
or hard-link identity. Empty moves preserve bytes without parsing Markdown.

Failures return `MoveError::Refused(Diagnostic)` with a stable code, path,
UTF-16 offset (`-1` when unavailable), and an actionable message. No partial
in-memory plan is returned.

## Validation and development

```text
moon fmt
moon info
moon check --target wasm --deny-warn
moon test --target wasm --deny-warn
moon test --target wasm-gc --deny-warn
moon test --target js --deny-warn
moon test --target native --deny-warn
moon run scripts/e2e.mbtx -- wasm
moon run scripts/e2e.mbtx -- native
moon run scripts/check-e2e.mbtx -- wasm
moon run scripts/check-e2e.mbtx -- native
moon run scripts/chain-e2e.mbtx -- wasm
moon run scripts/chain-e2e.mbtx -- native
```

The E2E script uses a fresh temporary directory and asserts the exact README
change, byte preservation, stale-plan refusal, exclusive output and exit codes.
It also forces a real filesystem write failure, checks the retained staging
diagnostics and retries successfully at the same unused output path.
Both fixtures are then restored and compared with their original bytes; a
modified migrated tree is refused without losing its later edits.
It retains temporary outputs for inspection. See [validation](docs/validation.md)
for actual local evidence and CI limitations.

## Why another Markdown project?

This is a **source-tree relocation workflow**, complementary to MoonBook's
site rendering/link checks and Yuegui's site graph. It does not expose a new
general parser or static-site generator. The underlying demand is already
served by VS Code's automatic link updates. See [ecosystem evidence](docs/research.md)
and [design / roadmap](docs/design.md). No claim of ecosystem uniqueness or
performance superiority is made.

Apache-2.0. Dependency and fixture attribution: [THIRD_PARTY.md](THIRD_PARTY.md).
