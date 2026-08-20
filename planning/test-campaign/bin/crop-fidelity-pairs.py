#!/usr/bin/env python3
"""Crop both halves of each Mac pair down to the window itself, at matching scale.

The two halves arrive framed differently and neither framing is the window:

  * the build capture is `screencapture -l<CGWindowID>`, which pads the window with the
    shadow it casts -- 2448x1496 around a 1156x680 window at dpr 2, so 68 device px on
    every side. The solve is the one the 980pt run already uses:
    scale = (2448-1496)/(1156-680) = 2.0, margin = (2448 - 1156*2)/2 = 68.
  * the design capture is a whole 1280x900 page at dpr 2, inside which the window is one
    element among a page header, a simulated menu bar and a drop shadow.

Both are cropped to the window's own content box, which makes them 2312x1360 each -- the
same pixels of the same thing, so a difference between them is a difference in the product
rather than in how it was photographed.

The design-side crop is measured off each image rather than assumed, because the page
header wraps differently per pane and would shift the window down. It is measured from the
pixels rather than from a DOM rect: `document.querySelectorAll('div')` returns [] in this
engine while `querySelectorAll('h1,h2,h3')` returns three headings, so element geometry
read back through it is not an oracle. Every crop is checked to land on the window's own
border on all four sides, and a crop that does not is refused rather than written.
"""
import json, pathlib, sys, hashlib
from PIL import Image

CAMPAIGN = pathlib.Path(__file__).resolve().parent.parent
REF_DIR = CAMPAIGN / "evidence/shots/mock-hidpi"
BUILD_DIR = CAMPAIGN / "evidence/shots/design-size"
OUT = CAMPAIGN / "evidence/shots/fidelity"

WIN_W, WIN_H = 1156 * 2, 680 * 2       # the design's window, at dpr 2
MENUBAR_H = 26 * 2                     # the mock draws the system menu bar above the window
BUILD_MARGIN = 68                      # shadow padding screencapture adds around the window


def border(c):
    """A window border pixel. The borders are rgba(255,255,255,.09) over a near-black
    ground, so a real border reads around 56 while the page background is 14 and the
    drop shadow below the window is darker still."""
    return sum(c[:3]) / 3 >= 40


def lit(c, bg):
    """Any painted pixel: brighter than the page background rather than a border."""
    return sum(c[:3]) / 3 > sum(bg[:3]) / 3 + 4


def design_crop(path):
    im = Image.open(path).convert("RGB")
    W, H = im.size
    px = im.load()
    bg = px[3, 3]
    # The .mac column: the body pads 30pt, so 60 device px, and the window is WIN_W wide.
    x0 = 60
    x1 = x0 + WIN_W - 1
    mid = x0 + WIN_W // 2
    # Anchor on the window's BOTTOM border rather than its top. The top-left corner the
    # menu bar draws is rounded (border-radius 8px), so the first painted pixel down the
    # left edge sits below the true top and a crop keyed to it lands inside the chrome.
    # Nothing is painted below the window except its own drop shadow, which is DARKER
    # than the page, so the last border-bright row in the middle column is unambiguous.
    y1 = None
    for y in range(H - 1, -1, -1):
        if border(px[mid, y]):
            y1 = y
            break
    if y1 is None:
        raise SystemExit(f"{path.name}: found no window bottom border in the middle column")
    y0 = y1 - WIN_H + 1
    if y0 < 0:
        raise SystemExit(f"{path.name}: the window runs off the top of the frame "
                         f"(would start at row {y0}) — the reference is clipped")
    edges = {"left": border(px[x0, y0 + WIN_H // 2]),
             "right": border(px[x1, y0 + WIN_H // 2]),
             "bottom": border(px[mid, y1]),
             # Above the window is the mock's simulated menu bar, which is painted; below
             # it is the page or the window's own shadow, which is not.
             "menubarAbove": lit(px[mid, y0 - MENUBAR_H // 2], bg),
             "clearBelow": not lit(px[mid, min(H - 1, y1 + 6)], bg)}
    return im, (x0, y0, x1 + 1, y1 + 1), edges


def build_crop(path):
    im = Image.open(path).convert("RGB")
    W, H = im.size
    scale = (W - H) / (1156 - 680)
    margin = (W - 1156 * scale) / 2
    if abs(scale - 2.0) > 1e-6 or abs(margin - BUILD_MARGIN) > 1e-6:
        raise SystemExit(f"{path.name}: solved scale={scale} margin={margin}, expected 2.0/68 "
                         f"— the window was not the size this crop assumes")
    m = int(margin)
    return im, (m, m, m + WIN_W, m + WIN_H), None


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    build = {c["subject"]: c for c in json.loads((BUILD_DIR / "captures.json").read_text())["captures"]}
    rows = []
    for sid in sorted(build):
        ref_path = REF_DIR / f"{sid}.full.png"
        build_path = CAMPAIGN / build[sid]["path"]
        if not ref_path.exists():
            print(f"  {sid}: no design capture — skipped")
            continue
        rim, rbox, redges = design_crop(ref_path)
        bim, bbox, _ = build_crop(build_path)
        if not all(redges.values()):
            raise SystemExit(f"{sid}: the design crop does not land on the window border "
                             f"on all four sides: {redges} — refusing to write it")
        out_r = OUT / f"{sid}.design.png"
        out_b = OUT / f"{sid}.build.png"
        rim.crop(rbox).save(out_r)
        bim.crop(bbox).save(out_b)
        wr, hr = Image.open(out_r).size
        wb, hb = Image.open(out_b).size
        if (wr, hr) != (wb, hb) != (WIN_W, WIN_H):
            raise SystemExit(f"{sid}: crops disagree — design {wr}x{hr}, build {wb}x{hb}")
        rows.append({
            "surface": sid,
            "design": f"evidence/shots/fidelity/{out_r.name}",
            "build": f"evidence/shots/fidelity/{out_b.name}",
            "size": [wr, hr],
            "designCropFrom": {"image": f"evidence/shots/mock-hidpi/{ref_path.name}", "box": list(rbox)},
            "buildCropFrom": {"image": build[sid]["path"], "box": list(bbox)},
            "designBorderHit": redges,
            "designSha256": hashlib.sha256(out_r.read_bytes()).hexdigest(),
            "buildSha256": hashlib.sha256(out_b.read_bytes()).hexdigest(),
        })
        print(f"  {sid}: {wr}x{hr} both halves, design box {rbox}, build box {bbox}")
    (OUT / "pairs.json").write_text(json.dumps({
        "window": {"points": [1156, 680], "devicePixels": [WIN_W, WIN_H], "deviceScaleFactor": 2},
        "designChannel": "obscura-0.2.0 serve --allow-file-access, CDP "
                         "Emulation.setDeviceMetricsOverride 1280x900@2 + Page.captureScreenshot, "
                         "cropped to the window's own borders",
        "buildChannel": "screencapture -x -l<CGWindowID> at an AX-set 1156x680 frame, "
                        "cropped by the shadow-margin solve",
        "pairs": rows}, indent=2) + "\n")
    print(f"wrote {OUT}/pairs.json — {len(rows)} pairs at {WIN_W}x{WIN_H}")


main()
