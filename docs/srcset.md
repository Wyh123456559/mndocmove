# Responsive image relocation

The static HTML profile supports `picture`, `source[srcset]`, `img[srcset]` and
the fallback `img[src]` together. It scans individual candidate URL spans in
Markdown HTML regions. Every local candidate must exist in the declared tree;
all candidates use the same simultaneous moves and snapshot guards. No image
selection is executed, and standalone `.html` files remain opaque assets.

Supported subset (quoted attributes only):

- One or more candidates, at most 256 per attribute. Literal commas separate
  candidates and must be followed by ASCII whitespace and another candidate.
- A candidate has one URL and either no descriptor (implicit `1x`) or one positive
  decimal `x` density. Decimal numbers have 1–9 integer digits and optionally
  1–6 fractional digits. Leading/trailing zeros are preserved in source.
- Equal densities are refused, including `1x` / `01.00x` / an omitted descriptor.
  Equality uses exact decimal canonicalization, independent of floating point.
- `source[media]` / `source[type]` are preserved metadata. Attribute order/case,
  quotes, descriptors, commas, whitespace, comments and fallback markup remain
  byte-for-byte outside edited URL spans.

Width descriptors (`w`), `sizes`, exponent/signed densities, empty candidates,
extra descriptors, duplicate attributes, data URLs, comma-bearing URLs and
HTML entities introducing commas or ASCII whitespace are refused with positioned
`UnsupportedHtml` diagnostics. Filename spaces/commas can use URL percent encoding.
Ordinary query entities such as `&amp;` remain supported. External URLs are
preserved after the same syntax checks; no requests are made during migration.

This is a conservative subset of the
[WHATWG srcset requirements](https://html.spec.whatwg.org/multipage/images.html#srcset-attributes),
checked against the Living Standard updated 2026-10-14. It intentionally refuses
some browser-accepted forms instead of emulating browser error recovery. It does
not validate image dimensions, MIME values, CSS conditions or DOM nesting.

Run the README's Svelte example. The original header, dark/light PNG files,
fixed upstream commit, SHA-256 values and MIT license are recorded in
[fixture provenance](../examples/svelte/SOURCE.md). Moving `header.md` into
`manual` and `assets` into `art` rewrites both URL-bearing attributes to
`../art/...`. Review and restore use the same plan; the CLI E2E runs offline
on the committed fixture and checks all source/output/restored image bytes.

The default CommonMark profile still refuses raw HTML. Previously accepted
static HTML plans and wire version 1 are unchanged. The expanded profile does
not silently skip unsupported candidates or produce a partially migrated list.
