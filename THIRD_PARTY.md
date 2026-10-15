# Third-party materials

No upstream application implementation or test cases were ported. The project
uses public package APIs. Tests were written for this project's contracts;
format semantics follow CommonMark and URI percent encoding.

| Material | Version/source | License | Use |
|---|---|---|---|
| MoonBit core/runtime | stable 2026-10-12 | Apache-2.0 | Collections, UTF-8, JSON, runtime; generated interfaces/toolchain scaffold |
| [cmark.mbt](https://github.com/moonbit-community/cmark.mbt) | Mooncakes 0.4.12 | Apache-2.0 | Markdown parser and source positions; char entity/unescape API |
| [async](https://github.com/moonbitlang/async) | Mooncakes 0.22.4 | Apache-2.0 | CLI filesystem and test automation process host |
| cmark transitive data packages | charclass 0.1.4, casefold 0.1.7, ucd 0.5.0 | Apache-2.0 package licenses; Unicode notices retained upstream | Parser character data |
| Microsoft Markdown language service | pinned fixture [source](examples/vscode/SOURCE.md) | MIT, retained [license](examples/vscode/LICENSE) | Unmodified README and linked example as real input data |

Runtime exit bridging uses the C `exit` function on native and async's
`runtime/exit` host import on Wasm; it relies on those runtime interfaces.
The included Apache license originates from the `moon new` module scaffold.
Upstream licenses/notices stay in downloaded dependencies; this repository
does not redistribute those dependency implementations.
