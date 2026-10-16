# Third-party materials

No upstream application implementation or test cases were ported. The project
uses public package APIs. Tests were written for this project's contracts;
format semantics follow CommonMark and URI percent encoding.

| Material | Version/source | License | Use |
|---|---|---|---|
| MoonBit core/runtime | stable 2026-10-12 | Apache-2.0 | Collections, UTF-8, JSON, runtime; generated interfaces/toolchain scaffold |
| [cmark.mbt](https://github.com/moonbit-community/cmark.mbt) | Mooncakes 0.4.12 | Apache-2.0 | Markdown parser and source positions; char entity/unescape API |
| [async](https://github.com/moonbitlang/async) | Mooncakes 0.22.4 | Apache-2.0 | CLI filesystem and test automation process host |
| cmark transitive data packages | charclass 0.1.4, casefold 0.1.7, ucd 0.5.0 | Apache-2.0 per package metadata; Unicode data provenance in upstream repositories | Parser character data |
| Microsoft Markdown language service | pinned fixture [source](examples/vscode/SOURCE.md) | MIT, retained [license](examples/vscode/LICENSE) | Unmodified README and linked example as real input data |
| sharkdp/bat | pinned fixture [source](examples/bat/SOURCE.md) | MIT option, retained [license](examples/bat/LICENSE-MIT) | Verbatim README header excerpt and unmodified SVG asset |
| Svelte | pinned fixture [source](examples/svelte/SOURCE.md) | MIT, retained [license](examples/svelte/LICENSE.md) | Verbatim README header and unmodified dark/light PNGs |
| WHATWG HTML Standard | [srcset](https://html.spec.whatwg.org/multipage/images.html#srcset-attributes) and [sizes requirements](https://html.spec.whatwg.org/multipage/images.html#sizes-attributes), checked 2026-10-16 | [CC BY 4.0; source-code portions BSD-3-Clause](https://github.com/whatwg/html/blob/main/LICENSE), copyright WHATWG | Semantic reference for the documented subset; no spec prose, implementation or tests copied |

Runtime exit bridging uses the C `exit` function on native and async's
`runtime/exit` host import on Wasm; it relies on those runtime interfaces.
The included Apache license originates from the `moon new` module scaffold.
Upstream licenses/notices stay in downloaded dependencies; this repository
does not redistribute those dependency implementations.
