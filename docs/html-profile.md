# Static HTML profile

Opt in with `plan_moves(tree, moves, profile=StaticHtml)` or CLI `--static-html`
at the end of `plan` arguments. The plan wire profile is `static-html`;
deserialization/replay retains it. Existing calls and CommonMark wire plans
keep the original behavior. Even empty static-HTML plans preserve bytes without
parsing, exactly as CommonMark no-op plans do.

Only regions classified as HTML by the CommonMark parser are scanned. Inline
HTML and HTML blocks are supported; Markdown code spans/fences never enter
the scanner. Within a raw HTML block, Markdown-looking text is literal HTML
text and is not treated as Markdown links. This is not an HTML DOM parser,
renderer, sanitizer, MDX processor or general `.html` file rewriter.

Supported tags (ASCII case insensitive): `a`, `img`, `p`, `div`, `span`,
`details`, `summary`, `br`, `hr`, `figure`, `figcaption`, `table`, `thead`,
`tbody`, `tr`, `td`, `th`, `ul`, `ol`, `li`, `h1`–`h6`, `strong`, `em`,
`b`, `i`, `code`, `pre`, `blockquote`, `sup`, `sub`, `kbd`, `samp`, `picture`, `source`.

URL-bearing attributes are `a[href]`, `img[src]` and individual candidates in
`img[srcset]` / `source[srcset]`. Width sets can retain supported static `sizes`.
See the [strict srcset and sizes subset](srcset.md).
Preserved
attributes are `id`, `class`, `title`, `alt`, `width`, `height`, `align`,
`role`, `target`, `rel`, `loading`, `decoding`, `border`, `colspan`, `rowspan`,
`open`, and `aria-*`. Every value must be quoted; only `details open` may
omit a value. Duplicate attributes are refused ignoring ASCII case.
`source[media]` and `source[type]` are preserved selection metadata.
Other attributes fail rather than hiding a possible URL grammar, including
`data-src`, `style`, event handlers, SVG `xlink:href` and audio/video sources.

URL entities must be recognized and semicolon terminated; use `&amp;` for
query ampersands. Unknown/legacy unterminated references, replacement/invalid
entities, controls, leading/trailing URL spaces and template markers fail.
HTML entities are decoded **without Markdown backslash unescaping**; rewritten
values escape both quote types and ampersands while retaining the original
surrounding quote. URL path percent encoding and root/missing-target rules are
shared with CommonMark. External URLs still receive the strict syntax check.

Supported comments are preserved literally and contain no live references.
Unsupported tags, comments or attributes return `UnsupportedHtml` with the
source path, UTF-16 position and a reason. Missing targets and invalid URLs
keep the shared diagnostics. Some browser-recoverable HTML is intentionally
refused. The scanner does not attempt to repair or validate HTML nesting.
