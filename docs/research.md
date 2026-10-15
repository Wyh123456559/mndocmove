# Ecosystem decision record

Research performed 2026-10-13, with fixture/source verification 2026-10-16.
The intended audience is ordinary repository documentation maintainers and
MoonBit tool authors, rather than a specialized protocol community.

The original candidate comparison selected document relocation (87.5/100)
over HTTP cassette replay (74/100) and configuration contracts (75/100).
Scores used value 25%, differentiation 25%, depth 15%, feasibility 10%,
portability 10%, demonstrability 10%, maintenance cost 5%. These are engineering
judgments, not measurements of adoption. Overlap was a hard rejection gate.

| Candidate | Value / differentiation / depth / feasibility / portability / demo / maintenance (1–5) | Decision |
|---|---|---|
| Source document relocation | 4.5 / 4.5 / 4.5 / 3.5 / 4.5 / 5 / 3 | Selected: source spans, simultaneous incoming/outgoing relocation and replay form an independent workflow |
| HTTP cassette replay | 5 / 1 / 4.5 / 4 / 4.5 / 5 / 3.5 | Reject: MoonVCR already covers recording, matching, ordered replay and consumption assertions |
| Configuration contracts | 5 / 1 / 4 / 4.5 / 5 / 5 / 4 | Reject: MoonConfigKit already covers schema relations, merged values, provenance and secret rendering |

Nearby MoonBit projects, checked public interfaces:

- [MoonBook](https://github.com/spectacleCase/moonbook), MPL-2.0, 0.3.1:
  `check_links`, `extract_sections`, `referenced_assets`, `build_site` and rendering.
  [Interface](https://raw.githubusercontent.com/spectacleCase/moonbook/main/pkg.generated.mbti).
  Latest observed maintenance: [2026-08-24](https://github.com/spectacleCase/moonbook/commit/1a4c5fb2b12ded947c35aa02dfc50aecea5f893f).
  Its rendered `.md` → `.html` rewriting belongs to site generation; the
  reviewed interface has no source move-map / preserved-source plan boundary.
- [Yuegui](https://github.com/Anxiu0101/yuegui), Apache-2.0, 0.1.3:
  `check_broken_links(Site)`, page links/headings, routes and site rendering.
  [Core interface](https://raw.githubusercontent.com/Anxiu0101/yuegui/master/core/pkg.generated.mbti).
  Latest observed maintenance: [2026-06-11](https://github.com/Anxiu0101/yuegui/commit/5e0128ee03bd7d0ab49268094a1773a875986d23).
  The inspected API does not plan and replay source-file moves.
- Rejected HTTP boundary: [MoonVCR](https://github.com/chenqi-arch/moonbit-project),
  Apache-2.0, 0.3.0, observed registry publication 2026-09-26; `Session`,
  `Cassette`, request matching and strict offline replay.
- Rejected configuration boundary: [MoonConfigKit](https://github.com/crh12354/23423),
  Apache-2.0, 0.1.1, [2026-08-23](https://github.com/crh12354/23423/commit/9e580a75a1fab013b744612c7505743909d2674e);
  `ConfigSchema::validate`, `merge_layers`, `ResolvedValue`, traces and relations.

Mainstream demand: VS Code documents
[automatic link updates on file/directory moves](https://code.visualstudio.com/docs/languages/markdown#_automatic-link-updates-on-file-move-or-rename).
Microsoft's [Markdown language service](https://github.com/microsoft/vscode-markdown-languageservice)
exposes file-rename workspace edits, handles incoming/outgoing references and
powers VS Code (MIT, observed 438 stars / 25 forks on research date).
[Nock](https://github.com/nock/nock) (MIT, approximately 13.1k stars then) and
[envalid](https://github.com/af/envalid) (MIT, approximately 1.6k stars then)
confirm the other problems are common, but their MoonBit boundaries were taken.
Counts are historical observations, not current adoption guarantees.

Search covered [Mooncakes](https://mooncakes.io/), GitHub,
[awesome-moonbit](https://github.com/moonbitlang/awesome-moonbit),
[moonbit-community](https://github.com/orgs/moonbit-community/repositories) and
[official documentation](https://docs.moonbitlang.com/en/stable/index.html).
Keywords: `markdown rename`, `markdown move`, `link rewrite`, `relocate`,
`markdown refactor`, `update links`, `broken link`, `doc links`, `搬迁`, `vcr`,
`cassette`, `record replay`, `mock http`, `dotenv`, `config schema`, `envalid`.
Some queries timed out or reached a 50-result limit. Private, unpublished and
unindexed projects remain unknown; absence from search is not proof of absence.

Classification: a complementary MoonBit workflow implementing an established
need. The engineering depth lies in source preservation, URL/path semantics,
simultaneous mappings and snapshot replay, rather than a renamed checker or
a thin parser wrapper. No originality, uniqueness or performance claim is made.
