# Category icons — the sixth aesthetic

Fifteen taxonomy chips for the store's Categories block. They are **not** listing
artwork and must not be mistaken for it: the five listing aesthetics (Tahoe
gel-glass, hand-drawn ink-and-wash, and three others) each say "this is a
product". A category says "this is a shelf label", so it gets its own register,
uniform across all fifteen.

Generated with `media-gen-pro` at `style: "openai"` — passed explicitly, because
the server auto-routes icon-shaped prompts to Arrow SVG otherwise.

**Why raster rather than Arrow SVG.** The defect being fixed is a *material*
mismatch: 30px gradient chips with white stroke glyphs sitting directly under
52px drawn listing artwork, which is why the row reads as cheap. A vector glyph,
however detailed, is still a glyph beside artwork, and Arrow's actual advantages
(scales to any size, stays editable) buy nothing at a fixed 38px chip. The page
already made this call once for all 30 listing icons. The one thing SVG would be
better at is recolouring for dark mode, and the listing icons already declined
that trade.

## Style block (identical for all fifteen)

> Soft-sculpted matte 3D icon, single symbol centred on a flat saturated
> background, full-bleed rounded square tile. The symbol is one bold simple form
> extruded slightly off the ground with a soft ambient shadow beneath it, moulded
> in a smooth matte material like painted clay. No gloss, no glass, no specular
> highlights, no reflections, no gradients on the ground. One soft light from the
> upper left. The symbol is off-white cream (#F6F4EF), the ground is the flat hex
> given below with no variation. Generous margin: the symbol occupies about 52%
> of the tile width and is optically centred. Clean edges, no texture, no noise,
> no grain. No text, no letters, no numbers, no logos, no wordmarks, no brand
> marks. Flat-on view, no perspective tilt.

## Ground colours

All fifteen sit at the same relative luminance (0.175), so the row reads as one
family rather than fifteen unrelated chips, and cream on any of them measures
4.67:1. The old palette had six of fifteen inside a 22-degree blue band, which is
why half the row looked identical.

| Category | Hue | Ground | Symbol |
|---|---|---|---|
| Utilities | 8 | `#D33F28` | a spanner, lying at a slight angle |
| Search | 30 | `#A86420` | a magnifying glass, handle to lower right |
| Files | 128 | `#1A8628` | a closed folder, tab on the left |
| Containers | 146 | `#198548` | three stacked rounded cubes |
| Data | 164 | `#198467` | three vertical bars of different heights |
| Web | 180 | `#198181` | a globe with one horizontal band around it |
| Browser | 194 | `#1E7E9B` | a browser window with a title bar and three dots |
| Docs | 208 | `#2577C0` | a single sheet of paper with a folded top corner |
| Dev tools | 222 | `#406FDB` | a terminal prompt chevron above a short underscore |
| Reasoning | 238 | `#6266E1` | one node branching into two, joined by short arms |
| Memory | 256 | `#7F5CE0` | three flat slabs stacked with a gap between each |
| Research | 276 | `#A149DC` | a round-bottomed laboratory flask with a narrow neck |
| Design | 300 | `#C626C6` | a pen nib, point downward |
| Reference | 328 | `#D62985` | a closed hardback book seen from the front |
| Media | 352 | `#D83349` | a play triangle inside a rounded square outline |

## Output

1024×1024 → squircle-safe crop → 96px webp at `docs/img/cat/<slug>.webp`,
displayed at 38px (`.tile.sm`), which is the listing tiles' small size. The chips
therefore match their neighbours in size and material and differ only in subject
and register.

## Regenerated

**Web** and **Reference** were regenerated once. The first globe came back as a
featureless capsule and the first book as a blank card, and both read as an
undifferentiated blob at 38px. The fix in each case was to ask for the feature
that carries the reading — deeply carved latitude and meridian grooves on the
globe, a deep centre gutter on an open book — rather than to re-roll the same
prompt. The other thirteen shipped on their first generation.
