# Design and coherent roadmap

1. Guide reorganization: move `docs/install.md` into `manual/start/install.md`,
   update README/SUMMARY incoming links and the guide's relative images and
   sibling links, review the full plan, export and compare.
2. Shared images: move `docs/images` into `assets/manual`; rewrite inline and
   reference-style image destinations while preserving image bytes, alt text,
   titles and unchanged Markdown source.
3. Team review: save a directory migration plan, then add/change a source file.
   Replay rejects the stale inventory; regenerate and review before exporting.

All three use the same public tree / move / plan API, independently of the CLI.
The first release includes the complete workflow, not just parsing.

For every supported local reference the invariant is
`resolve(new_source,new_link) = move(resolve(old_source,old_link))`.
Moves act simultaneously on original prefixes. Overlapping source prefixes
and output collisions fail before Markdown rewriting. Directory links whose
children all disappear fail rather than yielding dangling references.

The cmark dependency supplies CommonMark syntax and UTF-16 source positions.
Each destination span is checked against the parser's cooked value before
editing. Edits are ordered, checked for overlap and applied to the original
text. The complete result is then reparsed: the number/order and decoded values
of every destination must match the intended URL list, or planning fails with
`RewriteInvariant`. Immutable bytes and private array representation prevent callers from
mutating a snapshot through a getter. Wire decoding recomputes all derived
data; no edit is applied from a serialized untrusted offset.

Implemented first capability: CommonMark relocation, deterministic full-plan
exchange, stale-snapshot guard, new-directory CLI export and public fixture.

Implemented second capability: explicit static-HTML profile for common README
`a[href]`/`img[src]` attributes, with source/quote preservation, full saved-plan
replay and refusals for unsupported HTML URL grammars. The original profile
remains the conservative default. File moves cannot silently change whether
the content is interpreted as Markdown.

Implemented third capability: contextual migration review derived from verified
source edits, including all opaque-asset moves and an offline saved-plan CLI.

Implemented fourth capability: reserved sibling staging, exact inventory/byte
readback and no-replace publication, with retained failure diagnostics and a
real filesystem-failure/retry demonstration.

Implemented fifth capability: exact restoration from a saved plan, guarded
against changes to the migrated tree and exported through verified staging.

Implemented sixth capability: root-directory navigation links through `.`/`..`,
with directory-prefix moves, preserved suffixes and complete review/replay/restore.

Implemented seventh capability: static responsive image candidates with preserved
decimal density descriptors, source-selection metadata, fallback images and a
licensed Svelte README/PNG migration/restore workflow.

Implemented eighth capability: complete source/result snapshot drift reports,
with typed changes, deterministic JSON and a read-only CLI/CI verification flow.
Later work, not implemented: carefully specified site-route profiles, editor
integration and crash-durable filesystem transactions. Each requires its own end-to-end
workflow, diagnostic rules and regression suite. No automatic Git operation
or network availability check is part of the library.
