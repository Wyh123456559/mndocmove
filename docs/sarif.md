# SARIF migration preflight reports

`MoveAudit::to_sarif_string(root_prefix="docs")` converts an existing batch
preflight into deterministic SARIF **2.1.0**, for SARIF viewers and optional CI
integration. It uses the exact immutable tree retained by that audit, so file
positions cannot accidentally be computed from a different later snapshot.
The library's normal array-based audit JSON and plan formats remain unchanged.

```text
moon run cmd/main --target wasm -- audit-sarif DOCS moves.json docs blocked.sarif
moon run cmd/main --target wasm -- audit-sarif DOCS moves.json docs ready.sarif --profile static-html-root
```

`ROOT_PREFIX` is the documentation tree's portable path relative to the
repository root. Use `.` for the repository root itself. The library also
accepts the default empty string. Absolute/backslash/dot-dot/invalid prefixes
refuse. Artifact URIs percent-encode spaces, Unicode, percent and fragment
characters while retaining `/` path separators. `uriBaseId` is `SRCROOT`; its
description identifies the repository checkout supplied by the consumer,
without embedding machine-specific absolute paths. Configure the viewer's
source root; GitHub treats relative artifacts as repository paths, as described
in its [SARIF support](https://docs.github.com/en/code-security/reference/code-scanning/sarif-files/sarif-support).

Exit 0 means a ready report was written. Exit 1 means blocked preflight **with
its report written**, or a structural/invalid-input/I/O diagnostic. Structural
failures occur before a completed audit and do not create a report. Exit 2 is
usage error. Every report path must be unused and outside the source tree.
Existing reports and input files are retained on refusal. The command creates
no migration plan and never applies edits. A SARIF file is refused by plan
loaders. Report writes use the existing exclusive-file rules, without claiming
crash-durable publication.

The emitted subset includes:

- One error result for every existing audit diagnostic, and one sorted rule
  entry for each distinct code. The audit still reports only the first content
  refusal per failing document, at most 4096 results.
- One-based line/column point regions with `columnKind=utf16CodeUnits`; a tab
  is one unit, an astral character two, CRLF one newline. A leading BOM is
  excluded from SARIF text coordinates per the OASIS specification. Unknown
  positions/invalid UTF-8/newline positions keep file locations without a
  fabricated region. Out-of-range retained offsets refuse.
- Original source path and UTF-16 offset in result properties, including `-1`.
  Messages use fixed `{0}` plus the exact diagnostic as an argument, so braces
  in filenames are not interpreted as additional message placeholders.
- Ready/profile/source-count/checked-Markdown metadata. Empty/no-op audits
  preserve their existing readiness semantics and zero checked-file count.
- Stable recursive object-key ordering and inventory-ordered results. No
  source contents, fixes, command lines, timestamps or plan offsets are emitted.

No report upload, code-scanning enablement, alert fingerprinting, hosted viewer
rendering or universal consumer compatibility is claimed. Consumers impose
their own ingestion limits. All diagnostics are retained without truncation;
review a report locally before optionally integrating it with your CI.

The [OASIS 2.1.0 specification](https://docs.oasis-open.org/sarif/sarif/v2.1.0/sarif-v2.1.0.html)
and its [official schema](https://docs.oasis-open.org/sarif/sarif/v2.1.0/errata01/os/schemas/sarif-schema-2.1.0.json)
are semantic/validation references, not copied implementations or tests.
Run `moon run scripts/audit-e2e.mbtx -- wasm` or `native` for the offline real
README workflow. It writes blocked and ready SARIF, checks positions/URIs,
exclusive/outside-source output and report/plan separation, then performs the
existing fixed-source plan/review/export/check/exact restore workflow.
See [validation evidence](validation.md) and [source/licenses](../THIRD_PARTY.md).
