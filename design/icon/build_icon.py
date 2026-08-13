#!/usr/bin/env python3
"""
Engine A — the hand-authored layered SVG master for the mcp-router icon.

Direction: Tahoe gel-glass, dark register (icon-directions.md §2c).
Runner-up: 8 Instrument Emblem, rejected — it drifts flat, and this subject
           wants material.

Device:    a manifold. Three cool-glass conduits converge from the left into a
           single hub capsule; on the right one branch is lit amber and blooming
           while two others sit dormant, short and thin. Many-to-one on the way
           in, lazy-wake on the way out — the product, drawn.

Why a dark ground rather than the template-worn saturated blue tile: the
router's headline state is *nothing running*. Dormancy has to be the ground so
the one waking branch is the only light in the tile. A saturated ground puts
light everywhere and the idea dies.

Material values were sampled off the corpus rather than imagined:
  apple-03 (butterfly)  — dark navy cushion, per-panel rim keyline, no cast shadow
  apple-21 (stickers)   — charcoal ground lighter at top, figure-ground by value
  apple-06 (Home)       — amber gel with the glow building inward, backlit read
  apple-14 (App Store)  — rounded-cap bars, per-bar top-edge keyline, contact
                          shadow authored where bars cross

This is a *decorative* icon (README mark / repo tile), not an Icon Composer
package, so the squircle and its material are baked in deliberately — there is
no compositor downstream to supply them.

Layers still map 1:1 onto Icon Composer groups: bg / mid / fg / highlight.

    python3 build_icon.py            # writes icon-a-manifold.svg beside this file
"""

from pathlib import Path

S = 1024
HERE = Path(__file__).parent
SQUIRCLE = (HERE / "squircle-path.txt").read_text().strip()

# ---------------------------------------------------------------- geometry
HUB = dict(x=436, y=250, w=176, h=524, r=88)
HUB_CX = HUB["x"] + HUB["w"] / 2
HUB_R = HUB["x"] + HUB["w"]
HUB_B = HUB["y"] + HUB["h"]

CONDUIT_W = 78
ENTRY_X = 152
CONDUITS = [(316, 408), (512, 512), (708, 616)]   # (entry_y, hub_y)
CONDUIT_END_X = 500                                # ends inside the hub

LIVE = dict(y=512, x0=548, x1=846, w=84)
DORMANT_W = 60
DORMANT = [352, 672]
DORMANT_X1 = 704

# ---------------------------------------------------------------- palette
GROUND_HI, GROUND_MID, GROUND_LO = "#2C2942", "#211E33", "#14121F"
RIM_TOP, RIM_MID, RIM_BOT = "#A5A2CE", "#6A6890", "#8B88B4"

GLASS_HI, GLASS_LO = "#8582AE", "#57547B"
GLASS_LIT, GLASS_DARK = "#C6C3E8", "#302D48"          # dormant plumbing
GLASS_EDGE = "#C4C2E4"
HUB_HI, HUB_MID, HUB_LO, HUB_FOOT = "#CFCCEE", "#605D8A", "#3E3B60", "#6E6B96"
HUB_EDGE = "#D2D0EE"

AMBER_HI, AMBER_MID, AMBER_LO = "#FFDF9B", "#FDBB5F", "#EF9A31"
AMBER_BLOOM = "#FFB74D"


JOG_IN, JOG_OUT = 286, 404      # where the S-bend starts and lands


def conduit(entry_y: float, hub_y: float) -> str:
    """One inbound line: flat at the wall, one S-jog, flat into the hub."""
    if entry_y == hub_y:
        return f"M{ENTRY_X},{entry_y} L{CONDUIT_END_X},{hub_y}"
    ease = (JOG_OUT - JOG_IN) * 0.55
    return (
        f"M{ENTRY_X},{entry_y} L{JOG_IN},{entry_y} "
        f"C{JOG_IN + ease},{entry_y} {JOG_OUT - ease},{hub_y} {JOG_OUT},{hub_y} "
        f"L{CONDUIT_END_X},{hub_y}"
    )


def stroked(paths, width, **attrs) -> str:
    extra = " ".join(f'{k.replace("_", "-")}="{v}"' for k, v in attrs.items())
    return "\n".join(
        f'      <path d="{d}" stroke-width="{width}" stroke-linecap="round" '
        f'fill="none" {extra}/>'
        for d in paths
    )


def svg() -> str:
    inbound = [conduit(ey, hy) for ey, hy in CONDUITS]
    stubs = [f'M{LIVE["x0"]},{y} L{DORMANT_X1},{y}' for y in DORMANT]
    live = f'M{LIVE["x0"]},{LIVE["y"]} L{LIVE["x1"]},{LIVE["y"]}'

    # Every dormant run, drawn white, becomes the mask the keylines live inside —
    # so a keyline hugs its own curve instead of wandering off it.
    mask_body = stroked(inbound, CONDUIT_W, stroke="#fff") + "\n" + stroked(
        stubs, DORMANT_W, stroke="#fff"
    )

    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="{S}" height="{S}" viewBox="0 0 {S} {S}">
  <title>mcp-router</title>
  <defs>
    <clipPath id="tile"><path d="{SQUIRCLE}"/></clipPath>

    <radialGradient id="ground" cx="50%" cy="30%" r="86%">
      <stop offset="0%"   stop-color="{GROUND_HI}"/>
      <stop offset="58%"  stop-color="{GROUND_MID}"/>
      <stop offset="100%" stop-color="{GROUND_LO}"/>
    </radialGradient>
    <linearGradient id="rim" gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="0" y2="{S}">
      <stop offset="0%"   stop-color="{RIM_TOP}" stop-opacity="0.46"/>
      <stop offset="48%"  stop-color="{RIM_MID}" stop-opacity="0.10"/>
      <stop offset="100%" stop-color="{RIM_BOT}" stop-opacity="0.22"/>
    </linearGradient>

    <linearGradient id="glass" gradientUnits="userSpaceOnUse" x1="0" y1="270" x2="0" y2="750">
      <stop offset="0%"   stop-color="{GLASS_HI}"/>
      <stop offset="100%" stop-color="{GLASS_LO}"/>
    </linearGradient>
    <linearGradient id="hubfill" gradientUnits="userSpaceOnUse"
                    x1="0" y1="{HUB['y']}" x2="0" y2="{HUB_B}">
      <stop offset="0%"   stop-color="{HUB_HI}"/>
      <stop offset="24%"  stop-color="{HUB_MID}"/>
      <stop offset="72%"  stop-color="{HUB_LO}"/>
      <stop offset="100%" stop-color="{HUB_FOOT}"/>
    </linearGradient>

    <linearGradient id="amber" gradientUnits="userSpaceOnUse"
                    x1="{LIVE['x0']}" y1="0" x2="{LIVE['x1']}" y2="0">
      <stop offset="0%"   stop-color="{AMBER_HI}"/>
      <stop offset="52%"  stop-color="{AMBER_MID}"/>
      <stop offset="100%" stop-color="{AMBER_LO}"/>
    </linearGradient>
    <radialGradient id="bloom">
      <stop offset="0%"   stop-color="{AMBER_BLOOM}" stop-opacity="0.80"/>
      <stop offset="42%"  stop-color="{AMBER_BLOOM}" stop-opacity="0.26"/>
      <stop offset="100%" stop-color="{AMBER_BLOOM}" stop-opacity="0"/>
    </radialGradient>

    <filter id="soft" x="-60%" y="-60%" width="220%" height="220%">
      <feGaussianBlur stdDeviation="30"/>
    </filter>
    <filter id="tight" x="-60%" y="-60%" width="220%" height="220%">
      <feGaussianBlur stdDeviation="11"/>
    </filter>
    <filter id="cast" x="-40%" y="-40%" width="180%" height="180%">
      <feGaussianBlur stdDeviation="14"/>
    </filter>

    <mask id="dormant">
      <rect width="{S}" height="{S}" fill="#000"/>
{mask_body}
    </mask>
    <clipPath id="hubclip">
      <rect x="{HUB['x']}" y="{HUB['y']}" width="{HUB['w']}" height="{HUB['h']}" rx="{HUB['r']}"/>
    </clipPath>
    <mask id="livemask">
      <rect width="{S}" height="{S}" fill="#000"/>
      <path d="{live}" stroke="#fff" stroke-width="{LIVE['w']}" stroke-linecap="round" fill="none"/>
    </mask>
  </defs>

  <g clip-path="url(#tile)">

    <!-- ========================================================== bg -->
    <g id="bg">
      <path d="{SQUIRCLE}" fill="url(#ground)"/>
    </g>

    <!-- ========================================================== mid -->
    <!-- dormant plumbing: three lines in, two short stubs out -->
    <g id="mid">
      <g filter="url(#cast)" opacity="0.34">
{stroked(inbound, CONDUIT_W, stroke="#0A0912", transform="translate(0,10)")}
{stroked(stubs, DORMANT_W, stroke="#0A0912", transform="translate(0,9)")}
      </g>
{stroked(inbound, CONDUIT_W + 5, stroke=GLASS_EDGE, stroke_opacity="0.26")}
{stroked(stubs, DORMANT_W + 4, stroke=GLASS_EDGE, stroke_opacity="0.22")}
{stroked(inbound, CONDUIT_W, stroke="url(#glass)")}
{stroked(stubs, DORMANT_W, stroke="url(#glass)")}
      <!-- cylindrical shading, built from bands because a stroke gradient
           cannot follow a curve: lit upper face, keyline, shaded underside,
           each offset by (width - band) / 2 and masked back to its own run -->
      <g mask="url(#dormant)">
{stroked(inbound, CONDUIT_W * 0.44, stroke=GLASS_LIT, stroke_opacity="0.72", transform=f"translate(0,-{CONDUIT_W * 0.28})")}
{stroked(stubs, DORMANT_W * 0.44, stroke=GLASS_LIT, stroke_opacity="0.66", transform=f"translate(0,-{DORMANT_W * 0.28})")}
{stroked(inbound, CONDUIT_W * 0.26, stroke=GLASS_DARK, stroke_opacity="0.50", transform=f"translate(0,{CONDUIT_W * 0.37})")}
{stroked(stubs, DORMANT_W * 0.26, stroke=GLASS_DARK, stroke_opacity="0.44", transform=f"translate(0,{DORMANT_W * 0.37})")}
{stroked(inbound, 9, stroke=GLASS_EDGE, stroke_opacity="0.60", transform=f"translate(0,-{(CONDUIT_W - 9) / 2})")}
{stroked(stubs, 7, stroke=GLASS_EDGE, stroke_opacity="0.52", transform=f"translate(0,-{(DORMANT_W - 7) / 2})")}
      </g>
    </g>

    <!-- ========================================================== fg -->
    <g id="fg">
      <!-- the woken branch, drawn under the hub so the hub occludes its root -->
      <path d="{live}" stroke="url(#amber)" stroke-width="{LIVE['w']}"
            stroke-linecap="round" fill="none"/>
      <g mask="url(#livemask)">
        <path d="{live}" stroke="#FFFBEE" stroke-opacity="0.34" stroke-width="30"
              stroke-linecap="round" fill="none" filter="url(#tight)"/>
        <path d="{live}" stroke="#FFF1CE" stroke-opacity="0.62" stroke-width="{LIVE['w'] * 0.44}"
              stroke-linecap="round" fill="none" transform="translate(0,-{LIVE['w'] * 0.28})"/>
        <path d="{live}" stroke="#B0651A" stroke-opacity="0.44" stroke-width="{LIVE['w'] * 0.26}"
              stroke-linecap="round" fill="none" transform="translate(0,{LIVE['w'] * 0.37})"/>
        <path d="{live}" stroke="#FFFDF4" stroke-opacity="0.80" stroke-width="10"
              stroke-linecap="round" fill="none" transform="translate(0,-{(LIVE['w'] - 10) / 2})"/>
      </g>

      <!-- the hub: everything arrives here -->
      <rect x="{HUB['x']}" y="{HUB['y'] + 13}" width="{HUB['w']}" height="{HUB['h']}"
            rx="{HUB['r']}" fill="#0A0912" opacity="0.34" filter="url(#cast)"/>
      <rect x="{HUB['x']}" y="{HUB['y']}" width="{HUB['w']}" height="{HUB['h']}"
            rx="{HUB['r']}" fill="url(#hubfill)" fill-opacity="0.40"/>
      <!-- authored overlap: what the hub crosses darkens beneath it -->
      <g clip-path="url(#hubclip)" opacity="0.34">
        <rect x="{HUB['x'] - 34}" y="{HUB['y']}" width="76" height="{HUB['h']}"
              fill="#0D0C15" filter="url(#tight)"/>
        <rect x="{HUB_R - 42}" y="{HUB['y']}" width="76" height="{HUB['h']}"
              fill="#0D0C15" filter="url(#tight)"/>
      </g>
      <!-- warm bounce: the branch lights the hub from its own side -->
      <g clip-path="url(#hubclip)">
        <ellipse cx="{HUB_R}" cy="{LIVE['y']}" rx="164" ry="208" fill="url(#bloom)"/>
      </g>
      <rect x="{HUB['x'] + 2.5}" y="{HUB['y'] + 2.5}" width="{HUB['w'] - 5}"
            height="{HUB['h'] - 5}" rx="{HUB['r'] - 2.5}" fill="none"
            stroke="{HUB_EDGE}" stroke-opacity="0.86" stroke-width="5"/>
      <rect x="{HUB['x'] + 8}" y="{HUB['y'] + 8}" width="{HUB['w'] - 16}"
            height="{HUB['h'] - 16}" rx="{HUB['r'] - 8}" fill="none"
            stroke="{HUB_EDGE}" stroke-opacity="0.16" stroke-width="3"/>
    </g>

    <!-- ========================================================== highlight -->
    <g id="highlight">
      <ellipse cx="{LIVE['x0'] + 30}" cy="{LIVE['y']}" rx="185" ry="104"
               fill="url(#bloom)" filter="url(#tight)" opacity="0.95"/>
      <ellipse cx="{LIVE['x1'] - 60}" cy="{LIVE['y']}" rx="175" ry="92"
               fill="url(#bloom)" filter="url(#tight)" opacity="0.8"/>
      <g clip-path="url(#hubclip)">
        <ellipse cx="{HUB['x'] + 40}" cy="{HUB['y'] + 66}" rx="130" ry="150"
                 fill="#EDECFF" opacity="0.17" filter="url(#soft)"/>
      </g>
      <path d="M{HUB['x'] + 36},{HUB['y'] + 26} Q{HUB_CX},{HUB['y'] + 7} {HUB_R - 36},{HUB['y'] + 26}"
            stroke="#E4E2FA" stroke-opacity="0.58" stroke-width="7"
            stroke-linecap="round" fill="none"/>
      <path d="{SQUIRCLE}" fill="none" stroke="url(#rim)" stroke-width="7"/>
    </g>

  </g>
</svg>
"""


if __name__ == "__main__":
    out = HERE / "icon-a-manifold.svg"
    out.write_text(svg())
    print(f"wrote {out}")
