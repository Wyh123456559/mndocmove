# Contextual migration review

`MovePlan::review(context=3)` and `review PLAN_JSON [CONTEXT_LINES]` return a
deterministic human report containing the full per-file move manifest and
contextual Markdown changes. Opaque asset contents are never decoded as text.
Context must be a canonical integer 0–20 on the CLI; out-of-range library
arguments fail with `InvalidContext`. Loading a plan still validates its version,
profile, original inventory, and recomputed edits.

File headers contain JSON-quoted paths. Hunk headers use
`@@ -old_start,old_count +new_start,new_count @@`; body prefixes are a space
(unchanged), `-` (old) or `+` (new). CRLF is retained in body lines. An unterminated
line is followed by `\ No newline at end of file`. The report has an informational
preamble and asset manifest, so it must not be fed to `git apply` as a complete
migration. It cannot apply asset moves or replace replay's full snapshot check.

The algorithm derives affected line intervals from already verified UTF-16
edits, maps offsets using binary search, coalesces line overlaps and expands /
merges context windows over line operations. It does not search for equal lines
with LCS, avoiding ambiguity on repeated paragraphs and a quadratic diff matrix.
Every supposedly unchanged line is checked against both snapshots.

Tests independently consume the public hunk format, check source evidence and
line counts, and reconstruct replay output across sparse/dense changes, repeated
lines, different context sizes and final-newline states. Other tests cover
CRLF/emoji, same-line edits, source/plan immutability, asset-only/empty plans,
quoted Unicode/space paths, wire reload, CLI diagnostics and real public data.

This is a text report of source data. Control characters that could change
terminal behavior and bare carriage returns fail with `UnreviewableText` rather
than being dropped. The error suggests the escaped JSON preview; no plan or
source bytes are mutated. Output can be large when many source lines change.

Format references: [Git diff format](https://git-scm.com/docs/diff-format) and
[GNU unified format](https://www.gnu.org/software/diffutils/manual/html_node/Unified-Format.html).
No diff implementation or upstream test cases were copied.
