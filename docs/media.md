# Relocate embedded documentation media

The explicit `StaticHtml` profile relocates local references in Markdown
`video[src]`, `video[poster]`, `audio[src]`, media `source[src]` and `track[src]`.
Every local target must be in the declared file tree. Direct URLs, multiple
format sources, poster images, caption tracks and fallback `a[href]` links use
the same simultaneous moves as ordinary Markdown links. Only URL spans change;
all other markup and every opaque media/track byte are preserved.

```text
moon run cmd/main --target wasm -- plan examples/media/tree examples/media/moves.json media-plan.json --static-html
moon run cmd/main --target wasm -- review media-plan.json
moon run cmd/main --target wasm -- replay examples/media/tree media-plan.json relocated-media
moon run cmd/main --target wasm -- check relocated-media media-plan.json --result
moon run cmd/main --target wasm -- restore relocated-media media-plan.json restored-media
```

Choose unused output paths outside the source directory. The authored README
moves into `manual` and the real MDN CC0 WebM/MP3 plus poster/captions move from
`assets` to `media`. All six references become `../media/...`; the plan embeds
the complete source snapshot. [Pinned provenance and license](../examples/media/SOURCE.md).
Replace `--target wasm` with `--target native` for native execution.

Quoted attributes retain case, order, entities, quote style, line endings and
source-selection metadata. Additional supported metadata:

| Element | Attributes |
|---|---|
| `video`, `audio` | boolean `controls`, `autoplay`, `loop`, `muted`; `preload` (`""`, `none`, `metadata`, `auto`); `crossorigin` (`""`, `anonymous`, `use-credentials`) |
| `video` | boolean `playsinline`; existing width/height and other shared static metadata |
| `source` | preserved `type` and `media`, alongside the existing image profile |
| `track` | boolean `default`; `kind` (`subtitles`, `captions`, `descriptions`, `chapters`, `metadata`); preserved `srclang`, `label` |

Bare boolean attributes and quoted empty/attribute-name values are supported
(case insensitive). `controls="false"` refuses with an actionable diagnostic:
HTML boolean presence enables the flag. Enumerated values are checked without
trimming or entity decoding; unknown forms refuse instead of relying on browser
recovery. Original details/open behavior is retained. Empty media URL attributes,
duplicate attributes, templates, scripts, styles and event handlers refuse.
A `source` cannot combine `src` with image `srcset` / `sizes` in the same tag;
the input must explicitly separate those resource-selection forms.

External/scheme and fragment-only URLs retain the existing URL policy. No
request, codec conversion, media decoding, browser selection/playback, MIME
verification, BCP47 validation or DOM nesting validation is performed. This is
a relocation workflow, not a media player or HTML sanitizer. Standalone HTML,
SVG and WebVTT contents remain opaque; their internal application-specific
references are outside the API. CommonMark remains the default and refuses raw
HTML during nonempty migrations. Existing plan signatures/wire forms are unchanged.

The independent implementation follows the
[WHATWG media element requirements](https://html.spec.whatwg.org/multipage/media.html)
and [source element](https://html.spec.whatwg.org/multipage/embedded-content.html#the-source-element),
checked 2026-10-16, with the deliberately smaller grammar documented above.
No standard prose, browser code or upstream tests were copied.

Run `moon run scripts/media-e2e.mbtx -- wasm` (or `native`) for the offline
real-data workflow: plan/review/replay/result-check/exact restore, byte equality
for all four resources and refusal to overwrite a later video edit. Saved plans
and temporary outputs remain available for inspection at the printed location.
