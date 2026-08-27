#!/bin/bash
#
# G17 — FLOW-006: open a capability, read its document, move between the tabs.
#
# **What this closes.** M19 built the capability document panel and M23 measured it; M30 built
# `GET /servers/:name/document` and proved it with route tests, parity vectors and a two-router
# differential. Each half is sound and the JOIN was never a case. Every capture of that panel,
# M23's included, was a picture of `CapabilityDocumentFixture` — a JSON file in this repository.
# M30's own runner said so and took two frames of a real one; two frames taken once by the person
# who wrote the code is a look, not a case in a campaign that runs again. This is the case.
#
# **The subject is CONSTRUCTED, and that is stated rather than hidden — here, in the package's own
# read me, and in every row of `captures.json` this writes.** The route's package root is the
# server's declared `cwd` and nothing else, and **0 of the 21 upstreams in this machine's own
# `servers.json` declare one** — measured by M30 with `scripts/acceptance/m30-reach.mjs`, recorded
# at `planning/evidence/M30-reach.txt`, and filed as its own brief. So there is no real upstream on
# this Mac to point the panel at, and a server built here and labelled as built here is the honest
# subject. What is NOT constructed is the router, the route, the transport, the parser, the image
# resolver and the panel: those are the product, and the bytes cross a real HTTP connection.
#
# **It never takes the screen** — `planning/practices/UI_VERIFICATION.md` rule 1. Nothing is
# launched with `open`, the harness sets `.prohibited` and orders no window in, and each picture is
# rendered off the hosting view's own backing store rather than photographed off the display. The
# frontmost application is read before anything runs and asserted unchanged at the end.
#
#   ./planning/test-campaign/bin/g17-document-flow.sh          # run the flow
#   ./planning/test-campaign/bin/g17-document-flow.sh --arm    # run it, then plant four faults
#
# Exit codes: 0 clean · 1 ran and an assertion failed · 2 could not run · 3 the instrument could
# not measure (a MeasureDump built without MEASURE).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
OUT="${G17_OUT:-$ROOT/planning/test-campaign/evidence/g17-document}"
PORT="${G17_PORT:-8894}"
DIST="$ROOT/dist"
MEASURE_BIN="$ROOT/app/.build/debug/MeasureDump"
ASSERT="$ROOT/planning/test-campaign/bin/g17_document_assert.py"
ARM="no"
[ "${1:-}" = "--arm" ] && ARM="yes"

HOME_DIR="$(mktemp -d)"
ROUTER_PID=""
FRONT_SAMPLER=""

blocked() { echo "BLOCKED: $*" >&2; exit 2; }
fail() { echo "FAIL: $*" >&2; exit 1; }
cleanup() {
  [ -n "${FRONT_SAMPLER:-}" ] && kill "$FRONT_SAMPLER" 2>/dev/null || true
  [ -n "$ROUTER_PID" ] && kill "$ROUTER_PID" 2>/dev/null || true
  rm -rf "$HOME_DIR"
}
trap cleanup EXIT

# ---------------------------------------------------------------- rule 1, witnessed throughout
#
# **Before/after equality is the wrong assertion and it cost a red run to find out.** The first
# armed pass of this harness failed with "ghostty -> EgressMac": a third-party application took
# focus during the two minutes it ran, and a check comparing only the endpoints reported that as
# THIS run stealing the screen. The rule is that this run never takes the screen, which is a claim
# about the processes this harness starts — so a sampler watches the whole run and the assertion is
# over what it saw. `MeasureDump` sets `.prohibited` and `node` is headless, so neither can ever be
# frontmost; if either appears in the sample, that is the rule broken and it is caught wherever it
# happened rather than only at the end.
FRONT_LOG="$HOME_DIR/frontmost.log"
FRONT_BEFORE="$(osascript -e 'tell application "System Events" to get name of first process whose frontmost is true' 2>/dev/null || echo "unknown")"
echo "frontmost before: $FRONT_BEFORE"
( while :; do
    osascript -e 'tell application "System Events" to get name of first process whose frontmost is true' 2>/dev/null >> "$FRONT_LOG" || true
    sleep 1
  done ) &
FRONT_SAMPLER=$!

rm -rf "$OUT"; mkdir -p "$OUT"
[ -f "$DIST/index.js" ] || blocked "no built reference router at $DIST/index.js — run 'npx tsc -p tsconfig.json' first"
[ -x "$MEASURE_BIN" ] || blocked "no measurement harness at $MEASURE_BIN — build it with
    (cd $ROOT/app && MCP_ROUTER_MEASURE=1 swift build --product MeasureDump)"

# ---------------------------------------------------------------- the constructed packages
#
# Inside the scratch HOME rather than anywhere on the developer's disk: the route reads whatever a
# server's `cwd` names, and pointing it at a real checkout would put somebody's own files through a
# harness run.
PKG="$HOME_DIR/g17-capability"
BIG="$HOME_DIR/g17-oversize"
mkdir -p "$PKG/docs" "$BIG"

# **A wide, short band rather than a square.** The panel draws a figure `.resizable()` to the body's
# full width, so a square image is 736pt tall and pushes everything after it out of the frame — M30's
# capture lost all three of its refusal placeholders below the fold that way. 8:1 keeps the whole
# read me, its figure and its refused reference inside one picture, which is what lets one frame be
# the evidence for both.
/usr/bin/python3 - "$PKG/docs/figure.png" <<'PYEOF'
import struct, sys, zlib
w, h = 256, 32
raw = b''.join(b'\x00' + bytes([0x2f, 0x9c, 0x9c] * w) for _ in range(h))
def chunk(tag, data):
    c = tag + data
    return struct.pack('>I', len(data)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)
open(sys.argv[1], 'wb').write(
    b'\x89PNG\r\n\x1a\n'
    + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0))
    + chunk(b'IDAT', zlib.compress(raw))
    + chunk(b'IEND', b''))
PYEOF

cat > "$PKG/README.md" <<'MDEOF'
# g17-capability

A package constructed by planning/test-campaign/bin/g17-document-flow.sh so the capability document
panel has a real document to draw. It is not a real upstream: 0 of the 21 servers in this machine's
own servers.json declare the cwd this route reads.

![the package's own figure](docs/figure.png)

The reference below climbs out of the package, so the router refuses it and the panel draws its own
sentence in place of the picture rather than dropping the figure silently.

![a reference climbing out of the package](../../../../etc/passwd)
MDEOF

cat > "$PKG/CHANGELOG.md" <<'MDEOF'
# Changelog

## 1.0.0

Constructed for G17's flow. This tab exists so the reader has a second document to move to, which
is the step of the flow that the campaign had no case for.
MDEOF

cat > "$PKG/CAPABILITIES.md" <<'MDEOF'
# Capabilities

One tool, `read`, which returns the document it was asked for. The third tab, so all three keys the
route serves are on the wire in one response and each one has a frame of its own.
MDEOF

# A read me over the 512 KB transport cap for one document, so the too-large refusal is a state the
# route actually produces rather than a string in an enum.
/usr/bin/python3 -c "open('$BIG/README.md','w').write('# oversize\n\n' + 'x' * 600000)"

cat > "$HOME_DIR/servers.json" <<JSONEOF
{
  "port": $PORT,
  "mcpServers": {
    "g17-capability": { "command": "/bin/echo", "cwd": "$PKG" },
    "g17-no-package": { "command": "/bin/echo" },
    "g17-oversize":   { "command": "/bin/echo", "cwd": "$BIG" }
  }
}
JSONEOF

# ---------------------------------------------------------------- the router
#
# `MCP_ROUTER_HOME` is the only variable that moves the router's whole state, and the guard below
# refuses to continue unless the scratch home actually took: a harness that silently falls back to
# the developer's real ~/.claude/mcp-router on a typo is worse than one that fails.
MCP_ROUTER_HOME="$HOME_DIR" node "$DIST/index.js" serve --port "$PORT" >"$HOME_DIR/router.log" 2>&1 &
ROUTER_PID=$!
for _ in $(seq 1 60); do
  curl -fsS -m 2 "http://127.0.0.1:$PORT/servers" -o "$HOME_DIR/probe.json" 2>/dev/null && break
  sleep 0.2
done
[ -s "$HOME_DIR/probe.json" ] || { cat "$HOME_DIR/router.log" >&2; blocked "the scratch router never answered on $PORT"; }
grep -q 'g17-capability' "$HOME_DIR/probe.json" || blocked "the scratch router is not reading the scratch config"
[ -f "$HOME_DIR/control.token" ] || blocked "no control token under the scratch home — MCP_ROUTER_HOME did not take"
echo "router up on $PORT (reference implementation, node $DIST/index.js), scratch home $HOME_DIR"

# ---------------------------------------------------------------- FLOW-006.01 — the wire (SURF-026)
curl -fsS -m 10 "http://127.0.0.1:$PORT/servers/g17-capability/document" -o "$OUT/wire-served.json" \
  || fail "the document route refused the constructed server"
curl -sS -m 10 "http://127.0.0.1:$PORT/servers/g17-no-package/document" -o "$OUT/wire-nopackage.json" || true
curl -sS -m 10 "http://127.0.0.1:$PORT/servers/g17-oversize/document"   -o "$OUT/wire-toolarge.json" || true

# ---------------------------------------------------------------- FLOW-006.02–.04 and the refusals
#
# One render per frame, each naming the server it asked for and the tab it drew. The manifest row is
# written from the SAME invocation, so the picture and its provenance cannot drift apart.
: > "$OUT/manifest.tsv"
render() {
  local frame="$1" server="$2" tab="$3" height="$4" subject="$5" step="$6" status=0
  MCP_ROUTER_HOME="$HOME_DIR" "$MEASURE_BIN" \
    --surface readme --state ideal --appearance dark \
    --width 900 --height "$height" --settle 2.0 \
    --document-from "http://127.0.0.1:$PORT" --document-server "$server" --document-tab "$tab" \
    --png "$OUT/$frame.png" --out "$OUT/$frame.dump.json" >>"$OUT/renders.txt" 2>&1 || status=$?
  case $status in
    0) ;;
    3) blocked "MeasureDump exited 3 (inconclusive): it is present but was built without MEASURE, so
              the in-view harness is not compiled in and it measured nothing. Any plain 'swift build'
              in this worktree leaves it that way. Rebuild with:
                  (cd $ROOT/app && MCP_ROUTER_MEASURE=1 swift build --product MeasureDump)
              Nothing about $frame has been measured either way." ;;
    *) fail "could not render $frame (MeasureDump exited $status)" ;;
  esac
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$frame" "$server" "$tab" "$subject" "$step" "${7:-}" "${8:-}" >> "$OUT/manifest.tsv"
}

# The last two arguments are the frame's own witness: a string the PANEL draws, and the role it
# draws it in. That is what ties a picture to the package it is of independently of its filename.
# `refusal.toolarge` has none, and the empty pair is the honest record of that — its refusal names
# the file and the cap and never the capability, so the frame cannot say what it refuses. DEF-058.
render readme.served        g17-capability readMe       820 SURF-025 FLOW-006.02 g17-capability titlebar
render changelog.served     g17-capability changelog    820 SURF-025 FLOW-006.03 g17-capability titlebar
render capabilities.served  g17-capability capabilities 820 SURF-025 FLOW-006.04 g17-capability titlebar
render refusal.nopackage    g17-no-package readMe       520 SURF-025 FLOW-006.02 g17-no-package state-title
render refusal.toolarge     g17-oversize   readMe       520 SURF-025 FLOW-006.02

# The capture manifest, written from the render log rather than from the filenames. Each row carries
# what the router was asked for, and the assertion pass checks that against what the panel drew.
/usr/bin/python3 - "$OUT" "$PORT" <<'PYEOF'
import hashlib, json, os, sys, time
out, port = sys.argv[1], sys.argv[2]
rows = []
for line in open(os.path.join(out, "manifest.tsv")):
    parts = (line.rstrip("\n").split("\t") + ["", ""])[:7]
    frame, server, tab, subject, step, marker, marker_role = parts
    png = os.path.join(out, frame + ".png")
    rows.append({
        "frame": frame,
        "path": "evidence/g17-document/%s.png" % frame,
        "subject": subject,
        "step": step,
        "target": "app://mac/servers/%s/document" % server,
        "documentServer": server,
        "documentTab": tab,
        "marker": marker or None,
        "markerRole": marker_role or None,
        "channel": ("NSHostingView cacheDisplay(in:to:) off the view's own backing store — no window "
                    "ordered in, activation policy .prohibited; not a screen photograph"),
        "servedBy": "http://127.0.0.1:%s/servers/%s/document (reference router, node dist/index.js)"
                    % (port, server),
        "packageProvenance": "CONSTRUCTED by planning/test-campaign/bin/g17-document-flow.sh — 0 of "
                             "the 21 upstreams on this machine declare a package directory (M30, "
                             "planning/evidence/M30-reach.txt)",
        "sha256": hashlib.sha256(open(png, "rb").read()).hexdigest(),
        "bytes": os.path.getsize(png),
        "capturedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "derivedFrom": None,
    })
json.dump(rows, open(os.path.join(out, "captures.json"), "w"), indent=1, sort_keys=True)
print("wrote %d capture rows" % len(rows))
PYEOF

# ---------------------------------------------------------------- what landed
echo "--- assertions"
/usr/bin/python3 "$ASSERT" "$OUT" || fail "the flow's assertions did not pass"

# ---------------------------------------------------------------- the controls
#
# Every check above is a claim that something would be noticed. Arming is where that is watched
# rather than asserted: one input is mutated, the frame is re-rendered from the real router, and the
# named check has to be the one that goes red. Then the input is put back and the artifact is
# compared by sha256 against what it was before the fault.
if [ "$ARM" = "yes" ]; then
  echo "--- controls"
  mkdir -p "$OUT/armed"
  cp "$PKG/docs/figure.png" "$HOME_DIR/figure.png.orig"
  BEFORE_README="$(shasum -a 256 "$OUT/readme.served.png" | cut -d' ' -f1)"
  BEFORE_CL="$(shasum -a 256 "$OUT/changelog.served.png" | cut -d' ' -f1)"
  BEFORE_CAPS="$(shasum -a 256 "$OUT/capabilities.served.png" | cut -d' ' -f1)"
  BEFORE_LARGE="$(shasum -a 256 "$OUT/refusal.toolarge.png" | cut -d' ' -f1)"

  arm() {  # arm <name> <check-id> <what was planted>
    local name="$1" check="$2" what="$3"
    if /usr/bin/python3 "$ASSERT" "$OUT" --expect-fail "$check" > "$OUT/armed/$name.txt" 2>&1; then
      echo "  ARMED  $check — $what"
    else
      cat "$OUT/armed/$name.txt" >&2
      fail "control $check did NOT bite under: $what"
    fi
  }

  restore() {  # restore <frame> <expected sha> <label>
    local frame="$1" expected="$2" now
    now="$(shasum -a 256 "$OUT/$frame.png" | cut -d' ' -f1)"
    if [ "$now" = "$expected" ]; then
      echo "  RESTORED $frame byte-identical — sha256 $now"
    else
      fail "restoring $frame did not reproduce it: $expected -> $now"
    fi
  }

  # A — the figure's pixels. Replace the PNG's bytes with something NSImage cannot decode; the
  #     route still serves it as image/png, so what changes is only whether it draws.
  printf 'not a picture, and not eight bytes of A either\n' > "$PKG/docs/figure.png"
  render readme.served g17-capability readMe 820 SURF-025 FLOW-006.02 g17-capability titlebar
  arm figure G17-P4 "the served figure's bytes replaced with something that cannot decode"
  cp "$HOME_DIR/figure.png.orig" "$PKG/docs/figure.png"
  render readme.served g17-capability readMe 820 SURF-025 FLOW-006.02 g17-capability titlebar
  restore readme.served "$BEFORE_README" "the served read me"

  # B — the subject. Point the same frame at a different server; the filename does not change and
  #     the picture does, which is exactly the failure the lineage check exists for.
  render readme.served g17-no-package readMe 820 SURF-025 FLOW-006.02 g17-capability titlebar
  arm subject G17-P1 "the read me frame rendered against g17-no-package under its own filename"
  render readme.served g17-capability readMe 820 SURF-025 FLOW-006.02 g17-capability titlebar
  restore readme.served "$BEFORE_README" "the served read me"

  # C — the tabs. Draw the read me three times; if the flow's tab step could pass on that, moving
  #     between tabs was never being measured.
  render changelog.served    g17-capability readMe 820 SURF-025 FLOW-006.03 g17-capability titlebar
  render capabilities.served g17-capability readMe 820 SURF-025 FLOW-006.04 g17-capability titlebar
  arm tabs G17-P8 "the changelog and capabilities frames both rendered on the read me tab"
  render changelog.served    g17-capability changelog    820 SURF-025 FLOW-006.03 g17-capability titlebar
  render capabilities.served g17-capability capabilities 820 SURF-025 FLOW-006.04 g17-capability titlebar
  restore changelog.served "$BEFORE_CL" "the changelog"
  restore capabilities.served "$BEFORE_CAPS" "the capability list"

  # D — the refusals. Make two of the three the same refusal; distinguishable has to mean measured.
  render refusal.toolarge g17-no-package readMe 520 SURF-025 FLOW-006.02
  arm refusals G17-R3 "the too-large frame rendered against the no-package server, so two refusals
                       draw the same words"
  render refusal.toolarge g17-oversize readMe 520 SURF-025 FLOW-006.02
  restore refusal.toolarge "$BEFORE_LARGE" "the too-large refusal"

  echo "--- re-assert after restoration"
  /usr/bin/python3 - "$OUT" "$PORT" <<'PYEOF'
import hashlib, json, os, sys
out = sys.argv[1]
rows = json.load(open(os.path.join(out, "captures.json")))
for row in rows:
    png = os.path.join(out, row["frame"] + ".png")
    row["sha256"] = hashlib.sha256(open(png, "rb").read()).hexdigest()
    row["bytes"] = os.path.getsize(png)
json.dump(rows, open(os.path.join(out, "captures.json"), "w"), indent=1, sort_keys=True)
PYEOF
  /usr/bin/python3 "$ASSERT" "$OUT" || fail "the flow did not come back green after the controls"
fi

# ---------------------------------------------------------------- rule 1, asserted
kill "$FRONT_SAMPLER" 2>/dev/null || true
FRONT_SAMPLER=""
FRONT_AFTER="$(osascript -e 'tell application "System Events" to get name of first process whose frontmost is true' 2>/dev/null || echo "unknown")"
SAMPLES="$(wc -l < "$FRONT_LOG" | tr -d ' ')"
cp "$FRONT_LOG" "$OUT/frontmost.txt"
echo "frontmost after:  $FRONT_AFTER ($SAMPLES samples over the run)"
[ "$SAMPLES" -gt 0 ] || blocked "the frontmost sampler recorded nothing, so rule 1 was not witnessed"
if grep -qE '^(MeasureDump|node|MCPRouter)$' "$FRONT_LOG"; then
  fail "this run took the screen — $(grep -E '^(MeasureDump|node|MCPRouter)$' "$FRONT_LOG" | sort -u | tr '\n' ' ') was frontmost"
fi
echo "  ok — neither MeasureDump nor the router was frontmost in any of the $SAMPLES samples"
if [ "$FRONT_BEFORE" != "$FRONT_AFTER" ]; then
  echo "  note — the frontmost application changed ($FRONT_BEFORE -> $FRONT_AFTER) and it was not this"
  echo "         run: no process this harness starts appears anywhere in the sample. Recorded at"
  echo "         $OUT/frontmost.txt rather than waived."
fi
echo "g17-document-flow: ok"
