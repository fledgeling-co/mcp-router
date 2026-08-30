#!/usr/bin/env python3
"""Did this frame actually paint, or is it a photograph of a window that never drew?

WHY
---
`screencapture -x -l<CGWindowID>` against a window that is behind everything returns whatever
surface the window server last composited. When that is nothing, it returns window chrome and a
title and no content — and it exits 0. Measured on J5's first two lane runs: the `cold` and `stale`
frames came back byte-identical to each other (sha 84a469099e7c, 267622 bytes) while their
accessibility trees differed by 26 rows. The AX plane was right; the pictures agreed about a state
the app was not in, and nothing in the capture channel said so.

A fixture launch photographs correctly, which is why no lane had met this before:
`FixtureControlAPIClient` has its data at the first render, so the first paint carries the board. A
live launch does not — the window exists before the first poll answers, and by the time the board
has something to draw the window server has stopped compositing it. Hide-then-unhide, a
navigate-away-and-back reselect and a resize were each tried against a live cold launch and each
left the surface byte-identical.

WHAT IS CHECKED, AND WHY IT IS NOT A THRESHOLD
----------------------------------------------
**The sidebar's rectangle has to lie inside the window's.** That is an exact invariant of a window
that has laid out, and it is exactly what an unpainted one violates. Measured on the frames above:
the same dump that reports a 980x620 window at y=140 reports the sidebar outline at **y=-537 with a
height of 1964** — a pre-layout geometry that cannot be true of anything on screen. The painted
frames from the same lane, and the nine from `bin/capture-mac-glass.sh`, all report the sidebar at
y=192 with a height of 419, comfortably inside.

A colour count over the sidebar column was tried first and rejected, and the rejection is worth
recording because it is the more obvious design. The unpainted frame is not blank: it carries the
traffic lights, the sidebar-toggle glyph, the window's rounded corners and its shadow, which come to
146 distinct colours against 715 for the painted one. Those separate — but only with a floor chosen
after seeing both numbers, which is fitting a threshold to two samples rather than measuring a
property. The containment test has no threshold at all.

The count is still taken and printed, because it is what a reader wants next when a frame is
refused; it decides nothing.

    paint-check.py <frame.png> <window-dump.txt>

Exit 0 and print what was measured when the frame painted; exit 1 and print the reason when it did
not. Exit 2 when the check itself could not run — a dump with no sidebar row, a crop that does not
resolve — because a check that could not run is never a pass.
"""
from __future__ import annotations

import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:  # pragma: no cover - the lane's own dependency check
    print("paint-check: Pillow is not installed, so nothing was measured", file=sys.stderr)
    raise SystemExit(2) from None

# How far outside the window's own rectangle the sidebar's may sit before the layout is called
# unsettled. One point, because the two are nested and the numbers are exact.
TOLERANCE = 1.0


def frame_of(row: list[str]) -> list[float]:
    return [float(v) for v in row[-5:-1]]


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("usage: paint-check.py <frame.png> <window-dump.txt>", file=sys.stderr)
        return 2
    shot, dump = Path(argv[0]), Path(argv[1])
    # Every line is accounted for rather than filtered away. A blank line in an accessibility dump
    # is framing rather than a row, but "the dump had 92 rows" and "the dump had 92 rows and 400
    # lines this reader could not see" are different statements about the same file, and only the
    # second one is checkable.
    lines = dump.read_text().splitlines()
    rows = [line.split("\t") for line in lines if line.strip()]
    blanks = len(lines) - len(rows)
    window = next((r for r in rows if len(r) > 5 and r[1] == "AXWindow"), None)
    sidebar = next((r for r in rows if len(r) > 5 and r[1] == "AXOutline" and "Sidebar" in r), None)
    if window is None or sidebar is None:
        print("the dump carries no AXWindow or no Sidebar AXOutline, so the sidebar's rectangle "
              "could not be located and nothing was measured", file=sys.stderr)
        return 2

    wx, wy, ww, wh = frame_of(window)
    sx, sy, sw, sh = frame_of(sidebar)

    # The verdict. Everything below it is description.
    outside = not (sx >= wx - TOLERANCE and sy >= wy - TOLERANCE
                   and sx + sw <= wx + ww + TOLERANCE and sy + sh <= wy + wh + TOLERANCE)
    if outside:
        print(f"the window is {ww:.0f}x{wh:.0f} at ({wx:.0f},{wy:.0f}) and its sidebar reports "
              f"{sw:.0f}x{sh:.0f} at ({sx:.0f},{sy:.0f}), which is outside it. A laid-out window "
              f"contains its own sidebar, so this frame is a photograph of a window that never "
              f"finished laying out rather than a photograph of the board. "
              f"(read {len(rows)} row(s) of the dump, skipped {blanks} blank line(s))",
              file=sys.stderr)
        return 1

    image = Image.open(shot)
    # Two unknowns, two equations, as `bin/capture-mac-glass.sh` solves them: the window's points map
    # to pixels at some scale, inside a shadow margin the compositor adds equally on each side.
    scale = (image.width - image.height) / (ww - wh)
    margin = (image.width - ww * scale) / 2
    if abs(scale - round(scale)) > 0.01:
        print(f"the frame's scale solved to {scale}, which is not an integer — the crop would be "
              f"of the wrong region, so nothing was measured", file=sys.stderr)
        return 2

    # The sidebar's column, over the window's own height. Only reached once the containment test
    # above has passed, so the outline's y-range is known to be sane; the window's height is used
    # anyway because the column is what a reader looks at, not the outline's exact extent.
    left = margin + (sx - wx) * scale
    right = margin + (sx + sw - wx) * scale
    top = margin
    bottom = margin + wh * scale
    box = (int(round(left)), int(round(top)), int(round(right)), int(round(bottom)))
    if not (0 <= box[0] < box[2] <= image.width and 0 <= box[1] < box[3] <= image.height):
        print(f"the sidebar crop {box} does not fall inside a {image.width}x{image.height} frame, "
              f"so nothing was measured", file=sys.stderr)
        return 2

    colours = len(set(image.convert("RGB").crop(box).getdata()))
    print(f"sidebar {sw:.0f}x{sh:.0f} at ({sx:.0f},{sy:.0f}) lies inside the {ww:.0f}x{wh:.0f} "
          f"window; its column {box} holds {colours} distinct colour(s) at scale {scale:g} "
          f"(reported, not judged); read {len(rows)} row(s) of the dump and skipped {blanks} "
          f"blank line(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
