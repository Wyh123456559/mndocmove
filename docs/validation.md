# Executed validation — 2026-10-16

Stable Windows ZIP was fetched from the official `binaries/latest` endpoint,
Last-Modified 2026-10-12, SHA-256
`6E3EF6CB96AA5086D122183972687F79FC912F80652000907D96EE6AD967E3BF`.
It matched the already extracted stable toolchain used for these commands:
moon 0.1.20261012 (`748b63c`), moonc v0.10.15 (`943464bfa`), matching moonrun.
Configuration uses current `moon.mod` / `moon.pkg` syntax.

Executed locally, rather than inferred from compilation:

| Environment | Check | Tests / runtime |
|---|---|---|
| Windows x86-64, Wasm host | strict check passed | 51/51 tests; real README + bat HTML migration/restoration CLI E2E passed |
| Windows x86-64, Wasm-GC | strict check passed | 44/44 tests |
| Windows x86-64, JS / Node | strict check passed | 44/44 tests |
| Ubuntu 22.04 x86-64 through WSL2, native | strict check passed | 51/51 tests; native CLI real README + bat HTML migration/restoration E2E passed |

`moon fmt --check`, `moon info` executed; generated interfaces are checked in.
`--deny-warn` is applied to MoonBit checks/tests and the CLI build in E2E.
No MoonBit project warnings remain. The upstream async native C build on Linux
emits warnings for `posix_spawn_file_actions_addchdir_np` declaration and an
ignored `write` return value. MoonBit's deny-warn does not make those C compiler
warnings fatal. They were not suppressed or patched in downloaded dependencies.
Standalone `.mbtx` compilation can additionally emit the toolchain/dependency
duplicate `async/internal/c_buffer` import warning; E2E still executed and passed.

Windows native was attempted but cannot run here: MSVC C++ Build Tools / SDK
are absent. MinGW fallback is rejected by async's platform guards; it is not
claimed as supported. macOS is not available locally.
CI is configured for Windows (with MSVC), macOS and Linux, all four library
targets, both CLI targets, formatting and interface drift. A configured workflow
is not a CI pass. The first actual remote run, for `a90c538`, passed on all
three OS runners, including native runtime and both CLI E2E targets:
[GitHub Actions run 38775375097](https://github.com/Wyh123456559/mndocmove/actions/runs/38775375097).
That run tested 27 cases per target before contextual review was added. The
subsequent `ed144df` run passed Linux/macOS but failed a Windows native E2E
assertion: MSVC text-mode stdout adds CRLF to captured review output. The
initial fix in `ea800e9` used a first-occurrence replacement and still failed
later report lines on Windows native (Linux/macOS passed). The script now uses
`replace_all` for that stdout transport layer; file assertions remain byte-exact.
The same audit corrected all-separator path normalization and added a real
multi-level/backslash path regression. Current changes must pass their own
head-specific CI run; earlier failures are not reported as successful runs.

Tests cover incoming/outgoing/reference rewrites, CRLF/BOM/emoji offsets,
URL encoding round trips, opaque bytes, deterministic order, swaps, immutability,
missing targets, path conflicts, root escape, malformed/unknown wire data,
exact file/Markdown size limits, empty destinations, directory links,
stale snapshots and successful reuse after a refusal. The E2E script also
checks exit codes, no source writes, refusal of output inside the source root,
existing-output protection and unsupported empty-directory inventory.

The second capability adds inline/block HTML quote/entity round trips, mixed
HTML/Markdown moves, strict unsupported-attribute/tag failures, comments/code
preservation, old CommonMark wire compatibility and explicit profile replay.
Rewriting reparses the result and verifies every decoded destination. A
regression test covers entity-encoded line breaks in a Markdown query suffix;
they must remain encoded rather than becoming malformed source. Moves that
would reinterpret opaque bytes as Markdown (or vice versa) are refused.

Contextual review adds an independent hunk consumer that verifies old/new line
counts and reconstructs exact replay output across dense/sparse changes,
repeated lines, multiple context sizes and missing-final-newline states. Other
cases cover CRLF/emoji, coalescing, rename/asset manifests, invalid contexts,
terminal controls, deterministic wire reload and plan/source immutability.
Both real CLI workflows also inspect saved plans through `review`.

Verified export adds six real filesystem tests: unique staging reservation,
changed bytes, missing/extra files, empty-directory refusal and recovery,
no-replace publication over an existing empty directory/file, and exact final
inventory with reserved-looking user filenames. The E2E workflow forces an
actual overlong-component write failure and checks unpublished final output,
retained diagnostic files, successful retry and unchanged source/asset bytes.

Restoration adds seven black-box tests and a tested README example. They verify
exact original bytes/paths across both profiles, noncanonical URL spellings,
BOM/CRLF/emoji/no-final-newline, binary resources, simultaneous directory swaps,
wire reload, empty plans/trees, sorted first-difference diagnostics, additions,
deletions, renames, changed bytes, immutable arrays and reuse after refusal.
Both real CLI fixtures now perform migration-to-restoration round trips; a
later Markdown edit is refused and preserved, followed by a successful retry.
Nested output paths inside the source are refused in slash and backslash
forms; a backslash-form outside path completes a verified export.

Reproduce with the commands in README. Temporary E2E data is retained in the
printed system temporary directory; it is not checked into this repository.
