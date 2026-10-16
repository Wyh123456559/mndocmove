# Wire version 1

Only JSON arrays and scalar values are accepted. Objects are refused before
JSON decoding, so duplicate object fields cannot silently overwrite data.
Every tuple has exact arity; extra values and unknown versions/profiles fail.
Maximum JSON text length is 200,000,000 UTF-16 units; maximum nesting is 16.
The file/tree limits also apply after decoding. A plan embeds the original
source bytes, so it can be much larger than a preview.

Move input: `[["docs","manual"],["img","assets"]]`.

Full plan:

```json
["mndocmove",1,"commonmark",[["r.md","4869"]],[["r.md","s.md"]]]
```

Positions: magic string, version, profile, files, moves. Profiles are
`commonmark` and `static-html`; unknown values are refused. Existing CommonMark
version-1 plans retain their byte-identical canonical encoding.
Each file is `[relative_path, uppercase_hex_bytes]`; lowercase hex is accepted
on input and canonicalized. Files and moves are sorted by original path.
Reloading rebuilds the tree and runs the planner; edit offsets are never trusted
as an executable input. Replay then compares the complete current snapshot.

Preview: `["mndocmove-preview",1,moves,edits]`.
Each edit is `[path,start,end,before,after,old_target,new_target]`.
Offsets count UTF-16 code units; `end` is exclusive. These offsets refer to the
original source, including CRLF/BOM. Preview is informational, not a replay plan.

Ordered chains use the separate `mndocmove-chain` version-1 envelope documented
in [ordered migrations](chains.md). CLI inspection/execution accepts both forms;
the single-plan loader remains strict. Snapshot-check JSON is report-only and
is not accepted as either plan form.
