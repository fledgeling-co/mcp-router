# Storefront artwork

The console mock embeds every image as a WebP data URI, so nothing here is loaded at runtime —
`design/mcp-router-console.html` stays one self-contained file with 0 external references. This
directory is provenance: what the art is, where it came from, and how to make a matching piece.

| | |
|---|---|
| `gen/icon-set-{a,b,c}-*.png` | the three 1024×1024 generated sheets, four app tiles each |
| `gen/banner-{deploy,market}-*.png` | the two 1536×512 generated banners |
| `gen/px-*.webp` · `gen/banner-*.webp` | the encoded assets actually embedded in the mock |
| `slice-tiles.py` | sheet → four 128px squircle tiles |

**The art depicts capabilities, never publishers.** Every card in the store names a real company —
Anthropic, OpenAI, Google, Vercel, GitHub, Microsoft, Stripe, Fledgeling — and drawing something
that resembled one of their marks would be manufacturing a logo they never made. Each tile shows
what the entry *does* and the publisher is stated in words beside it. Both banners are abstract for
the same reason. Keep that rule if you add to this set.

## Adding a tile

The generator is not deterministic, so the sheets are the only way to match the family — pass the
existing ones as reference images and the new hue will land in the same light model, stroke weight
and squircle. The prompts are recorded in `design/mcp-router-console-spec.md`.

```sh
python3 slice-tiles.py gen/icon-set-c-4f9140.png flow compass canvas ts
cwebp -q 90 -sharp_yuv -alpha_q 100 tile-flow.png -o gen/px-flow.webp
```

Then base64 the `.webp` into a `--ic-*` custom property in the mock's artwork `:root` block and add
the matching `.appicon.i-*` rule. Banners are encoded at q93 rather than q90 — at 90 the gradient
bands visibly across the 1000px width.
