# Media fixture provenance

Verified 2026-10-16. `tree/assets/flower.webm` and `t-rex-roar.mp3` are
unmodified files from [MDN interactive examples](https://github.com/mdn/interactive-examples),
fixed commit [`13024db581b08fae11a0ca229497198b9b0534e7`](https://github.com/mdn/interactive-examples/commit/13024db581b08fae11a0ca229497198b9b0534e7).
This upstream repository is archived; it is used as pinned data, not a runtime
dependency. The upstream [CC0 1.0 Universal license](https://github.com/mdn/interactive-examples/blob/13024db581b08fae11a0ca229497198b9b0534e7/LICENSE)
is retained verbatim in [LICENSE-CC0](LICENSE-CC0).

| File | Fixed upstream path | Bytes | SHA-256 |
|---|---|---|---|
| `tree/assets/flower.webm` | [live-examples/media/cc0-videos/flower.webm](https://github.com/mdn/interactive-examples/blob/13024db581b08fae11a0ca229497198b9b0534e7/live-examples/media/cc0-videos/flower.webm) | 554058 | `C6F8A348953395598A9A73B9BAB1676436410797BCE9F398F4BE1531D6E76DDA` |
| `tree/assets/t-rex-roar.mp3` | [live-examples/media/cc0-audio/t-rex-roar.mp3](https://github.com/mdn/interactive-examples/blob/13024db581b08fae11a0ca229497198b9b0534e7/live-examples/media/cc0-audio/t-rex-roar.mp3) | 39868 | `41191D0727073BF848BCC8F0BD851D71A0B0058E901ABB1C1B236AD327BDA52E` |
| `LICENSE-CC0` | `LICENSE` | 6555 | `36FFD9DC085D529A7E60E1276D73AE5A030B020313E6C5408593A6AE2AF39673` |

The README markup, generic SVG poster, WebVTT caption and move list are authored
for this project under Apache-2.0. No MDN prose, implementation or tests were
copied. The fixture moves the document into `manual` and all four resources into
`media`; `scripts/media-e2e.mbtx` checks review, saved-plan replay, exact bytes,
result snapshot, exact restoration and refusal of a later modified video.
No network or browser playback is needed to validate path/byte preservation.
