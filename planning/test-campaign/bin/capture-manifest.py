#!/usr/bin/env python3
"""Assemble `evidence/shots/captures.json` from the manifests the capture steps write.

WHY THIS EXISTS, MEASURED
-------------------------
`capture-lineage.py --gate` reported SURF-028's published frame as RECONSTRUCTED: the
recorded sha256 disagreed with the bytes on disk. The obvious reading -- "the manifest was
written after the shutter" -- is wrong here, and the git history says so exactly:

    39102ac  png=9d048beb8c7eb6a3   captures.json=9d048beb8c7eb6a3   agree
    3189d02  png=a54c084a5e62dbc3   captures.json=9d048beb8c7eb6a3   disagree

`"sha256": hashlib.sha256(open(png, "rb").read()).hexdigest()`, `bin/g17-document-flow.sh:238` at `16b5ca9` and `:326` writes a sha256 for every frame as it renders and
re-stamps it at the end of the run, into its OWN manifest at
`evidence/g17-document/captures.json`. That file still agrees with all five frames byte for
byte. What went stale was the HAND-COPIED duplicate of those rows in the top-level manifest:
`3189d02` re-rendered the frames after a renumber and nothing re-copied them.

So the defect is not the capture step. It is that the file the gate reads was maintained by
hand, alongside per-lane manifests that were written at capture time and were correct. A
copy nobody derives goes stale on the next run of the thing it copied, and there is no
signal when it does -- the gate's RECONSTRUCTED pass is the signal, four commits later.

This script makes the top-level manifest DERIVED. Every row comes from the lane manifest the
capturing process wrote, so a re-run of any lane changes the gate's copy in the same
movement as the frames. `--check` is the gate: it exits 1 when the derived manifest and the
committed one disagree, which is the state the campaign was in at HEAD.

WHAT IT DOES NOT DO
-------------------
It does not invent provenance. Two lanes have no capture-time manifest at all:

  * `evidence/shots/surf-022-consent-auth-states.png` -- CASE-0157 records the channel in
    its own `capture.method`, which is a record made alongside the case rather than by the
    shutter, and no digest was ever recorded. Its row says so and carries no `target` and no
    `sha256`, so `attach-shots.py` keeps reporting SURF-022 as resting on its filename. That
    is the true state; closing it needs a re-take through a channel that writes a manifest.
  * the glass lane writes its rows straight into the top-level file from
    `bin/capture-mac-glass.sh` and its `.captures.ndjson` scratch file is not committed, so
    those rows are PRESERVED from the committed manifest rather than re-derived. They are
    still capture-time rows; they simply have no separate source file to derive from.

    python3 bin/capture-manifest.py [--check | --write]
"""
from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

CAMPAIGN = Path(__file__).resolve().parent.parent
MANIFEST = CAMPAIGN / "evidence/shots/captures.json"
SHOTS = CAMPAIGN / "evidence/shots"

# Directories whose contents are renders of the DESIGN rather than photographs of the build.
# `capture-lineage.py` and `attach-shots.py` both exclude a directory named exactly `mock`,
# which is why `mock-hidpi/` is still walked by both -- DEF-054 / X8, upstream.
MOCK_DIRS = {"mock", "mock-hidpi"}


def sha_of(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


def target_from_readback(title: str) -> str:
    """The address a Mac board capture was pointed at, from the window title the AX layer
    read back AT THE SHUTTER. This is the same construction `+ title.strip().lower().replace(`, `bin/capture-mac-glass.sh:191` at `16b5ca9`
    performs inline while capturing, applied to `design-size`'s capture-time readback, which
    that script records and does not turn into a target."""
    return "app://mac/" + title.strip().lower().replace(" ", "-")


# --------------------------------------------------------------------------------------
# Dispositions. Every frame on disk is either published by a subject in `inventory.json` or
# carries a reason it is not, and the reason is a judgement about the campaign rather than
# something a script can derive -- so it is written here, in a diff a reader can review, and
# never generated.
# --------------------------------------------------------------------------------------
SECOND_STATE = ("a second state of a surface the wall already shows. `inventory.json` renders one "
                "`shot` per subject, so the extra scenario states are carried by the cases that "
                "cite them ({cases}) rather than by the wall.")

PER_FILE = {
    "evidence/shots/SURF-001.build.png":
        "the Servers window SURF-001 declares a share of. SURF-001 publishes the sidebar crop taken "
        "out of it (`SURF-001.shell.png`, named in that row's `derivedFrom`), so publishing this "
        "frame too would put the same pixels on the wall twice under two captions.",
    "evidence/shots/DEF-059.insights-filed-as-SURF-011.png":
        "DEF-059's own exhibit, kept deliberately. These are the Insights board's pixels, and until "
        "this commit they sat at `evidence/shots/SURF-011.build.png` and were published as the Mac "
        "Settings board. `axkit select Settings` stopped working when M15 made Settings a Scene, the "
        "app stayed on whichever board the loop visited last, and the shutter filed those pixels "
        "under SURF-011's filename -- the exact failure `capture-lineage.py` exists to find, and the "
        "one its tie pass caught, because the capture step recorded `target: app://mac/insights` "
        "honestly while the filename said otherwise. `bin/capture-mac-glass.sh:165-169` now refuses to "
        "photograph a select that did not take. Renamed rather than deleted so the defect keeps its "
        "evidence, and renamed rather than left in place so no filename-matching tool can offer it "
        "to SURF-011 again.",
    "evidence/shots/SURF-002.addserver.png":
        "a witnessed capture of the `Add an MCP server` sheet drawn over the Servers board, from the "
        "2026-08-20 glass run. Nothing publishes it because NO SURFACE ENUMERATES THAT SHEET: "
        "`inventory.json` has no id for it and no case cites it, so it is a picture of a control the "
        "product has and the campaign never counted. Kept rather than deleted -- the frame is real "
        "evidence and deleting it would remove the only trace of the gap. Enumerating the sheet as a "
        "surface with its own cases is coverage work and belongs to a coverage item, not to this one.",
    "evidence/shots/ios/UNASSERTED.ios.after-tapping-pair-mac.png":
        "a third capture of app://ios/pair-mac, asserted by nothing and named UNASSERTED so no "
        "filename match can present it as a second independent proof. Its `unassertedReason` carries "
        "the full argument.",
    "evidence/shots/surf-022-consent-auth-states.png":
        "the wall does not show it; CASE-0157 cites it as raster evidence of the consent screen's "
        "states. It is kept unpublished because its provenance cannot be made good without "
        "re-taking it -- see `provenanceGap` on this row.",
}

LANE_REASON = {
    "design-size":
        "the build half of the mockup-fidelity pairs, photographed at the DESIGN's own window size "
        "(1156x680) rather than the campaign's 980x620. `bin/crop-fidelity-pairs.py` crops it to the "
        "window's own content box; the wall publishes the 980x620 glass captures, so this frame is an "
        "input to the comparison rather than a picture of the surface.",
    "fidelity":
        "a derived crop, not a capture. `evidence/shots/fidelity/pairs.json` is what be-my-witness "
        "reads, and it names both halves, the image each was cropped from and the box. A crop of one "
        "half of a comparison is not the surface's picture and must never be published as one.",
    "mock-hidpi":
        "a render of the DESIGN OF RECORD, not a photograph of the build. Publishing one of these as a "
        "surface's `shot` is exactly DEF-054: `attach-shots.py --apply` would repoint 11 surfaces at "
        "these files, because its mock exclusion matches a directory named exactly `mock` and this one "
        "is `mock-hidpi`. Kept as the design source the fidelity pairs crop from.",
    "ios":
        "a second state of an iOS surface the wall already shows for that subject. The cases that cite "
        "it carry it.",
}


def cases_citing() -> dict[str, list[str]]:
    cases = json.loads((CAMPAIGN / "cases.json").read_text())
    out: dict[str, list[str]] = {}
    for c in cases:
        for e in c.get("evidence") or []:
            out.setdefault(e, []).append(c["id"])
    return out


def published_paths() -> dict[str, str]:
    """Every path `inventory.json` puts on the wall, mapped to the subject that publishes it --
    surfaces and flow steps alike, because the evidence page renders a `shot` on either."""
    inv = json.loads((CAMPAIGN / "inventory.json").read_text())
    out = {s["shot"]: s["id"] for s in inv.get("surface", []) if s.get("shot")}
    for f in inv.get("flow", []):
        out.update({st["shot"]: st["id"] for st in f.get("steps", []) if st.get("shot")})
    return out


def derive() -> list[dict]:
    committed = {e["path"]: e for e in json.loads(MANIFEST.read_text())}
    citing = cases_citing()
    rows: dict[str, dict] = {}

    # --- the glass lane. No separate source file (see the module docstring), so its rows are
    # carried forward from the committed manifest, which is where the capture step wrote them.
    for path, e in committed.items():
        if path.startswith("evidence/shots/") and "/" not in path[len("evidence/shots/"):]:
            rows[path] = dict(e)

    # --- iOS: `evidence/shots/ios/captures.json`, written by the XCTAttachment collector.
    ios = json.loads((SHOTS / "ios/captures.json").read_text())
    for e in ios:
        rows[e["path"]] = dict(e)

    # --- the capability-document lane: `evidence/g17-document/captures.json`, written and
    # re-stamped by `bin/g17-document-flow.sh` as it renders. THIS is the row set the
    # top-level manifest had a stale hand copy of.
    g17 = json.loads((CAMPAIGN / "evidence/g17-document/captures.json").read_text())
    for e in g17:
        rows[e["path"]] = dict(e)

    # --- design-size: `bin/capture-mac-design-size.sh` records the shutter's own window-title
    # readback and the digest; it records no `target`, so one is constructed from the readback
    # by the same rule the glass script applies at capture time.
    ds = json.loads((SHOTS / "design-size/captures.json").read_text())["captures"]
    for e in ds:
        title = e["conditions"]["windowTitleReadback"]
        rows[e["path"]] = {
            "path": e["path"], "subject": e["subject"],
            "target": target_from_readback(title),
            "targetSource": "constructed from `conditions.windowTitleReadback`, which the capture "
                            "step recorded at the shutter; `bin/capture-mac-design-size.sh` writes "
                            "no `target` field of its own",
            "channel": e["channel"], "derivedFrom": None, "sha256": e["sha256"],
            "conditions": e["conditions"], "witnessed": e["witnessed"],
            "frameStatus": e.get("frameStatus"),
        }

    # --- mock-hidpi: `evidence/shots/mock-hidpi/raw.json`, written by
    # `bin/capture-mock-refs-hidpi.py` over CDP against the prototype.
    raw = json.loads((SHOTS / "mock-hidpi/raw.json").read_text())
    for e in raw["captures"]:
        rows[e["full"]] = {
            "path": e["full"], "subject": None,
            "depicts": f"the design of record for {e['surface']}, not the build",
            # No `target`, deliberately, and this is a typing decision rather than a withheld
            # fact. `target` means "what the channel was pointed at AS THIS SUBJECT'S CAPTURE",
            # and this frame is no subject's capture -- it is the prototype. The address the
            # channel was pointed at is recorded in full as `renderedFrom`. Writing it as
            # `target` would make `attach-shots.py` report these 11 files as corroborated
            # attachments for SURF-001..011 while its --apply still proposes filing the DESIGN
            # as the build, which is DEF-054: it compares nothing, it only checks the field is
            # present. Measured both ways on this tree — with `target` written, the
            # uncorroborated count falls 12 -> 1 and --apply's refusal disarms.
            "target": None,
            "renderedFrom": f"design/mocks/prototype.html?{e['query']}",
            "attachHazard": "DEF-054 / X8 — `attach-shots.py`'s mock exclusion matches a directory "
                            "named exactly `mock`, so it walks `mock-hidpi/` and offers this render "
                            "to a surface on its filename. Any tool that attaches this file to a "
                            "surface is doing so on the filename alone.",
            "channel": raw["channel"], "derivedFrom": None, "sha256": e["sha256"],
            "conditions": {"viewport": raw["viewport"], "viewportReadback": raw["viewportReadback"],
                           "titleReadback": e["title"]},
            "witnessed": False,
        }

    # --- fidelity: `evidence/shots/fidelity/pairs.json`, written by `bin/crop-fidelity-pairs.py`,
    # which records both digests and the image and box each half was cropped from.
    pairs = json.loads((SHOTS / "fidelity/pairs.json").read_text())
    for p in pairs["pairs"]:
        for half, chan_key, sha_key, src_key in (
            ("design", "designChannel", "designSha256", "designCropFrom"),
            ("build", "buildChannel", "buildSha256", "buildCropFrom"),
        ):
            rows[p[half]] = {
                "path": p[half], "subject": None,
                "depicts": f"the {half} half of the fidelity pair for {p['surface']}",
                # Same typing as the mock rows: a crop has no subject, so it makes no `target`
                # claim. What it was cut out of is the checkable fact, and that is `derivedFrom`.
                "target": None,
                "croppedFrom": rows.get(p[src_key]["image"], {}).get(
                    "target") or rows.get(p[src_key]["image"], {}).get("renderedFrom"),
                "channel": pairs[chan_key],
                "derivedFrom": p[src_key]["image"],
                "cropBox": p[src_key]["box"],
                "sha256": p[sha_key],
                "conditions": {"size": p["size"], "window": pairs["window"]},
                "witnessed": False,
            }

    # --- the one frame with no capture-time record anywhere.
    rows["evidence/shots/surf-022-consent-auth-states.png"] = {
        "path": "evidence/shots/surf-022-consent-auth-states.png", "subject": None,
        "target": None, "channel": None, "derivedFrom": None, "sha256": None,
        "provenanceGap": "No capture-time manifest row was ever written for this frame. "
                         "`cases.json` CASE-0157 records `capture.method` as 'obscura fetch "
                         "--allow-private-network --screenshot, 1280x720 viewport, live /authorize "
                         "route', which is a record made alongside the case rather than by the "
                         "shutter, and no digest was recorded at all. A `target` and a `sha256` "
                         "written now would say what somebody believes rather than what the channel "
                         "did, so neither is written. `attach-shots.py` therefore keeps reporting "
                         "SURF-022 as resting on its filename, correctly. Re-taking it through a "
                         "channel that writes captures.json is the only thing that closes it.",
        "witnessed": False,
    }

    # --- dispositions, and the one place a published subject is resolved.
    pub = published_paths()
    for path, row in rows.items():
        if path in pub:
            row.pop("unpublishedReason", None)
            # A parameterised surface is published by its FLOW STEPS, because a step is that
            # surface at one concrete address and the surface itself is a family of them. The
            # capture step already recorded which step each frame belongs to -- `step` in the
            # g17 lane manifest, written from `manifest.tsv` at render time -- so the `subject`
            # claim is narrowed to that step ONLY when the step doing the publishing is the
            # same one the channel recorded. A disagreement is left alone and the lineage gate
            # reports it, which is the whole point of the field.
            step = row.get("step")
            if step and pub[path] == step and row.get("subject") != step:
                row["subjectNote"] = (
                    f"the capture step recorded `subject: {row['subject']}` and "
                    f"`step: {step}`; {step} is the subject that publishes this frame, so the "
                    f"narrower of the two capture-time claims is the one recorded here. "
                    f"{row['subject']}'s route is the template "
                    f"`app://mac/servers/{{server}}/document` and this frame was rendered "
                    f"against one instance of it.")
                row["subject"] = step
            continue
        lane = Path(path).parent.name
        reason = PER_FILE.get(path)
        if reason is None and lane in LANE_REASON:
            reason = LANE_REASON[lane]
        if reason is None:
            cites = citing.get(path)
            if not cites:
                raise SystemExit(f"no disposition for {path} — it is on disk, nothing publishes it, "
                                 f"and no case cites it. Publish it, delete it, or write its reason "
                                 f"into PER_FILE above.")
            reason = SECOND_STATE.format(cases=", ".join(cites))
        row["unpublishedReason"] = reason

    return [rows[k] for k in sorted(rows)]


def verify(rows: list[dict]) -> list[str]:
    """A row whose recorded digest disagrees with the bytes is the RECONSTRUCTED finding, and
    it is caught here rather than four commits later, because this is where the copy is made."""
    bad = []
    for r in rows:
        p = CAMPAIGN / r["path"]
        if not p.exists():
            bad.append(f"{r['path']}: no file at that path")
        elif r.get("sha256") and sha_of(p) != r["sha256"]:
            bad.append(f"{r['path']}: the lane manifest records {r['sha256'][:12]} and the bytes "
                       f"are {sha_of(p)[:12]}. The capture step and the file disagree — re-run the "
                       f"lane rather than restamping the row.")
    # Every frame on disk must appear, or the assembly is not covering what the gate walks.
    seen = {r["path"] for r in rows}
    for p in sorted(SHOTS.rglob("*")):
        if p.suffix.lower() != ".png":
            continue
        if MOCK_DIRS & {q.lower() for q in p.relative_to(SHOTS).parts[:-1]}:
            continue
        rel = str(p.relative_to(CAMPAIGN))
        if rel not in seen:
            bad.append(f"{rel}: on disk and named by no lane manifest")
    return bad


def main() -> int:
    rows = derive()
    bad = verify(rows)
    if bad:
        print(f"{len(bad)} problem(s) assembling {MANIFEST.relative_to(CAMPAIGN)}:")
        for b in bad:
            print(f"   {b}")
        return 1
    text = json.dumps(rows, indent=1) + "\n"
    if "--write" in sys.argv:
        MANIFEST.write_text(text)
        print(f"wrote {MANIFEST.relative_to(CAMPAIGN)} — {len(rows)} row(s) from the lane manifests")
        return 0
    if text != MANIFEST.read_text():
        print(f"{MANIFEST.relative_to(CAMPAIGN)} is not what the lane manifests say.\n"
              f"A hand-maintained copy of a capture-time record goes stale on the next run of the "
              f"lane it copies, with no signal until `capture-lineage.py` reports it as "
              f"RECONSTRUCTED. Re-run with --write.")
        return 1
    print(f"{MANIFEST.relative_to(CAMPAIGN)} matches the lane manifests — {len(rows)} row(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
