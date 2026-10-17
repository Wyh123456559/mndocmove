# Reassign explicit section references

Documentation maintainers can change one section's references while retaining
both old and replacement pages. Three supported workflows are:

1. Rename an anchor within a page: `r.md, old → r.md, new`. Both `#old` and
   explicit `r.md#old` references change; references without a fragment and
   references to other sections retain their exact original bytes.
2. Consolidate a section into an existing manual: `old.md, setup →
   manual/new.md, installation`. Fragment-only references inside `old.md`
   become document-relative URLs to the replacement. Whole-page references,
   both page paths, headings and surrounding text remain in place.
3. Replace an SVG symbol: `icons/old.svg, mark → icons/new.svg, logo`.
   Markdown images and supported static HTML URL attributes update under the
   selected profile; SVG bytes remain opaque and unchanged.

Use `DocTree::incoming("old.md")` to inspect decoded fragment identities and
source ranges first. Choose the mapping explicitly, and prepare both files in
the complete inventory. `AnchorRetarget` has four immutable public fields:
`source`, `fragment`, `destination`, `replacement`. Fragments are decoded,
case-sensitive identifiers without the URL's leading `#`; a literal `#` inside
an identifier is allowed and percent-encoded on output. No heading slug,
rendered route, server redirect or anchor-existence inference is performed.
The caller must verify that replacement identifiers exist in their renderer.

Write `anchors.json` **outside** the documentation root:

```json
[["old.md","setup","manual/new.md","installation"]]
```

```text
moon run cmd/main --target wasm -- incoming DOCS old.md
moon run cmd/main --target wasm -- retarget-anchors DOCS anchors.json anchors-plan.json
moon run cmd/main --target wasm -- review anchors-plan.json
moon run cmd/main --target wasm -- replay DOCS anchors-plan.json updated-docs
moon run cmd/main --target wasm -- incoming updated-docs manual/new.md
moon run cmd/main --target wasm -- check updated-docs anchors-plan.json --result
moon run cmd/main --target wasm -- restore updated-docs anchors-plan.json restored-docs
```

The library equivalent is `anchor_retargets_from_json(text)` then
`plan_anchor_retargets(tree,mappings,profile=CommonMark)`. The strict array
decoder refuses objects, extra fields and non-strings; planning validates paths,
existing file endpoints and fragment values. Directory/missing endpoints refuse
with `MissingAnchorSource` / `MissingAnchorTarget`. Duplicate source/fragment
keys and identity declarations refuse with `AnchorConflict` / `IdentityAnchor`.
At most 4096 mappings and 4096 UTF-16 units per decoded fragment are accepted;
C0 and DEL controls, malformed percent escapes and invalid UTF-8 refuse with
`InvalidFragment`. Encoded slashes are allowed inside fragment identifiers.

Matching uses exact resolved file and decoded fragment identity. No fragment
differs from an explicit empty `#`; only the latter matches `fragment=""`.
Queries retain their cooked values, and unchanged path parts are retained when
the target file stays the same. When the target changes, relative paths are
recomputed; root paths remain rooted under `commonmark-root` / `static-html-root`.
Changed URL spans are escaped and may normalize entity/percent spelling.
Everything outside those spans, including CRLF/BOM, is byte-preserved.

Mappings are simultaneous one-hop substitutions: `a→b, b→c` changes original
`a` to `b`, without cascading to `c`. Unselected unsupported/broken local input
also refuses the complete plan. Every Markdown file is checked and each rewrite
is reparsed; there is no partial plan. External URLs and code examples remain
unchanged. Empty mappings canonicalize to an ordinary byte-preserving no-op
without parsing. Ordinary 4096-file / 64-MiB-tree / 1-MiB-Markdown limits apply
to both input and output.

Saved form: `["mndocmove-anchors",1,profile,input_files,four_string_mappings]`.
Intentions sort by source path then fragment using MoonBit `String.compare`.
Loading recomputes edits from the exact snapshot; `anchor_retargets()` returns
a copied array, while `moves()`, `relinks()` and `retargets()` are empty.
Review labels each `retarget-anchor` and preview uses `mndocmove-anchors-preview`.
Replay guards every input byte; restore guards every result byte and returns
the original URL spelling. Existing plan kinds retain their encoding/behavior.

An anchor plan can start a chain followed by physical moves. Parallel merge
refuses with `MergeAnchors`; physical-rename adoption refuses with `AdoptPlanKind`.
The file-move audit API does not audit anchor mappings. Plans and exports use
the existing exclusive-output and outside-root rules.

Run `moon run scripts/anchors-e2e.mbtx -- wasm` or `native` for an offline,
temporary five-file workflow: the existing MIT Microsoft README/example plus
authored section-consolidation documents. It checks query/review/export/result,
exact restoration of every file, unchanged source, and refusal after later
edits. Sources/licenses are in [THIRD_PARTY.md](../THIRD_PARTY.md); no external
implementation, new dependency or new downloaded fixture is introduced.
