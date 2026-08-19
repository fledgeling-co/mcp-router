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
"""
import hashlib
import json
import pathlib
import sys


def main(directory: str) -> int:
    root = pathlib.Path(directory)
    manifest_path = root / "manifest.json"
    if not manifest_path.is_file():
        print(f"error: no manifest.json under {root} — nothing was exported", file=sys.stderr)
        return 1

    manifest = json.loads(manifest_path.read_text())
    renamed, seen_digests = 0, {}
    for test in manifest:
        for attachment in test.get("attachments", []):
            exported = attachment.get("exportedFileName")
            suggested = attachment.get("suggestedHumanReadableName") or exported
            if not exported:
                continue
            source = root / exported
            if not source.is_file():
                print(f"error: manifest names {exported}, which is not on disk", file=sys.stderr)
                return 1
            digest = hashlib.sha256(source.read_bytes()).hexdigest()
            stem = pathlib.Path(suggested).stem
            destination = root / f"{stem}{source.suffix or '.png'}"
            source.rename(destination)
            renamed += 1
            print(f"  {destination.name}  sha={digest[:16]}  from {test.get('testIdentifier', '?')}")
            if digest in seen_digests:
                print(
                    f"error: {destination.name} is byte-identical to {seen_digests[digest]}. "
                    "Two surfaces cannot share one capture — one of them was never photographed.",
                    file=sys.stderr,
                )
                return 1
            seen_digests[digest] = destination.name

    print(f"exported {renamed} on-glass captures to {root}")
    if renamed == 0:
        print("error: zero captures exported — the lane photographed nothing", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1] if len(sys.argv) > 1 else "."))
