# Verified export and recovery

`replay ROOT PLAN_JSON NEW_OUTPUT_DIRECTORY` first validates the complete source
snapshot. The source is read-only throughout. The output parent must already
exist and must be outside the source inventory. The final path must be unused.

The exporter reserves a random `.mndocmove-stage-<32 hex digits>` directory
beside the final destination with exclusive creation. Its `tree/` child holds
only user files; `.mndocmove-incomplete` is metadata outside that child. A user
file with that name is therefore preserved normally. Unix staging permissions
are requested as `0700`; Windows permissions follow the host's directory rules.

After writing, the exporter reads `tree/` through the same strict inventory
reader as the source. It compares every path and byte with the planned output.
Extra files, missing files, changed bytes, empty directories and unsupported
filesystem objects refuse publication. It then renames `tree/` to the final
path with `replace=false`. A destination created after the initial existence
check is also protected; an existing empty directory is never replaced.

The pinned async 0.22.4 dependency implements no-replace rename with Linux
`renameat2(RENAME_NOREPLACE)`, macOS `renameatx_np(RENAME_EXCL)` and Windows
no-replace rename APIs. Unsupported host/filesystem behavior returns an error;
there is no copy-and-delete fallback. These implementations were inspected in
the dependency's `src/internal/event_loop/fs.c`; see the
[upstream filesystem implementation](https://github.com/moonbitlang/async/blob/main/src/internal/event_loop/fs.c).

On a write, readback or publication failure, exit 1 includes `ExportFailed`, the
retained staging path and the underlying cause. Inspect that path, fix the
cause, and replay a valid plan to an unused destination. Failed stages are
never automatically deleted. Replaying creates a fresh stage; it does not
trust or resume partially written files. An interruption can leave a stage
before its marker or child directory was created.

After publication, the exporter removes its marker and empty staging container.
Cleanup failure prints `CleanupWarning` and keeps exit 0 because the verified
final tree was already published. The warning identifies leftover metadata.

No crash durability or concurrent-edit guarantee is made. There is no `fsync`
protocol, journal, overwrite mode or in-place mutation. Do not edit the source,
stage or destination concurrently. Export preserves paths and bytes, not
permissions, timestamps, ACLs or hard-link identity.

Run `moon run scripts/e2e.mbtx -- wasm` or `-- native` for a reproducible real
write failure: a planned component longer than the host's filename limit fails
inside staging. The script checks that the final path remains unpublished,
the diagnostic stage is retained, source bytes are unchanged and a corrected
plan succeeds at the same final path. White-box tests separately alter staged
bytes/inventory and place an empty directory or file at the final path before
publication, verifying refusal and recovery.
