// Learn more about moon.mod configuration:
// https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html
//
// To add a dependency, run this command in your terminal:
//   moon add moonbitlang/x
//
// Or manually declare it in `import`, for example:
// import {
//   "moonbitlang/x@0.4.6",
// }

name = "Wyh123456559/mndocmove"

version = "0.1.0"

readme = "README.md"

repository = "https://github.com/Wyh123456559/mndocmove"

license = "Apache-2.0"

keywords = [ "markdown", "refactoring", "documentation", "links" ]

preferred_target = "wasm"

description = "Plan and replay source-preserving Markdown document and asset moves"

import {
  "moonbit-community/cmark@0.4.12",
  "moonbitlang/async@0.22.4",
}
