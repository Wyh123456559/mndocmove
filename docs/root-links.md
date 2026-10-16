# Inventory-root navigation

Documentation pages commonly link back to their declared documentation root.
For `guide/NAV.md`, `[Root](../?view=tree#docs)` names that root directory, not
another Markdown page. Moving `guide` to `manual/deep` changes that destination
to `../../?view=tree#docs`; the query and fragment remain unchanged.

This works with CommonMark inline/reference links and the static HTML profile's
`a[href]` attributes. Source whitespace, quotes, entities, BOM, line endings and
unchanged URL spellings are retained. Plans can be saved, reviewed, replayed and
restored with the existing API and CLI; the wire format is unchanged.

The root is a fixed link target. It cannot be renamed by a move pair, and neither
the inventory nor the move planner accepts an empty or dot file/move path.
`Entry::new` and `Move::new` defer validation to those boundaries.
In derived `Edit.old_target` and
`Edit.new_target`, the empty string denotes the inventory root. Other targets
remain validated relative paths. This sentinel never names an output file.

`.` / `..` are normalized as URL path segments, including valid percent-encoded
dot segments. A link that already resolves to the intended root is not rewritten.
A changed destination uses `.` at the root, or one `..` per containing directory;
the original trailing slash is preserved. For example, moving `guide/r.md` with
`../` to `r.md` produces `./`. An additional `..` that escapes the declared root
still raises `OutsideRoot`. Root-relative `/...` URLs remain unsupported.

Directory navigation does not infer a landing page, generate an index or change
heading anchors. A non-root directory that loses all its children is still
refused unless its prefix is explicitly moved; root support does not hide a
dangling subdirectory link.

Run `moon run scripts/e2e.mbtx -- wasm` or `-- native`. The workflow constructs an
authored navigation page around the unmodified, licensed Microsoft README and
example fixture, moves their complete directory, inspects the saved plan and
exports/restores it. Assertions check root navigation, query/fragment preservation,
CRLF, unchanged source files and exact upstream fixture bytes.
