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
| Windows x86-64, Wasm host | strict check passed | 112/112 tests; Git-rename CLI E2E passed |
| Windows x86-64, Wasm-GC | strict check passed | 105/105 tests |
| Windows x86-64, JS / Node | strict check passed | 105/105 tests |
| Ubuntu 22.04 x86-64 through WSL2, native | strict check passed | 112/112 tests; real Git-rename CLI E2E passed |

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
The restored-snapshot head `43b5f19` subsequently passed all three systems,
including Windows native E2E:
[GitHub Actions run 38832637668](https://github.com/Wyh123456559/mndocmove/actions/runs/38832637668).
The inventory-root head `2ad0b08` also passed all three systems:
[GitHub Actions run 38834525464](https://github.com/Wyh123456559/mndocmove/actions/runs/38834525464).
The responsive-image head `bc0fba7` passed all three systems:
[GitHub Actions run 38835714944](https://github.com/Wyh123456559/mndocmove/actions/runs/38835714944).
The complete snapshot-report head `d29f332` passed all three systems and both
legacy/new CLI workflows:
[GitHub Actions run 38848072096](https://github.com/Wyh123456559/mndocmove/actions/runs/38848072096).
The ordered-chain head `2db6b8d` passed all three systems and all three E2E
scripts on both CLI targets:
[GitHub Actions run 38849187092](https://github.com/Wyh123456559/mndocmove/actions/runs/38849187092).
The width-responsive head `c6a1e11` passed all three systems, all four library
targets and the complete Wasm/native E2E matrix:
[GitHub Actions run 38851796463](https://github.com/Wyh123456559/mndocmove/actions/runs/38851796463).
The media head `f9699a6` passed all three systems, four library targets and all
four E2E scripts on both CLI targets:
[GitHub Actions run 38877811452](https://github.com/Wyh123456559/mndocmove/actions/runs/38877811452).
The parallel-merge head `fdb89cf` passed all three systems, four library targets
and five E2E scripts on both CLI targets:
[GitHub Actions run 38880337002](https://github.com/Wyh123456559/mndocmove/actions/runs/38880337002).

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

Root navigation adds five black-box cases plus a tested README example. The
cases exercise inward/outward document moves, prefix swaps, root query/fragment
suffixes, reference definitions/static HTML, original URL spelling, save/load
and restore, while retaining escape and invalid-root-move refusals. The real
fixture E2E additionally moves an authored root navigation page together with
the unmodified Microsoft README and example.

Responsive image relocation adds nine black-box cases plus a tested README
example. Tests cover source/img/fallback spans, implicit/decimal densities,
exact descriptors and comma/whitespace layout, entities and percent-encoded
filename spaces/commas, astral Unicode, source offsets, mixed Markdown/HTML,
external URLs, wire/review/restore and deterministic output. Invalid grammars,
duplicate densities, missing/escaping candidates and 256/257 candidate limits
refuse the complete plan and leave later valid planning usable. The real Svelte
README excerpt and both binary PNGs undergo saved-plan review/replay/restore;
every original, exported and restored image byte is compared offline.

Snapshot checks add six black-box tests and a tested README example. They cover
source/result selection, complete sorted drift, equal-length byte changes,
deterministic JSON/reloaded plans, copied report arrays, empty/zero-byte data,
and all 8192 differences between two maximal file inventories. The independent
`scripts/check-e2e.mbtx` uses the real Microsoft fixture and checks both sides,
all drift categories, read-only input, exit codes and report/plan separation.
CI executes this script and the full migration/restoration script on both CLI
targets; local native snapshot-check execution is recorded above.

Ordered chains add eight black-box tests, one wire-budget white-box test and a
tested README example. Coverage includes equivalence with sequential plans,
intermediate-vs-endpoint guards, cancellation with retained stage evidence,
profile inheritance/overrides, deterministic single-snapshot wire exchange,
malformed/extra/unknown data, array isolation and recovery after an append
refusal. Limits accept eight stages and exactly 128 MiB logical snapshot bytes,
and reject the next stage. Wire preflight is checked against actual encoded
UTF-16 lengths, including Unicode paths, profiles and empty arrays, at the exact
accepted/refused boundary without allocating a 200-million-unit test artifact.
The offline chain E2E performs three ordered stages on the real Microsoft
fixture, endpoint checks and exact restore, while refusing stale source and
existing/inside-source output plan paths. CI runs the full migration, check,
chain and media E2E scripts on Wasm/native alongside the four library targets
on every OS.

Width-based responsive relocation adds five black-box cases and a tested README
example. Coverage includes exact width equality with leading zeros, mixed/implicit
density refusal, both attribute orders, external/query URLs, BOM/CRLF/emoji,
strict CSS lengths/conditions, Unicode whitespace and unknown CSS refusal,
32/33 entry and 4096/4097 UTF-16 sizes limits, source spans, deterministic wire,
review/check/restore and reuse after refusal. The existing Svelte E2E now also
migrates the authored width page with the real unmodified 2500px PNGs and checks
exact source/metadata preservation and restored bytes. Public signatures and
the existing plan wire representation are unchanged (`moon info` verified).

Embedded media adds six black-box cases and a tested README example. Tests
cover direct/alternate video and audio sources, posters, tracks and fallback
links, shared URL/entity/percent rules, source spans and BOM/CRLF/emoji,
supported boolean/enumerated metadata, duplicate/dynamic/ambiguous/empty inputs,
missing/escaping resources, code/comment preservation, deterministic saved plans,
chain composition and recovery after a later binary edit. The new independent
media E2E uses pinned CC0 WebM/MP3 plus authored SVG/WebVTT and checks all six
rewritten references, full result inventory, exact exported/restored resource
bytes, profile opt-in and refusal to overwrite later video edits. No codec or
browser playback claim follows from these path/byte checks.

Parallel-plan merge adds six black-box cases and a tested README example:
interacting links and same-line spans, commutativity/idempotence, exact source
comparison including equal-size opaque changes, profile/intention/prefix/path
conflicts, safe shared directories, media syntax and byte-exact wire/restore.
All 4096 identical intentions coalesce at the limit; a 4097-intention union
refuses without mutating either input. The real Microsoft fixture E2E checks
independently saved plans, equivalent reversed merge, contextual review,
export/result-check/exact restore, exclusive output and stale-source refusal.
CI adds that E2E on Wasm/native, making five scripts per OS/CLI target.

Git import adds seven black-box cases and a tested README example. Coverage
includes reordered exact renames, scoped endpoints, Unicode/spaces/literal percent
paths, strict UTF-8, every unsupported status category, NUL truncation/extra data,
quoted/non-NUL formats, duplicate/case-alias records, directory non-inference,
4096/4097 records and UTF-16 path units, byte/field budgets and reuse after refusal.
`scripts/git-e2e.mbtx` invokes real Git tree objects/moves/diffs, without commits
or configured author changes, and verifies saved-plan migration/restoration on
the licensed README fixture. A real changed-content Git diff is refused as a
whole. Both Wasm and native CLI workflows executed successfully. CI runs six
E2E scripts per OS/CLI target; Git is an external test/producer executable only.

Reproduce with the commands in README. Temporary E2E data is retained in the
printed system temporary directory; it is not checked into this repository.
