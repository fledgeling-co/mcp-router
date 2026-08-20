#!/usr/bin/env python3
"""Rename XCUITest attachments to the names their tests gave them.

`xcresulttool export attachments` writes opaque filenames plus a `manifest.json` that maps each
one to the test that produced it and the name the test set. The opaque names are what makes a
capture unattributable, and attribution is the whole reason this lane's evidence is admissible:
the runner takes each picture inside a test, after that surface's own identity assertion has
already passed.

So this renames each file to `<attachment name>.png` and leaves `manifest.json` in place as the
record of which test produced which file. It prints the count, and a count of zero is an error —
a lane that exported nothing has photographed nothing, and reporting that as a clean run is the
failure the campaign's `-glass` suffix exists to prevent.

**Two populations, and only one of them is evidence.** A red run also exports XCTest's own
diagnostics: `UI Snapshot`, `Screen Recording`, `App UI hierarchy`, and one `Debug description`
per failed query. Those are useful for reading a failure and they are not captures of a surface.
`PhoneGlassTests.captureMarker` prefixes every attachment the suite took, so the split is declared
by the producer rather than guessed from the filename here. Diagnostics move to `diagnostics/`
under the same root, keeping them for the next reader without letting them into the evidence wall.

**Nothing is renamed until every check has passed.** The shared-image check used to run inside the
rename loop, so a failure left the directory half-renamed and the next reader could not tell an
opaque name from one this script had not reached yet. Now it plans, checks, then acts.
"""
import datetime
import hashlib
import json
import re
import pathlib
import sys


def main(directory: str) -> int:
    root = pathlib.Path(directory)
    # The export's own mtime, not "now": this is when the pictures were taken, and a stamp read off
    # the clock at naming time would drift from the run it claims to describe.
    stamp = datetime.datetime.fromtimestamp(
        root.stat().st_mtime, datetime.timezone.utc
    ).isoformat()
    manifest_path = root / "manifest.json"
    if not manifest_path.is_file():
        print(f"error: no manifest.json under {root} — nothing was exported", file=sys.stderr)
        return 1

    marker = "GLASS-CAPTURE-"
    lineage_marker = "GLASS-LINEAGE-"
    manifest = json.loads(manifest_path.read_text())
    lineage_by_name: dict[str, dict] = {}

    # Plan first. Nothing on disk moves until every check below has passed.
    captures, diagnostics = [], []
    for test in manifest:
        for attachment in test.get("attachments", []):
            exported = attachment.get("exportedFileName")
            suggested = attachment.get("suggestedHumanReadableName") or exported
            if not exported:
                continue
            source = root / exported
            # NOT `Path(suggested).stem`. The names this suite sets are dotted —
            # `SURF-018.ios.settings-paired-state` — and `.stem` reads the last dotted component as
            # a file extension and drops it, which collapsed `SURF-018.ios.settings-paired-state`
            # and `UNASSERTED.ios.after-tapping-pair-mac` onto `SURF-018.ios` and `UNASSERTED.ios`.
            # The shared-image check then fired on two captures that were genuinely different
            # pictures, correctly reporting a collision this script had itself created.
            stem = suggested
            if stem.lower().endswith(".png"):
                stem = stem[:-4]
            is_capture = marker in stem
            if not source.is_file():
                # A capture named and not written is a picture this lane claims and cannot show,
                # so it stops the step. A diagnostic in the same state is XCTest's business:
                # `export attachments` has been seen to list a .jpeg poster frame it did not
                # write, and letting that kill the naming step loses every real capture with it.
                if is_capture:
                    print(f"error: the manifest names capture {exported}, which is not on disk",
                          file=sys.stderr)
                    return 1
                print(f"  note: skipping {suggested} — listed in the manifest, not exported")
                continue
            if lineage_marker in stem:
                try:
                    record = json.loads(source.read_text())
                    lineage_by_name[record["name"]] = record
                except (ValueError, KeyError, OSError) as error:
                    print(f"  note: unreadable lineage record {suggested}: {error}")
                source.unlink()
                continue
            row = (source, stem, test.get("testIdentifier", "?"))
            (captures if is_capture else diagnostics).append(row)

    if not captures:
        print("error: zero captures exported — the lane photographed nothing.", file=sys.stderr)
        print(f"       {len(diagnostics)} diagnostic attachment(s) were present, so the export "
              "itself worked; no test called capture().", file=sys.stderr)
        return 1

    # A capture shared between two subjects means one of them was never photographed. Checked over
    # the captures alone: two of XCTest's diagnostics being identical is expected, not a finding.
    planned, seen_digests = [], {}
    for source, stem, test_id in captures:
        digest = hashlib.sha256(source.read_bytes()).hexdigest()
        name = stem.split(marker, 1)[1]
        # XCUITest injects `_0_<uuid>` into the middle of the name the test set — before its final
        # dot-component, so `SURF-012.ios.discover-populated` arrives as
        # `SURF-012.ios_0_<uuid>.discover-populated`. Cutting at the marker would drop the half
        # that says which surface state this is, so the segment is excised and the name rejoined.
        name = re.sub(r"_\d+_[0-9A-Fa-f-]{36}", "", name)
        destination = root / f"{name}{source.suffix or '.png'}"
        if digest in seen_digests:
            print(f"error: {destination.name} is byte-identical to {seen_digests[digest]}. "
                  "Two surfaces cannot share one capture — one of them was never photographed.",
                  file=sys.stderr)
            return 1
        seen_digests[digest] = destination.name
        planned.append((source, destination, digest, test_id))

    for source, destination, digest, test_id in planned:
        source.rename(destination)
        print(f"  {destination.name}  sha={digest[:16]}  from {test_id}")

    # Provenance, written from what the tests recorded at shutter time. Every field here came out
    # of the running app in the same instant as the pixels — the target especially, which is the
    # navigation bar's own identifier rather than a name this script assigned. A capture with no
    # lineage record is reported rather than given a plausible one.
    entries, unsourced = [], []
    for source, destination, digest, test_id in planned:
        name = destination.stem
        record = lineage_by_name.get(name)
        if record is None:
            unsourced.append(destination.name)
            continue
        entries.append({
            "path": f"evidence/shots/ios/{destination.name}",
            "subject": record.get("subject", ""),
            "target": record.get("target", ""),
            "targetReadback": record.get("targetReadback", ""),
            "channel": record.get("channel", ""),
            "derivedFrom": record.get("derivedFrom", test_id),
            "sha256": digest,
            "capturedAt": stamp,
            "conditions": (
                "iOS Simulator, lane-owned device; XCUIScreenshot carries no per-frame status, so "
                "attribution stands in its place — taken in-test after the surface's own assertion"
            ),
            "witnessed": False,
        })
    if unsourced:
        print(f"error: {len(unsourced)} capture(s) arrived with no lineage record: "
              f"{', '.join(unsourced)}", file=sys.stderr)
        return 1
    (root / "captures.json").write_text(json.dumps(entries, indent=1) + "\n")
    print(f"wrote provenance for {len(entries)} capture(s) to {root / 'captures.json'}")

    # And into the manifest the lineage gate actually reads.
    #
    # `capture-lineage.py` reads `evidence/shots/captures.json`, one level up — this directory's
    # own file is the lane's record and nothing downstream opens it. For six runs the two drifted:
    # the parent kept the sha256 of a capture taken days earlier while the bytes beside it were
    # fresh, and the gate reported six RECONSTRUCTED subjects, which is what it is for. Merging
    # here rather than reconciling later is the whole point — a manifest written after the fact
    # records what somebody believed, and these fields came out of the running app at shutter time.
    #
    # Entries are replaced by path, so a capture the lane no longer takes keeps its old row rather
    # than vanishing: the gate's unsourced pass is where a stale row should surface, not here.
    parent_path = root.parent / "captures.json"
    parent = json.loads(parent_path.read_text()) if parent_path.exists() else []
    fresh = {e["path"]: e for e in entries}
    merged = [fresh.pop(e["path"], e) for e in parent]
    merged.extend(fresh.values())
    parent_path.write_text(json.dumps(merged, indent=1) + "\n")
    print(f"merged {len(entries)} entry(ies) into {parent_path} ({len(merged)} total)")

    if diagnostics:
        diag_dir = root / "diagnostics"
        diag_dir.mkdir(exist_ok=True)
        for source, stem, _ in diagnostics:
            source.rename(diag_dir / f"{stem}{source.suffix}")
        print(f"moved {len(diagnostics)} XCTest diagnostic(s) to {diag_dir}")

    print(f"exported {len(planned)} on-glass captures to {root}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1] if len(sys.argv) > 1 else "."))
