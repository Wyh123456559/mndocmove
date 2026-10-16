# Svelte responsive README fixture

Verified 2026-10-16. Source: [sveltejs/svelte](https://github.com/sveltejs/svelte),
fixed commit [`40bb08482f4857d91221638dec544a532bc35389`](https://github.com/sveltejs/svelte/commit/40bb08482f4857d91221638dec544a532bc35389).

`tree/header.md` is the verbatim first six lines of the upstream
[README](https://raw.githubusercontent.com/sveltejs/svelte/40bb08482f4857d91221638dec544a532bc35389/README.md),
ending with its newline. The two PNG files are unmodified upstream
[banner.png](https://raw.githubusercontent.com/sveltejs/svelte/40bb08482f4857d91221638dec544a532bc35389/assets/banner.png)
and [banner_dark.png](https://raw.githubusercontent.com/sveltejs/svelte/40bb08482f4857d91221638dec544a532bc35389/assets/banner_dark.png).
MIT copyright and license are retained verbatim in [LICENSE.md](LICENSE.md),
from that commit's upstream license. No endorsement is implied.

| Included file | SHA-256 |
|---|---|
| `tree/header.md` | `AD79B7A16E62AF42B88C152B7C2C32145371EAB0701CACE2E468A5633E9721BF` |
| `tree/assets/banner.png` | `85810AFC1BEDA10F609DF6213D37A9E2FBCA7C7D5EE144D522AEF8FC9B7814BC` |
| `tree/assets/banner_dark.png` | `A4C309D6CEA99AEFC461C27F42173F984E03C22E8D09685FC511DEF1FDE82FB9` |
| `LICENSE.md` | `06257F4847B13A49A039EFB17B944C141E71B12FD8D231B362D86919067D77A3` |

The authored move list puts the header in `manual` and the images in `art`.
Both the dark-mode `source[srcset]` and the fallback `img[src]` must become
`../art/...`. The image bytes and all non-URL markup must survive replay and
exact restoration. CI uses these committed files offline.
