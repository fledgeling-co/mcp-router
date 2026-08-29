# `btn primary` in `design/mcp-router-console.html`

| Normaliser | Count |
|---|---|
| Any element whose class attribute carries both words | **35** |
| `<button>` elements only | **33** |
| Class attribute values beginning with the literal `btn primary` | **29** |

Elements examined: **3545**. Dropped, and why: 692 with no class attribute, 2818 with class without both words. Nothing else was discarded, so the three counts above and these drops sum to the whole population.

Carrying `disabled`, as an attribute or as a class: **0** of 35.
A `:disabled` rule that reaches `.primary` anywhere in the file: **yes — .btn.primary:disabled**.

So, at the widest of the three readings: the design of record draws **no** disabled primary — 0 of 35, and its CSS **does** carry a rule that reaches one.
The second half is measured here and asserted in `MockButtonFidelityTests.theMockDimsTheDisabledPrimary`, which reads the rule's body rather than its selector.

## Every site

| Line | Tag | `class` | In the 33 | In the 29 | `disabled` |
|---|---|---|---|---|---|
| :1505 | `button` | `btn primary` | yes | yes | no |
| :1737 | `button` | `btn primary lg` | yes | yes | no |
| :1902 | `button` | `btn primary` | yes | yes | no |
| :2111 | `button` | `btn primary` | yes | yes | no |
| :2165 | `button` | `btn primary lg` | yes | yes | no |
| :2200 | `button` | `btn primary lg` | yes | yes | no |
| :2389 | `button` | `btn primary` | yes | yes | no |
| :2472 | `button` | `btn sm primary` | yes | no | no |
| :2487 | `button` | `btn sm primary` | yes | no | no |
| :2503 | `button` | `btn sm primary` | yes | no | no |
| :2523 | `button` | `btn primary lg` | yes | yes | no |
| :2565 | `button` | `btn primary` | yes | yes | no |
| :2692 | `button` | `btn sm primary` | yes | no | no |
| :2759 | `button` | `btn primary` | yes | yes | no |
| :2796 | `button` | `btn primary lg` | yes | yes | no |
| :2818 | `button` | `btn primary push` | yes | yes | no |
| :2887 | `span` | `btn sm primary push` | no | no | no |
| :3168 | `span` | `btn sm primary` | no | no | no |
| :3281 | `button` | `btn primary` | yes | yes | no |
| :3303 | `button` | `btn primary` | yes | yes | no |
| :3323 | `button` | `btn primary` | yes | yes | no |
| :3580 | `button` | `btn primary` | yes | yes | no |
| :3873 | `button` | `btn primary` | yes | yes | no |
| :3920 | `button` | `btn primary` | yes | yes | no |
| :3958 | `button` | `btn primary` | yes | yes | no |
| :3981 | `button` | `btn primary lg` | yes | yes | no |
| :4087 | `button` | `btn primary` | yes | yes | no |
| :4109 | `button` | `btn primary` | yes | yes | no |
| :4139 | `button` | `btn primary` | yes | yes | no |
| :4165 | `button` | `btn primary` | yes | yes | no |
| :4208 | `button` | `btn primary` | yes | yes | no |
| :4238 | `button` | `btn primary` | yes | yes | no |
| :4269 | `button` | `btn primary` | yes | yes | no |
| :4298 | `button` | `btn primary` | yes | yes | no |
| :4356 | `button` | `btn primary` | yes | yes | no |
