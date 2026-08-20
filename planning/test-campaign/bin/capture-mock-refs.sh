#!/bin/bash
# The design-of-record half of every witness pair, with the same provenance
# discipline the build half now carries.
#
# The previous reference set had the identical defect the build set did:
# mock/SURF-001.png and mock/SURF-003.png were byte-identical, because the
# prototype's initial pane is `activity` and the shell reference was captured
# without deep-linking anywhere. A witness comparing SURF-001 would have been
# handed the Activity board as the design of record for the shell.
#
# Every capture here deep-links (`?pane=…&sheet=…&only=…`), reads S back out of
# the page after load, and records that readback as the target. A reference whose
# readback disagrees with the link is written down as such rather than filed.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
CAMPAIGN="$ROOT/planning/test-campaign"
MOCK="$ROOT/design/mocks/prototype.html"
OUT="$CAMPAIGN/evidence/shots/mock"
NDJSON="$OUT/.captures.ndjson"
mkdir -p "$OUT"
: > "$NDJSON"
[ -f "$MOCK" ] || { echo "no design of record at $MOCK"; exit 2; }

shoot() {
  local sid="$1" query="$2" expect="$3" field="$4" shares="${5:-}"
  local url="file://$MOCK?$query"
  local dest="$OUT/$sid.png"
  local state
  # With --screenshot, obscura wraps the eval result in an envelope on its own
  # line and prints "Screenshot written" after it, so the last line is the wrong
  # one. Pull the envelope by name and unwrap the inner string.
  state="$(obscura fetch "$url" \
      --eval "(()=>JSON.stringify({pane:S.pane,sheet:S.sheet,popover:S.popover,tab:S.tab||null,pairing:S.pairing||null}))()" \
      --screenshot "$dest" 2>/dev/null \
    | grep -m1 '"evaluation"' \
    | python3 -c 'import sys,json; print(json.loads(sys.stdin.read()).get("evaluation") or "")')"
  SID="$sid" DEST="$dest" URL="$url" STATE="$state" EXPECT="$expect" \
  SHARES="$shares" FIELD="$field" ND="$NDJSON" python3 - <<'PY'
import hashlib, json, os, datetime, pathlib
dest = pathlib.Path(os.environ["DEST"])
if not dest.exists():
    raise SystemExit(f"{os.environ['SID']}: obscura wrote no screenshot")
raw = dest.read_bytes()
try:
    state = json.loads(os.environ["STATE"])
except Exception:
    raise SystemExit(f"{os.environ['SID']}: no state readback — the page did not "
                     f"evaluate, so nothing proves what this picture shows")
# Which field carries the identity depends on the surface. S.tab defaults to
# "discover" for the phone and is present on every load, so preferring it
# reported "discover" for eight Mac boards whose pictures were all different —
# a readback that cannot vary with the subject is not a readback.
field = os.environ["FIELD"]
if field == "sheet":
    landed = state.get("sheet") or "none"
elif field == "popover":
    landed = "popover" if state.get("popover") else "none"
else:
    landed = state.get(field) or "none"
expect = os.environ["EXPECT"]
entry = {
    "path": f"evidence/shots/mock/{dest.name}",
    "subject": os.environ["SID"],
    "target": os.environ["URL"],
    "channel": "obscura-0.2.0 fetch --screenshot (file://, 1280x720 viewport, dpr 1)",
    "derivedFrom": None,
    "sha256": hashlib.sha256(raw).hexdigest(),
    "capturedAt": datetime.datetime.now(datetime.timezone.utc)
                  .replace(microsecond=0).isoformat().replace("+00:00", "Z"),
    "conditions": {"stateReadback": state, "expected": expect, "identityField": field, "role": "design-of-record",
                   "viewport": [1280, 720], "dpr": 1,
                   "note": ("obscura fetch --screenshot captures the viewport only; "
                            "the mock window is 915px tall, so roughly 200px below "
                            "the fold is absent from every reference")},
    "witnessed": "prototype deep-link; S read out of the page after load",
}
if os.environ.get("SHARES"):
    entry["sharesWith"] = [s for s in os.environ["SHARES"].split(",") if s]
if landed != expect:
    entry["mismatch"] = (f"asked for {expect!r}, page settled on {landed!r} — this "
                         f"reference is not the surface it is filed under")
open(os.environ["ND"], "a").write(json.dumps(entry) + "\n")
flag = "  MISMATCH" if landed != expect else ""
print(f"  {os.environ['SID']:9} landed={str(landed):12} sha={entry['sha256'][:12]} "
      f"bytes={len(raw)}{flag}")
PY
}

# The three iOS surfaces have their own mock files. Driving them through
# prototype.html's `?pairing=scan` reported a state change that the render did
# not make — the pairing reference came back byte-identical to Discover — so
# they are shot from the file that actually draws them, identified by its title.
shoot_file() {
  local sid="$1" file="$2" expect="$3"
  local url="file://$ROOT/design/mocks/$file"
  local dest="$OUT/$sid.png"
  local title
  title="$(obscura fetch "$url" --eval "(()=>document.title)()" --screenshot "$dest" 2>/dev/null \
    | grep -m1 '"evaluation"' \
    | python3 -c 'import sys,json; print(json.loads(sys.stdin.read()).get("evaluation") or "")')"
  SID="$sid" DEST="$dest" URL="$url" TITLE="$title" EXPECT="$expect" ND="$NDJSON" python3 - <<'PY2'
import hashlib, json, os, datetime, pathlib
dest = pathlib.Path(os.environ["DEST"])
raw = dest.read_bytes()
title = os.environ["TITLE"].strip()
entry = {"path": f"evidence/shots/mock/{dest.name}", "subject": os.environ["SID"],
         "target": os.environ["URL"],
         "channel": "obscura-0.2.0 fetch --screenshot (file://, 1280x720 viewport, dpr 1)",
         "derivedFrom": None, "sha256": hashlib.sha256(raw).hexdigest(),
         "capturedAt": datetime.datetime.now(datetime.timezone.utc)
                       .replace(microsecond=0).isoformat().replace("+00:00", "Z"),
         "conditions": {"titleReadback": title, "expected": os.environ["EXPECT"],
                        "identityField": "document.title", "role": "design-of-record",
                        "viewport": [1280, 720], "dpr": 1},
         "witnessed": "dedicated mock file; document.title read out of the page after load"}
if os.environ["EXPECT"].lower() not in title.lower():
    entry["mismatch"] = (f"asked for {os.environ['EXPECT']!r}, page titled {title!r} — this "
                         f"reference is not the surface it is filed under")
open(os.environ["ND"], "a").write(json.dumps(entry) + "\n")
flag = "  MISMATCH" if entry.get("mismatch") else ""
print(f"  {os.environ['SID']:9} title={title[:34]:34} sha={entry['sha256'][:12]} bytes={len(raw)}{flag}")
PY2
}

shoot SURF-001 "pane=servers&only=mac"            servers  pane    SURF-002
shoot SURF-002 "pane=servers&only=mac"            servers  pane    SURF-001
shoot SURF-003 "pane=activity&only=mac"           activity pane
shoot SURF-004 "pane=skills&only=mac"             skills   pane
shoot SURF-005 "pane=discover&only=mac"           discover pane
shoot SURF-006 "pane=evals&only=mac"              evals    pane
shoot SURF-007 "pane=cleanup&only=mac"            cleanup  pane
shoot SURF-008 "pane=inbox&only=mac"              inbox    pane
shoot SURF-009 "pane=inbox&popover=1&only=mac"    popover  popover
shoot SURF-010 "pane=inbox&sheet=pair&only=mac"   pair     sheet
shoot SURF-011 "pane=settings&only=mac"           settings pane
shoot_file SURF-012 i2-phone-discover.html Discover
shoot_file SURF-013 i3-phone-triage.html Triage
shoot_file SURF-014 i1-phone-pairing.html pairing

python3 - <<PY
import json, pathlib
src = pathlib.Path("$NDJSON")
rows = [json.loads(l) for l in src.read_text().splitlines() if l.strip()]
pathlib.Path("$OUT/captures.json").write_text(json.dumps(rows, indent=2) + "\n")
bad = [r for r in rows if r.get("mismatch")]
print(f"mock manifest: {len(rows)} reference(s), {len(bad)} filed under a surface they do not show")
for r in bad:
    print(f"  {r['subject']}: {r['mismatch']}")
src.unlink()
PY
