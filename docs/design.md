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
text. Immutable bytes and private array representation prevent callers from
mutating a snapshot through a getter. Wire decoding recomputes all derived
data; no edit is applied from a serialized untrusted offset.

Implemented first capability: CommonMark relocation, deterministic full-plan
exchange, stale-snapshot guard, new-directory CLI export and public fixture.

Next capability: explicit static-HTML profile for common README `href`/`src`
attributes, with source/quote preservation and strict refusals for unsupported
HTML URL grammars. Keep the original profile as the conservative default.

Later work, not implemented: carefully specified site-route profiles, editor
integration and filesystem transactions. Each requires its own end-to-end
workflow, diagnostic rules and regression suite. No automatic Git operation
or network availability check is part of the library.
