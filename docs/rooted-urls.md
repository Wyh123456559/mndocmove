# Explicit root-relative URL policy

Opt in with `CommonMarkRoot` or `StaticHtmlRoot` when the complete inventory
corresponds exactly to the site's URL root. Single-leading-slash URLs such as
`/assets/logo.png` resolve from that root, while ordinary relative URLs retain
their existing document-relative rules. Moving a document alone leaves rooted
URLs byte-identical; moving their target rewrites the path with its leading
slash preserved. `/?query#fragment` stays attached to the inventory root.

This follows the distinction documented by [MDN](https://developer.mozilla.org/en-US/docs/Web/API/URL_API/Resolving_relative_references).
It does not infer a web server, route aliases, extensionless Markdown, `.html`
conversion, deployment subdirectory/base URL or headings. Select the complete
URL-root tree explicitly; a repository's arbitrary `docs` subtree is not
automatically the site's `/docs/` mount. No server/network check is made.

```text
moon run cmd/main --target wasm -- audit DOCS moves.json --profile static-html-root
moon run cmd/main --target wasm -- plan DOCS moves.json root-plan.json --profile static-html-root
moon run cmd/main --target wasm -- review root-plan.json
moon run cmd/main --target wasm -- replay DOCS root-plan.json relocated
moon run cmd/main --target wasm -- restore relocated root-plan.json restored
```

`--profile NAME` is accepted at the end of `plan`, `plan-git`, `relink`,
`relink-git`, `retarget`, `audit` and `extend`. Names are `commonmark`,
`static-html`, `commonmark-root`, `static-html-root`; unknown names refuse before
output creation. Existing `--static-html` and `extend --commonmark` remain.
These are alternative selectors, not flags to combine. Saved plans/chains
retain the explicit name, and later stages inherit it unless overridden.

`CommonMarkRoot` retains CommonMark's conservative HTML refusal.
`StaticHtmlRoot` adds the same supported HTML/media/srcset subset as StaticHtml.
The original two profiles still reject rooted local references. Adding public
enum variants means embedding code with exhaustive profile matches must add
cases. Existing profile names and their canonical plan bytes are unchanged.

All root-contained path validation, source-span checks, reparse invariants,
byte/size budgets and exact replay/restore guards still apply. Root traversal
above `/` refuses (`OutsideRoot`) rather than guessing a clamped server path.
Encoded separators/NUL, malformed UTF-8, missing targets and file-with-trailing-
slash references refuse. Directory-prefix moves must preserve directory links
as before. Network-path URLs beginning `//` remain external and unchanged.
Queries/fragments and original spelling outside changed destination spans are
preserved. Empty moves remain byte-preserving no-ops without parsing.

Root profiles work with batch audit, reference substitutions, physical-move
adoption, already-moved repair and ordered chains. Run
`moon run scripts/rooted-e2e.mbtx -- wasm` or `native` for an offline example
using the MIT Microsoft README/example and an authored rooted navigation page.
It verifies explicit-profile refusal/recovery, ordinary and rooted URL forms,
saved review/export/check/exact restore, physical-move adoption and exact source
bytes. Existing fixture provenance/licenses remain in THIRD_PARTY.md; MDN is
semantic reference material, with no copied implementation or fixture text.
