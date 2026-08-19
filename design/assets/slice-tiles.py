#!/usr/bin/env python3
"""Slice a 2x2 generated icon sheet into 128px squircle app tiles.

The sheets in `gen/` are 1024x1024 renders of four macOS-style app icons on a
near-white ground. They cannot be regenerated identically — the model is not
deterministic — so the sheets are the provenance and this script is the only
part of the pipeline that has to be reproducible.

Two details are load-bearing:

  * The tile is found by `(luminance < 600) | (saturation > 40)` rather than by
    quartering the canvas. A plain bounding box includes the drop shadow, which
    drags the square off-centre and leaves a white halo down two edges.
  * The mask is rasterised at 4x and downsampled, because PIL's
    `rounded_rectangle` has no antialiasing and a 128px squircle drawn directly
    has visibly stepped corners against the card ground.

Usage:  python3 slice-tiles.py gen/icon-set-c-4f9140.png flow compass canvas ts
        (names are in reading order: top-left, top-right, bottom-left, bottom-right)
"""
import sys
import numpy as np
from PIL import Image, ImageDraw

OUT = 128
INSET = 0.035      # fraction of the tile's side, to clear the shadow
RADIUS = 0.235     # fraction of the output side; matches the Big Sur squircle
SUPERSAMPLE = 4


def slice_sheet(src: str, names: list[str]) -> None:
    im = Image.open(src).convert("RGB")
    a = np.asarray(im).astype(int)
    mask = (a.sum(axis=2) < 600) | ((a.max(axis=2) - a.min(axis=2)) > 40)

    h, w = mask.shape
    quadrants = [(0, h // 2, 0, w // 2), (0, h // 2, w // 2, w),
                 (h // 2, h, 0, w // 2), (h // 2, h, w // 2, w)]

    for name, (y0, y1, x0, x1) in zip(names, quadrants):
        ys, xs = np.nonzero(mask[y0:y1, x0:x1])
        if len(ys) == 0:
            sys.exit(f"no tile detected in the {name} quadrant of {src}")
        top, bottom, left, right = ys.min(), ys.max(), xs.min(), xs.max()
        side = min(bottom - top, right - left)
        half = side / 2 - side * INSET
        cy, cx = (top + bottom) / 2, (left + right) / 2
        box = (int(x0 + cx - half), int(y0 + cy - half),
               int(x0 + cx + half), int(y0 + cy + half))

        big = OUT * SUPERSAMPLE
        tile = im.crop(box).resize((big, big), Image.LANCZOS).convert("RGBA")
        m = Image.new("L", (big, big), 0)
        ImageDraw.Draw(m).rounded_rectangle([0, 0, big - 1, big - 1],
                                            radius=int(big * RADIUS), fill=255)
        tile.putalpha(m)
        tile.resize((OUT, OUT), Image.LANCZOS).save(f"tile-{name}.png")
        print(f"{name}: box={box} side={side}")


if __name__ == "__main__":
    if len(sys.argv) != 6:
        sys.exit(__doc__)
    slice_sheet(sys.argv[1], sys.argv[2:6])
