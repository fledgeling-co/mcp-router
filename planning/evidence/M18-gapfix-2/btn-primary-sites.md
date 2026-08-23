# `btn primary` in `design/mcp-router-console.html`

| Normaliser | Count |
|---|---|
| Any element whose class attribute carries both words | **35** |
| `<button>` elements only | **33** |
| Class attribute values beginning with the literal `btn primary` | **29** |

Elements examined: **3566**. Dropped, and why: 692 with no class attribute, 2839 with class without both words. Nothing else was discarded, so the three counts above and these drops sum to the whole population.

Carrying `disabled`, as an attribute or as a class: **0** of 35.
A `:disabled` rule that reaches `.primary` anywhere in the file: **none**.

So the claim the count supports — *the design of record never draws a disabled primary,
and its CSS could not dim one* — holds at the widest of the three readings.

## Every site

| Line | Tag | `class` | In the 33 | In the 29 | `disabled` |
|---|---|---|---|---|---|
| :1486 | `button` | `btn primary` | yes | yes | no |
| :1718 | `button` | `btn primary lg` | yes | yes | no |
| :1883 | `button` | `btn primary` | yes | yes | no |
| :2092 | `button` | `btn primary` | yes | yes | no |
| :2146 | `button` | `btn primary lg` | yes | yes | no |
| :2181 | `button` | `btn primary lg` | yes | yes | no |
| :2370 | `button` | `btn primary` | yes | yes | no |
| :2453 | `button` | `btn sm primary` | yes | no | no |
| :2468 | `button` | `btn sm primary` | yes | no | no |
| :2484 | `button` | `btn sm primary` | yes | no | no |
| :2504 | `button` | `btn primary lg` | yes | yes | no |
| :2546 | `button` | `btn primary` | yes | yes | no |
| :2680 | `button` | `btn sm primary` | yes | no | no |
| :2747 | `button` | `btn primary` | yes | yes | no |
| :2787 | `button` | `btn primary lg` | yes | yes | no |
| :2809 | `button` | `btn primary push` | yes | yes | no |
| :2878 | `span` | `btn sm primary push` | no | no | no |
| :3159 | `span` | `btn sm primary` | no | no | no |
| :3272 | `button` | `btn primary` | yes | yes | no |
| :3294 | `button` | `btn primary` | yes | yes | no |
| :3314 | `button` | `btn primary` | yes | yes | no |
| :3571 | `button` | `btn primary` | yes | yes | no |
| :3863 | `button` | `btn primary` | yes | yes | no |
| :3910 | `button` | `btn primary` | yes | yes | no |
| :3948 | `button` | `btn primary` | yes | yes | no |
| :3971 | `button` | `btn primary lg` | yes | yes | no |
| :4077 | `button` | `btn primary` | yes | yes | no |
| :4099 | `button` | `btn primary` | yes | yes | no |
| :4129 | `button` | `btn primary` | yes | yes | no |
| :4155 | `button` | `btn primary` | yes | yes | no |
| :4198 | `button` | `btn primary` | yes | yes | no |
| :4228 | `button` | `btn primary` | yes | yes | no |
| :4259 | `button` | `btn primary` | yes | yes | no |
| :4288 | `button` | `btn primary` | yes | yes | no |
| :4346 | `button` | `btn primary` | yes | yes | no |
