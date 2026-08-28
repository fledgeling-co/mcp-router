#!/usr/bin/env python3
"""Refuse a pixel claim that has no pixels, no distinct pixels, or no named channel.

`make lint` runs this. It is `J3`'s gate, and it exists because the raster-visual rung — the
campaign's one claim that somebody looked at a screen — was accepting all three of those.

WHAT WAS MEASURED, 2026-08-29, `campaign.py check` at `test-campaign` 0.14.1 over
`planning/test-campaign`, full scope, 114 cases and 32 on the raster rung:

  * **28 raster-visual claims cited an artifact that is not a picture.** Six mac-glass cases cited
    `evidence/shots/captures.json`, which is a manifest of captures; two of them also cited
    `evidence/runs/mac-glass-capture.log`. Five swiftui cases cited a verdicts file, a manifest, a
    run log and a wire response between them. Each of the eleven also cited a real PNG, so nothing
    was fabricated — but a rung that accepts a JSON file as its artifact cannot tell the eleven
    from a case that cites only JSON, and one of those was already in the registry (`CASE-0109`,
    held honest by an `n/a:` status rather than by any check).
  * **Three cases published one PNG byte for byte.** `CASE-0185`, `CASE-0186` and `CASE-0187` all
    stood on `evidence/g17-document/readme.served.png`. Two of them read genuinely different
    regions of that frame and the third read no pixels at all, and nothing on the case recorded
    which.
  * **Five pixel claims named no capture method**, so nothing said whether the pixels came off a
    display server, out of an offscreen renderer, or out of a previous run.

The three overlap by case id, which is why they are one gate and not three: the rung was accepting
a claim without demanding a distinct image, from a named channel, of the thing being claimed.

WHY A REPOSITORY GATE WHEN THE SKILL ALREADY CHECKS TWO OF THE THREE. `campaign.py check` finds
the bad artifacts and the shared bytes, and it is how all three were found. It is not in
`make lint` and it cannot be: `vendor/test-campaign/` pins **0.9.2**, whose `campaign.py` has no
`RASTER_RUNGS` and no `inspect_raster` at all, and the version that does is whichever one happens
to be installed in a shared plugin cache on one machine. A rule enforced only by a version nobody
in this repository controls is a rule that leaves with the cache. This runs from the tree, over
the tree, on every lint.

WHAT IT DOES NOT DO, stated rather than implied:

  * **It does not score a picture.** No density, entropy or unique-colour floor: an empty-state
    surface is mostly background by design and a shell error message has much the same ink as the
    empty state it replaced, so a floor cannot separate a failed capture from a sparse screen.
    What is decided here is decidable from the bytes and from the declaration beside them.
  * **It does not establish that a picture is OF its subject.** That is capture lineage's axis —
    the manifest row, the target read back at the shutter, the marker the frame itself drew — and
    `bin/capture-manifest.py`, `capture-lineage.py` and `G17-L1` already hold it. This gate refuses
    the case that has no picture to attribute in the first place.
  * **It reaches `cases.json` only.** The published wall — a surface's `shot`, a flow step's `shot`
    — is `capture-manifest.py`'s population and is deliberately not duplicated here.
  * **A case that did not resolve to `pass` is out of scope**, the same frame `campaign.py` uses. A
    raster case recorded `n/a:` with a reason has said it did not reach a capture, and holding it
    to one would push it toward a picture manufactured to clear a gate.

Exit codes follow the house rule: 0 clean · 1 findings · 2 usage · 3 it measured nothing, which is
not a pass · 4 a control arm misbehaved, so no verdict is printed.
"""
from __future__ import annotations  # `X | None` is evaluated at def time on 3.9; the gates run under /usr/bin/python3

import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
CAMPAIGN_REL = "planning/test-campaign"

RASTER_RUNGS = ("raster-visual",)

# The first bytes of every raster container a capture channel in this campaign can write. A file
# that starts with none of them is not a picture, whatever its suffix says — which is the whole of
# the first finding: `captures.json` and `mac-glass-capture.log` were cited as captures, and both
# announce what they are in their first eight bytes.
RASTER_MAGIC = {
    b"\x89PNG\r\n\x1a\n": "png",
    b"\xff\xd8\xff": "jpeg",
    b"GIF87a": "gif",
    b"GIF89a": "gif",
    b"II*\x00": "tiff",
    b"MM\x00*": "tiff",
    b"BM": "bmp",
}

# HOW THE PIXELS REACHED A FILE. Closed rather than free text, because the finding is that free
# text was absent and a reader could not tell a photograph of a running window from a render. Each
# member is a real channel in this campaign's evidence, counted from the `capture.method` strings
# already recorded: 22 mac captures, 6 phone captures, 1 browser raster, and the two offscreen
# renders this item names for the first time.
CHANNELS = {
    "display-server-window":
        "window-scoped off the OS display server — `screencapture -l<CGWindowID>`, "
        "ScreenCaptureKit. A window that was drawn.",
    "display-server-screen":
        "the whole screen or a region of it off the display server. Photographs whatever is on "
        "top, so it says less about a subject than a window-scoped capture does.",
    "simulator-render-server":
        "off a booted simulator's render server — `XCUIScreen.main.screenshot()`, "
        "`simctl io screenshot`. A window drawn by a device the harness owns.",
    "browser-raster":
        "a browser engine's rasteriser over a live URL. Real pixels of a real response, drawn by "
        "an engine rather than by a window server.",
    "offscreen-render":
        "the hosting view's own backing store, with no display server involved and no window "
        "ordered in. Says the view drew; says nothing about a window a person could have seen.",
}


class Drops:
    """What this reader discarded, named rather than silently skipped.

    `planning/reader-accounting.py` holds every raw-input reader under `planning/` to recording
    what it drops, on the ground that a reader's pass and its cannot-discriminate are otherwise
    indistinguishable. This reader takes 114 cases and keeps the ~30 on the raster rung, so the
    drop is most of its input and the count is printed on every run.
    """

    def __init__(self, subject: str) -> None:
        self.subject = subject
        self.seen = 0
        self.dropped: dict[str, list] = {}

    def keep(self, item: str) -> None:
        self.seen += 1

    def drop(self, item: str, reason: str) -> None:
        """Record WHICH item went missing, not how many did.

        A per-reason counter moves whether or not the drop happened, and a reader that keeps one
        can report a tidy zero over a corpus it silently narrowed. The ids are kept so a run can
        be asked which cases it declined to hold, and the first eight of each class are printed.
        """
        self.seen += 1
        self.dropped.setdefault(reason, []).append(item)

    def total_dropped(self) -> int:
        return sum(len(v) for v in self.dropped.values())

    def report(self) -> None:
        print("%s: %d read · %d kept · %d dropped"
              % (self.subject, self.seen, self.seen - self.total_dropped(),
                 self.total_dropped()))
        for reason in sorted(self.dropped):
            ids = self.dropped[reason]
            shown = ", ".join(ids[:8]) + ("" if len(ids) <= 8 else ", …")
            print("    dropped %d — %s\n      %s" % (len(ids), reason, shown))


def tracked_files(root: str) -> set:
    """What the repository holds, from the index rather than from the working tree.

    `os.path.exists` answers True for an artifact that exists in one worktree and in no commit,
    which is the state 42 evidence logs were in when `evidence-citation-gate.py` was written. A
    capture nobody else can open is not evidence, so the question asked here is the index's.
    """
    out = subprocess.run(["git", "-C", root, "ls-files", "-z"],
                         capture_output=True, check=False)
    if out.returncode != 0:
        return set()
    fields = out.stdout.decode("utf-8", "replace").split("\0")
    if fields and fields[-1] == "":
        fields.pop()
    return set(fields)


def inspect(path: str) -> dict:
    """What a cited artifact actually is, read from its own first bytes."""
    out = {"exists": os.path.exists(path), "kind": None, "bytes": None,
           "sha256": None, "width": None, "height": None, "reason": None}
    if not out["exists"]:
        out["reason"] = "no file at that path"
        return out
    with open(path, "rb") as handle:
        raw = handle.read()
    out["bytes"] = len(raw)
    if not raw:
        out["reason"] = "zero-byte file — the capture wrote nothing"
        return out
    out["sha256"] = hashlib.sha256(raw).hexdigest()
    for magic, kind in RASTER_MAGIC.items():
        if raw.startswith(magic):
            out["kind"] = kind
            break
    if not out["kind"]:
        head = raw[:32].decode("utf-8", "replace").strip().replace("\n", " ")
        out["reason"] = ("not a picture — starts %r. A manifest, a log or a verdicts file is a "
                         "record ABOUT captures, and citing one as a capture is how a structural "
                         "assertion comes to wear the pixel rung's badge" % head[:32])
        return out
    if out["kind"] == "png" and len(raw) >= 24 and raw[12:16] == b"IHDR":
        out["width"] = int.from_bytes(raw[16:20], "big")
        out["height"] = int.from_bytes(raw[20:24], "big")
        if out["width"] <= 1 or out["height"] <= 1:
            out["reason"] = ("%dx%d — a capture this size is a placeholder, not a window"
                             % (out["width"], out["height"]))
    return out


def resolved(status: str) -> str:
    """`pass`, or the word before the colon in a reasoned status."""
    s = (status or "").strip().lower()
    if s in ("pass", "fail", "skip", "open"):
        return s
    return s.split(":", 1)[0].strip() or "open"


def audit(campaign_dir: str, root: str, tracked: set) -> dict:
    """Every finding, and the denominators that make a zero mean something."""
    cases_path = os.path.join(campaign_dir, "cases.json")
    if not os.path.exists(cases_path):
        return {"blocked": "no cases.json at %s" % cases_path}
    with open(cases_path, "r") as handle:
        cases = json.load(handle)

    drops = Drops("cases.json")
    findings = []
    channels: dict[str, int] = {}
    by_sha: dict[str, list] = {}
    examined = []

    def rel(p: str) -> str:
        """A campaign-relative evidence path, rooted for the index question."""
        return p if p.startswith("planning/") else os.path.join(CAMPAIGN_REL, p)

    for case in cases:
        cid = case["id"]
        if case.get("oracle") not in RASTER_RUNGS:
            drops.drop(cid, "not on the raster rung — this gate's subject is the pixel claim")
            continue
        state = resolved(case.get("status", "open"))
        if state != "pass":
            drops.drop(cid, "on the raster rung and did not resolve to `pass` — a case that says "
                            "it did not reach a capture is not held to one")
            continue
        drops.keep(cid)
        examined.append(cid)
        capture = case.get("capture") or {}

        # ── R4. A named channel, from a closed vocabulary.
        channel = capture.get("channel")
        if not channel:
            findings.append((cid, "R4", "names no `capture.channel`, so nothing says whether "
                                        "these pixels came off a display server, out of an "
                                        "offscreen renderer, or out of a previous run"))
        elif channel not in CHANNELS:
            findings.append((cid, "R4", "declares channel %r, which is not one of: %s"
                             % (channel, ", ".join(sorted(CHANNELS)))))
        else:
            channels[channel] = channels.get(channel, 0) + 1
        if not (capture.get("method") or "").strip():
            findings.append((cid, "R4", "names no `capture.method` — the channel says what kind "
                                        "of thing took the picture and the method says which "
                                        "invocation did"))

        # ── R1. An artifact at all.
        shots = list(case.get("evidence") or [])
        if not shots:
            findings.append((cid, "R1", "claims the pixel rung and names no artifact"))

        # ── R2. Every artifact it names is a picture. R6, in the same pass: one the repository
        #        holds, because a capture in one worktree and in no commit is one nobody can open.
        for path in shots:
            info = inspect(os.path.join(root, rel(path)))
            if info["reason"]:
                findings.append((cid, "R2", "%s: %s" % (path, info["reason"])))
            elif info["sha256"]:
                by_sha.setdefault(info["sha256"], []).append("%s:%s" % (cid, path))
            if rel(path) not in tracked:
                findings.append((cid, "R6", "%s is not in the index — an artifact the repository "
                                            "does not hold is one no reader can open" % path))

        # ── R5. A crop names the frame it was cut from, and that frame is a picture too.
        parent = capture.get("derivedFrom")
        if parent:
            info = inspect(os.path.join(root, rel(parent)))
            if info["reason"]:
                findings.append((cid, "R5", "`capture.derivedFrom` names %s: %s"
                                 % (parent, info["reason"])))
            if rel(parent) not in tracked:
                findings.append((cid, "R5", "`capture.derivedFrom` names %s, which is not in "
                                            "the index" % parent))
        for path in (capture.get("source") or []):
            if rel(path) not in tracked:
                findings.append((cid, "R6", "`capture.source` names %s, which is not in the "
                                            "index" % path))

    # ── R3. No two pixel claims stand on the same bytes.
    shared = {sha: ids for sha, ids in by_sha.items() if len(ids) > 1}
    for sha, ids in sorted(shared.items()):
        cids = [i.split(":", 1)[0] for i in ids]
        declarations = []
        for case in cases:
            if case["id"] in cids:
                cap = case.get("capture") or {}
                shares = set(cap.get("sharesWith") or [])
                ok = (set(cids) - {case["id"]}) <= shares and bool(cap.get("sharesReason"))
                declarations.append(ok)
        if not (declarations and all(declarations)):
            findings.append((", ".join(sorted(set(cids))), "R3",
                             "stand on one artifact byte for byte (%s…) — one picture cannot be "
                             "evidence for two different assertions unless every case in the "
                             "group declares `capture.sharesWith` naming the others and a "
                             "`capture.sharesReason`" % sha[:12]))

    return {"findings": findings, "examined": examined, "channels": channels,
            "drops": drops, "cases": len(cases), "shared": shared}


# ─────────────────────────────────────────────────────────────────────────────────────────────
# PRESENCE CONTROL. Runs on every invocation, and its arms are the three findings themselves plus
# the two obligations that follow from them. An absence check cannot detect its own blindness, and
# this one reports zeros over a corpus it may simply have failed to read — so before any verdict is
# printed, a scratch corpus is built in which each rule MUST bite, and one in which none may.
# ─────────────────────────────────────────────────────────────────────────────────────────────

def _png(size: int, red: int) -> bytes:
    """A real PNG, built from stdlib so the control needs no image library.

    `size` is deliberately above the 1x1 placeholder floor R2 enforces — a control whose own
    fixtures trip a rule cannot arm any of the others, which is what the first cut of this control
    did: every arm reported R2 and A0 reddened over its own 1x1 pixels.
    """
    import struct
    import zlib

    raw = b"".join(b"\x00" + bytes([red, 0x40, 0x80] * size) for _ in range(size))

    def chunk(tag: bytes, body: bytes) -> bytes:
        return (struct.pack(">I", len(body)) + tag + body
                + struct.pack(">I", zlib.crc32(tag + body) & 0xFFFFFFFF))

    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw))
            + chunk(b"IEND", b""))


def _clean_case(cid: str, shot: str) -> dict:
    return {"id": cid, "oracle": "raster-visual", "status": "pass",
            "evidence": ["evidence/shots/%s" % shot],
            "capture": {"channel": "display-server-window",
                        "method": "screencapture -x -l<CGWindowID>"}}


def control() -> bool:
    """Plant one fault per rule and require the named rule to be the one that reddens."""
    tmp = tempfile.mkdtemp(prefix="raster-claim-control-")
    try:
        camp = os.path.join(tmp, CAMPAIGN_REL)
        shots = os.path.join(camp, "evidence", "shots")
        os.makedirs(shots)
        with open(os.path.join(shots, "A.png"), "wb") as h:
            h.write(_png(8, 0xC0))
        with open(os.path.join(shots, "B.png"), "wb") as h:
            h.write(_png(8, 0x20))
        with open(os.path.join(shots, "captures.json"), "w") as h:
            h.write('[{"frame": "A", "sha256": "0"}]')
        with open(os.path.join(shots, "UNCOMMITTED.png"), "wb") as h:
            h.write(_png(8, 0x60))
        subprocess.run(["git", "init", "-q", "-b", "main", tmp], check=True, capture_output=True)
        subprocess.run(["git", "-C", tmp, "add", "-A", "--", CAMPAIGN_REL],
                       check=True, capture_output=True)
        # Removed from the index and left on disk: the one state `os.path.exists` cannot see.
        subprocess.run(["git", "-C", tmp, "rm", "-q", "--cached",
                        CAMPAIGN_REL + "/evidence/shots/UNCOMMITTED.png"],
                       check=True, capture_output=True)

        def verdict(cases, note):
            with open(os.path.join(camp, "cases.json"), "w") as handle:
                json.dump(cases, handle)
            a = audit(camp, tmp, tracked_files(tmp))
            if a.get("blocked"):
                return note, set(), a["blocked"]
            return note, {rule for _, rule, _ in a["findings"]}, None

        arms = []
        clean = [_clean_case("CTL-1", "A.png"), _clean_case("CTL-2", "B.png")]

        # A0 — the clean corpus. Without this arm every other arm is satisfied by a gate that
        # reddens on everything, which is the failure mode a control is supposed to exclude.
        arms.append(("A0 clean corpus is green", verdict(clean, "A0"), set()))

        empty = json.loads(json.dumps(clean)); empty[0]["evidence"] = []
        arms.append(("A1 a pixel claim with no artifact", verdict(empty, "A1"), {"R1"}))

        manifest = json.loads(json.dumps(clean))
        manifest[0]["evidence"].append("evidence/shots/captures.json")
        arms.append(("A2 a manifest path seeded onto a pixel claim", verdict(manifest, "A2"), {"R2"}))

        dup = json.loads(json.dumps(clean)); dup[1]["evidence"] = ["evidence/shots/A.png"]
        arms.append(("A3 two cases pointed at one file", verdict(dup, "A3"), {"R3"}))

        nochan = json.loads(json.dumps(clean)); del nochan[0]["capture"]["channel"]
        arms.append(("A4 a pixel claim with no channel", verdict(nochan, "A4"), {"R4"}))

        badchan = json.loads(json.dumps(clean))
        badchan[0]["capture"]["channel"] = "somebody-took-a-photo"
        arms.append(("A5 a channel outside the vocabulary", verdict(badchan, "A5"), {"R4"}))

        nometh = json.loads(json.dumps(clean)); nometh[0]["capture"]["method"] = "  "
        arms.append(("A6 a channel with no method behind it", verdict(nometh, "A6"), {"R4"}))

        crop = json.loads(json.dumps(clean))
        crop[0]["capture"]["derivedFrom"] = "evidence/shots/captures.json"
        arms.append(("A7 a crop derived from something that is not a picture",
                     verdict(crop, "A7"), {"R5"}))

        untracked = json.loads(json.dumps(clean))
        untracked[0]["evidence"] = ["evidence/shots/UNCOMMITTED.png"]
        arms.append(("A8 a capture on disk and in no commit", verdict(untracked, "A8"), {"R6"}))

        # A9 — a declared share is admitted. The rule has to have an honest exit or it teaches
        # people to delete the second case rather than to declare the sharing.
        declared = json.loads(json.dumps(clean))
        declared[1]["evidence"] = ["evidence/shots/A.png"]
        for i, other in ((0, "CTL-2"), (1, "CTL-1")):
            declared[i]["capture"]["sharesWith"] = [other]
            declared[i]["capture"]["sharesReason"] = "one window, declared on both sides"
        arms.append(("A9 a declared share is admitted", verdict(declared, "A9"), set()))

        ok = True
        for label, (_, fired, blocked), expected in arms:
            if blocked:
                print("  CONTROL BLOCKED %s — %s" % (label, blocked))
                ok = False
                continue
            if expected and not expected <= fired:
                print("  CONTROL FAILED %s — expected %s, the gate reported %s"
                      % (label, sorted(expected), sorted(fired) or "nothing"))
                ok = False
            elif not expected and fired:
                print("  CONTROL FAILED %s — nothing should have fired, the gate reported %s"
                      % (label, sorted(fired)))
                ok = False
            else:
                print("  control ok   %s" % label)
        return ok
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def main(argv) -> int:
    if len(argv) > 1 and argv[1] not in ("--quiet",):
        print("usage: raster-claim-gate.py [--quiet]", file=sys.stderr)
        return 2
    quiet = "--quiet" in argv

    print("raster-claim-gate: every pixel claim owes a distinct picture from a named channel")
    if not control():
        print("\nNO VERDICT — a control arm misbehaved, so a zero from this run would be a "
              "reading of the instrument rather than of the corpus.")
        return 4

    campaign_dir = os.path.join(ROOT, CAMPAIGN_REL)
    a = audit(campaign_dir, ROOT, tracked_files(ROOT))
    if a.get("blocked"):
        print("\nINCONCLUSIVE — %s" % a["blocked"])
        return 3

    a["drops"].report()
    print("pixel claims examined: %d of %d cases" % (len(a["examined"]), a["cases"]))
    if a["channels"]:
        print("channels declared: %s"
              % " · ".join("%s %d" % (k, v) for k, v in sorted(a["channels"].items())))

    if not a["examined"]:
        print("\nINCONCLUSIVE — no case on the raster rung resolved to `pass`, so this run "
              "compared nothing. A gate that measured nothing does not report clean.")
        return 3

    if not a["findings"]:
        if not quiet:
            print("\nPASS — %d pixel claim(s), each standing on a picture the repository holds, "
                  "none sharing bytes with another, each naming the channel it came off."
                  % len(a["examined"]))
        return 0

    print("\nFINDINGS raster-claim: %d" % len(a["findings"]))
    for cid, rule, message in a["findings"]:
        print("  %-6s %s — %s" % (rule, cid, message))
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
