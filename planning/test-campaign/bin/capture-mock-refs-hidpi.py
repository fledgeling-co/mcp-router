#!/usr/bin/env python3
"""Rasterise the design of record at the window size the design actually draws.

The references this replaces were captured with `obscura fetch --screenshot`, which
renders at a fixed 1280x720 dpr-1 viewport with no flag to change it. The design's
Mac window is 1156x680, and it sits below a page header inside that page, so a
720-tall viewport clips it: measured on 2026-08-20, the reference PNG's bottom row
carried 578 non-background pixels out of 640 sampled, i.e. content ran off the
frame rather than ending inside it. A reference that does not contain the whole
window cannot be compared against a photograph of the whole window.

CDP's Emulation.setDeviceMetricsOverride is the one emulation domain measured to
work in this engine, so the viewport is set there and the window is cropped out of
the result by locating its own borders in the pixels rather than by trusting a
DOM rect -- `querySelectorAll('div')` returns [] in this engine while
`querySelectorAll('h1,h2,h3')` returns three headings, so element geometry read
back through it is not an oracle here.
"""
import asyncio, base64, json, sys, pathlib, hashlib
import websockets

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 9222
OUT = pathlib.Path(sys.argv[2]) if len(sys.argv) > 2 else pathlib.Path("evidence/shots/mock-hidpi")
MOCK = "file:///Users/lukerhodes/Dev/mcp-router/design/mocks/prototype.html"

# CSS viewport: wide enough for the 1156pt window plus the body's 30pt gutters,
# tall enough for the page header plus the 26pt menubar plus the 680pt window.
VW, VH, DPR = 1280, 900, 2

TARGETS = [
    ("SURF-001", "pane=servers&only=mac"),
    ("SURF-002", "pane=servers&only=mac"),
    ("SURF-003", "pane=activity&only=mac"),
    ("SURF-004", "pane=skills&only=mac"),
    ("SURF-005", "pane=discover&only=mac"),
    ("SURF-006", "pane=evals&only=mac"),
    ("SURF-007", "pane=cleanup&only=mac"),
    ("SURF-008", "pane=inbox&only=mac"),
    ("SURF-009", "pane=inbox&popover=1&only=mac"),
    ("SURF-010", "pane=inbox&sheet=pair&only=mac"),
    ("SURF-011", "pane=settings&only=mac"),
]

class CDP:
    def __init__(self, ws): self.ws, self.n, self.session = ws, 0, None
    async def send(self, method, params=None, session=True):
        self.n += 1
        msg = {"id": self.n, "method": method, "params": params or {}}
        if session and self.session: msg["sessionId"] = self.session
        await self.ws.send(json.dumps(msg))
        while True:
            r = json.loads(await self.ws.recv())
            if r.get("id") == self.n:
                if "error" in r: raise RuntimeError(f"{method}: {r['error']}")
                return r.get("result", {})

async def main():
    OUT.mkdir(parents=True, exist_ok=True)
    # obscura serve exposes the CDP socket directly; it publishes no /json/version.
    async with websockets.connect(f"ws://127.0.0.1:{PORT}/devtools/browser",
                                  max_size=64*1024*1024) as ws:
        c = CDP(ws)
        t = await c.send("Target.createTarget", {"url": "about:blank"}, session=False)
        a = await c.send("Target.attachToTarget",
                         {"targetId": t["targetId"], "flatten": True}, session=False)
        c.session = a["sessionId"]
        await c.send("Page.enable")
        await c.send("Emulation.setDeviceMetricsOverride",
                     {"width": VW, "height": VH, "deviceScaleFactor": DPR, "mobile": False})
        # A CDP method returning without an error proves only that it was accepted, so the
        # override is read back off the page before a single frame is trusted.
        probe = await c.send("Runtime.evaluate",
                             {"expression": "JSON.stringify([innerWidth,innerHeight,devicePixelRatio])",
                              "returnByValue": True})
        got = json.loads(probe["result"]["value"])
        print(f"viewport readback {got}")
        if got != [VW, VH, DPR]:
            raise SystemExit(f"setDeviceMetricsOverride did not take effect: asked "
                             f"{[VW,VH,DPR]}, page reports {got} -- refusing to capture")
        manifest = []
        for sid, query in TARGETS:
            await c.send("Page.navigate", {"url": f"{MOCK}?{query}"})
            await asyncio.sleep(1.4)
            title = json.loads((await c.send("Runtime.evaluate",
                {"expression": "JSON.stringify([document.title,document.body.innerText.slice(0,60)])",
                 "returnByValue": True}))["result"]["value"])
            shot = await c.send("Page.captureScreenshot", {"format": "png"})
            raw = base64.b64decode(shot["data"])
            dest = OUT / f"{sid}.full.png"
            dest.write_bytes(raw)
            manifest.append({"surface": sid, "query": query, "full": str(dest),
                             "title": title[0], "text": title[1],
                             "sha256": hashlib.sha256(raw).hexdigest()})
            print(f"  {sid} {len(raw)//1024}KB sha={manifest[-1]['sha256'][:12]}")
        (OUT / "raw.json").write_text(json.dumps(
            {"viewport": {"width": VW, "height": VH, "deviceScaleFactor": DPR},
             "channel": "obscura-0.2.0 serve --allow-file-access, CDP "
                        "Emulation.setDeviceMetricsOverride + Page.captureScreenshot",
             "viewportReadback": got, "captures": manifest}, indent=2) + "\n")
        print(f"wrote {OUT}/raw.json")

asyncio.run(main())
