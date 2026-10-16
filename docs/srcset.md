# Responsive image relocation

The static HTML profile supports `picture`, `source[srcset]`, `img[srcset]` and
the fallback `img[src]` together. It scans individual candidate URL spans in
Markdown HTML regions. Every local candidate must exist in the declared tree;
all candidates use the same simultaneous moves and snapshot guards. No image
selection is executed, and standalone `.html` files remain opaque assets.

Supported subset (quoted attributes only):

- One or more candidates, at most 256 per attribute. Literal commas separate
  candidates and must be followed by ASCII whitespace and another candidate.
- A candidate has one URL and either no descriptor (implicit `1x`), one positive
  integer `w` width (1–9 digits), or one positive decimal `x` density.
  A set cannot mix widths and densities, including implicit density.
  Decimal numbers have 1–9 integer digits and optionally
  1–6 fractional digits. Leading/trailing zeros are preserved in source.
- Equal densities are refused, including `1x` / `01.00x` / an omitted descriptor.
  Equality uses exact decimal canonicalization, independent of floating point.
- Equal widths are refused even with different leading zeros (`320w` / `0320w`).
- Optional `sizes` on `img` / `source` requires a width-based `srcset` on the
  same tag, regardless of attribute order. Without it, browsers use their default
  source size. At most 32 comma-separated entries / 4096 UTF-16 units are allowed.
  Each conditional entry is `(min-width: LENGTH) SIZE` or
  `(max-width: LENGTH) SIZE`, followed by an unconditional final SIZE.
  LENGTH supports `px`, `em`, `rem`; SIZE also supports `vw`, `vh`, `vmin`, `vmax`.
  Numbers are nonnegative with 1–9 integer and optionally 1–6 fractional digits;
  unitless `0` is accepted. Only ASCII HTML whitespace is trimmed. Accepted
  metadata is preserved literally; CSS is never evaluated or rewritten.
- `source[media]` / `source[type]` are preserved metadata. Attribute order/case,
  quotes, descriptors, commas, whitespace, comments and fallback markup remain
  byte-for-byte outside edited URL spans.

`sizes` functions (`calc`, `var`, `url`), `auto`, percentages, compound/range media
conditions, CSS escapes/entities, exponent/signed numbers, empty candidates,
extra descriptors, duplicate attributes, data URLs, comma-bearing URLs and
HTML entities introducing commas or ASCII whitespace are refused with positioned
`UnsupportedHtml` diagnostics. Filename spaces/commas can use URL percent encoding.
Ordinary query entities such as `&amp;` remain supported. External URLs are
preserved after the same syntax checks; no requests are made during migration.

This is a conservative subset of the
[WHATWG srcset requirements](https://html.spec.whatwg.org/multipage/images.html#srcset-attributes),
checked against the Living Standard updated 2026-10-14. It intentionally refuses
some browser-accepted forms instead of emulating browser error recovery. It does
not validate image dimensions, MIME values, browser layout or DOM nesting.

Run the README's Svelte example. The original header, dark/light PNG files,
fixed upstream commit, SHA-256 values and MIT license are recorded in
[fixture provenance](../examples/svelte/SOURCE.md). Moving `header.md` into
`manual` and `assets` into `art` rewrites both URL-bearing attributes to
`../art/...`. Review and restore use the same plan; the CLI E2E runs offline
on the committed fixture and checks all source/output/restored image bytes.
The additional authored `tree/width.md` uses both actual 2500px-wide PNGs with
`2500w` and `(max-width: 40em) 100vw, 800px`. The same commands relocate its
references to `art/...`, retaining the complete sizes and descriptor text.

The default CommonMark profile still refuses raw HTML. Previously accepted
static HTML plans and wire version 1 are unchanged. The expanded profile does
not silently skip unsupported candidates or produce a partially migrated list.
