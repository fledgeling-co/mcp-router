#!/usr/bin/env python3
"""Photograph the design-of-record halves at VIEWPORT 1440x900 SETTLE_MS 1200.

Obscura CDP (not Playwright). Target.createTarget then attachToTarget.
Clips to .win (Mac) or .ph2 (phone) so contact-sheet chrome is not the product.
Freezes prototype timers before the settle so two shots of the same pane match.
"""
from __future__ import annotations

import asyncio
import json
import time
from pathlib import Path

import websockets

BROWSER = "ws://127.0.0.1:9334/devtools/browser"

# Derived, never pinned: this file sits at planning/test-campaign/evidence/runs/, so the
# repository root is four parents up. A literal /Users/... path here is correct only on the
# machine that wrote it, and says nothing when it stops being — see G9.
ROOT = Path(__file__).resolve().parents[4]
if not (ROOT / "design" / "mocks" / "prototype.html").exists():
    raise SystemExit(f"FATAL: {ROOT} is not the repository root — this script moved; fix parents[4]")
PROTO = ROOT / "design" / "mocks" / "prototype.html"
SHOTS = ROOT / "planning" / "test-campaign" / "evidence" / "shots"
MOCK = SHOTS / "mock"
VIEWPORT = {"width": 1440, "height": 900}
SETTLE_MS = 1200
DSF = 1

# Existing BUILD shots (never overwrite these). None = no same-surface build capture.
BUILD = {
    "SURF-001": SHOTS / "SURF-001.build.png",
    "SURF-002": SHOTS / "SURF-002.build.png",
    "SURF-003": SHOTS / "SURF-003.build.png",
    "SURF-004": SHOTS / "SURF-004.build.png",
    "SURF-005": SHOTS / "SURF-005.build.png",
    "SURF-006": SHOTS / "SURF-006.build.png",
    "SURF-007": SHOTS / "SURF-007.build.png",
    "SURF-008": SHOTS / "SURF-008.build.png",
    "SURF-009": None,  # NSStatusItem not pressable in background
    "SURF-010": SHOTS / "SURF-010.build.png",  # present on disk; pairing AX was refused earlier
    "SURF-011": SHOTS / "SURF-011.build.png",
    "SURF-012": None,  # ios-boot PNG is Settings, not Discover
    "SURF-013": None,  # add.png is not Triage/Queue/Library
    "SURF-014": None,  # pairing scanner never photographed
}

SURFACES = [
    {"id": "SURF-001", "name": "Mac shell — sidebar, title, menus", "clip": "mac",
     "url": "file://{p}?only=mac&pane=activity"},
    {"id": "SURF-002", "name": "Mac Servers board", "clip": "mac",
     "url": "file://{p}?only=mac&pane=servers"},
    {"id": "SURF-003", "name": "Mac Activity board", "clip": "mac",
     "url": "file://{p}?only=mac&pane=activity"},
    {"id": "SURF-004", "name": "Mac Skills board", "clip": "mac",
     "url": "file://{p}?only=mac&pane=skills"},
    {"id": "SURF-005", "name": "Mac Discover board", "clip": "mac",
     "url": "file://{p}?only=mac&pane=discover"},
    {"id": "SURF-006", "name": "Mac Checks board", "clip": "mac",
     "url": "file://{p}?only=mac&pane=evals"},
    {"id": "SURF-007", "name": "Mac Cleanup board", "clip": "mac",
     "url": "file://{p}?only=mac&pane=cleanup"},
    {"id": "SURF-008", "name": "Mac Inbox board and review sheet", "clip": "mac",
     "url": "file://{p}?only=mac&pane=inbox"},
    {"id": "SURF-009", "name": "Mac menu-bar popover and inbox band", "clip": "mac",
     "url": "file://{p}?only=mac&popover=1"},
    {"id": "SURF-010", "name": "Mac Pairing sheet", "clip": "mac",
     "url": "file://{p}?only=mac&sheet=pair"},
    {"id": "SURF-011", "name": "Mac Settings board", "clip": "mac",
     "url": "file://{p}?only=mac&pane=settings"},
    {"id": "SURF-012", "name": "iOS Discover", "clip": "phone",
     "url": "file://{p}?only=phone&tab=discover"},
    {"id": "SURF-013", "name": "iOS Triage, Queue, Library", "clip": "phone",
     "url": "file://{p}?only=phone&tab=triage"},
    {"id": "SURF-014", "name": "iOS Pairing scanner and code entry", "clip": "phone",
     "url": "file://{p}?only=phone&tab=settings&pairing=scan"},
    {"id": "SURF-015", "name": "Router daemon and upstream pool", "clip": None, "url": None,
     "reason": "no visual design of record (daemon / IPC)"},
    {"id": "SURF-016", "name": "Loopback control API and auth routes", "clip": None, "url": None,
     "reason": "no visual design of record (HTTP control API)"},
    {"id": "SURF-017", "name": "Parity harness vs TypeScript reference", "clip": None, "url": None,
     "reason": "no visual design of record (parity harness)"},
]

FREEZE_JS = """
(() => {
  const highest = setInterval(() => {}, 1e9);
  for (let i = 1; i <= highest; i++) clearInterval(i);
  const tmax = setTimeout(() => {}, 1e9);
  for (let i = 1; i <= tmax; i++) clearTimeout(i);
  try { if (typeof S !== 'undefined') { S.pairSecs = S.pairSecs; } } catch (e) {}
  return {intervalsCleared: highest, timeoutsCleared: tmax};
})()
"""

CLIP_JS = """
(() => {
  const sel = arguments && arguments[0];
})()
"""


class CDP:
    def __init__(self, ws):
        self.ws = ws
        self.n = 0
        self.session = None
        self.pending = {}
        self.events = []

    async def send(self, method, params=None, session=True):
        self.n += 1
        msg = {"id": self.n, "method": method}
        if params:
            msg["params"] = params
        if session and self.session:
            msg["sessionId"] = self.session
        await self.ws.send(json.dumps(msg))
        while True:
            raw = await asyncio.wait_for(self.ws.recv(), timeout=30)
            data = json.loads(raw)
            if data.get("id") == self.n:
                if "error" in data:
                    raise RuntimeError(f"{method}: {data['error']}")
                return data.get("result") or {}
            # drain events

    async def eval(self, expression, await_promise=False):
        r = await self.send("Runtime.evaluate", {
            "expression": expression,
            "returnByValue": True,
            "awaitPromise": await_promise,
        })
        if r.get("exceptionDetails"):
            raise RuntimeError(f"eval: {r['exceptionDetails']}")
        return (r.get("result") or {}).get("value")


async def capture():
    MOCK.mkdir(parents=True, exist_ok=True)
    proto = str(PROTO)
    pairs = []
    log = []

    async with websockets.connect(BROWSER, max_size=32 * 1024 * 1024) as ws:
        c = CDP(ws)
        created = await c.send("Target.createTarget", {"url": "about:blank"}, session=False)
        tid = created["targetId"]
        attached = await c.send("Target.attachToTarget", {"targetId": tid, "flatten": True}, session=False)
        c.session = attached["sessionId"]
        await c.send("Page.enable")
        await c.send("Runtime.enable")
        await c.send("Emulation.setDeviceMetricsOverride", {
            "width": VIEWPORT["width"],
            "height": VIEWPORT["height"],
            "deviceScaleFactor": DSF,
            "mobile": False,
        })
        log.append(f"attached target={tid} session={c.session}")

        for s in SURFACES:
            row = {
                "surface": s["id"],
                "name": s["name"],
                "viewport": VIEWPORT,
                "settleMs": SETTLE_MS,
            }
            if not s.get("url"):
                row["shot"] = None
                row["reference"] = None
                row["reason"] = s["reason"]
                pairs.append(row)
                log.append(f"{s['id']} no-visual {s['reason']}")
                continue

            url = s["url"].format(p=proto)
            await c.send("Page.navigate", {"url": url})
            # wait load
            await asyncio.sleep(0.4)
            freeze = await c.eval(FREEZE_JS)
            await asyncio.sleep(SETTLE_MS / 1000)
            sel = ".win" if s["clip"] == "mac" else ".ph2"
            box = await c.eval(f"""
(() => {{
  const el = document.querySelector({sel!r});
  if (!el) return null;
  const r = el.getBoundingClientRect();
  return {{x: r.x, y: r.y, width: r.width, height: r.height, title: document.title,
           pane: (typeof S!=='undefined' && S.pane) || null,
           tab: (typeof S!=='undefined' && S.tab) || null,
           sheet: (typeof S!=='undefined' && S.sheet) || null,
           popover: (typeof S!=='undefined' && !!S.popover) || false,
           pairing: (typeof S!=='undefined' && S.pairing) || null}};
}})()
""")
            if not box or not box.get("width"):
                log.append(f"{s['id']} CLIP MISS url={url} box={box}")
                row["shot"] = str(BUILD[s["id"]]) if BUILD.get(s["id"]) else None
                row["reference"] = None
                row["reason"] = f"clip selector {sel} produced no box at {url}"
                pairs.append(row)
                continue

            shot = await c.send("Page.captureScreenshot", {
                "format": "png",
                "fromSurface": True,
                "captureBeyondViewport": True,
                "clip": {
                    "x": max(0, box["x"]),
                    "y": max(0, box["y"]),
                    "width": box["width"],
                    "height": box["height"],
                    "scale": 1,
                },
            })
            import base64
            raw = base64.b64decode(shot["data"])
            out = MOCK / f"{s['id']}.png"
            out.write_bytes(raw)
            magic = raw[:8]
            ok = magic == b"\x89PNG\r\n\x1a\n"
            log.append(
                f"{s['id']} bytes={len(raw)} magic={ok} clip={box['width']:.0f}x{box['height']:.0f}"
                f" @({box['x']:.0f},{box['y']:.0f}) freeze={freeze} state={{pane:{box.get('pane')},tab:{box.get('tab')},sheet:{box.get('sheet')},popover:{box.get('popover')},pairing:{box.get('pairing')}}}"
            )

            build = BUILD.get(s["id"])
            if build and build.exists():
                row["shot"] = str(build)
                row["reference"] = str(out)
                row["reason"] = None
            else:
                # Mock is on disk; do not pair a wrong-surface build PNG.
                row["shot"] = None
                row["reference"] = None
                row["reason"] = (
                    f"mock captured at {out.name} ({len(raw)} bytes) but build half is uncaptured "
                    f"or is a different surface; not paired"
                )
            pairs.append(row)

        await c.send("Target.closeTarget", {"targetId": tid}, session=False)

    pairs_path = SHOTS / "pairs.json"
    pairs_path.write_text(json.dumps(pairs, indent=1) + "\n")
    log_path = ROOT / "planning" / "test-campaign" / "evidence" / "runs" / "capture-mocks.log"
    log_path.write_text("\n".join(log) + "\n")
    with_ref = sum(1 for p in pairs if p.get("reference"))
    print(f"CAPTURE PAIRS  surfaces={len(pairs)}  with a reference={with_ref}  without={len(pairs)-with_ref}")
    for line in log:
        print(line)
    print(f"wrote {pairs_path}")
    print(f"wrote {log_path}")


if __name__ == "__main__":
    asyncio.run(capture())
