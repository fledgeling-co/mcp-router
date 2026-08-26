#!/bin/bash
#
# M30's end-to-end look: a real package's own documents, served by a real router, drawn by the real
# panel — and the refusal frame every upstream on this machine actually lands in.
#
# **Why this exists.** M30's completion record proved the route with unit tests, mapping tests, three
# vector files and a two-router wire differential, and then said the panel's rendering was "M23's
# measurement and unchanged". That is true about pixels and silent about reachability. M23 measured
# `CapabilityDocumentSheet` driven by `FixtureCapabilityDocumentSource` — a JSON file in this
# repository — so at the point the item was called done, nobody had seen the panel draw a document
# a router served. This takes that look.
#
# **The subject is constructed, and that is stated rather than hidden.** The package root is the
# server's declared `cwd` and nothing else, and 0 of the 21 upstreams in the developer's own
# `servers.json` declare one — measured, not assumed. `scripts/acceptance/m30-reach.mjs` is the
# instrument and `planning/evidence/M30-reach.txt` is its run. So there is no real upstream on this machine to point at, and the honest move is a server
# built here, labelled as built here, rather than an argument that the pixels were measured
# somewhere else.
#
# **It never takes the screen.** `UI_VERIFICATION.md` rule 1. Nothing is launched with `open`, the
# measurement harness sets `.prohibited` and orders no window in, and the picture is rendered off the
# hosting view's own backing store rather than photographed off the display. The frontmost
# application is recorded before anything runs and asserted unchanged at the end: if this ever steals
# focus, it fails itself.
#
# Exit codes follow the house rule: 2 means it could not run, 1 means it ran and an assertion failed.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="${M30_LOOK_OUT:-$ROOT/planning/evidence/M30-look}"
PORT="${M30_LOOK_PORT:-8893}"
HOME_DIR="$(mktemp -d)"
DIST="$ROOT/dist"
ROUTER_PID=""

blocked() { echo "BLOCKED: $*" >&2; exit 2; }
fail() { echo "FAIL: $*" >&2; exit 1; }
cleanup() {
  [ -n "$ROUTER_PID" ] && kill "$ROUTER_PID" 2>/dev/null || true
  rm -rf "$HOME_DIR"
}
trap cleanup EXIT

# ---------------------------------------------------------------- rule 1, armed before anything
FRONT_BEFORE="$(osascript -e 'tell application "System Events" to get name of first process whose frontmost is true' 2>/dev/null || echo "unknown")"
echo "frontmost before: $FRONT_BEFORE"

mkdir -p "$OUT"

[ -f "$DIST/index.js" ] || blocked "no built reference router at $DIST/index.js — run 'npm run build' first"
MEASURE_BIN="$ROOT/app/.build/debug/MeasureDump"
[ -x "$MEASURE_BIN" ] || blocked "no measurement harness at $MEASURE_BIN — build with MCP_ROUTER_MEASURE=1"

# ---------------------------------------------------------------- the constructed package
#
# Inside the scratch HOME rather than anywhere on the developer's disk: the route reads whatever the
# server's `cwd` names, and pointing it at a real checkout would put somebody's own files through a
# harness run.
#
# The read me names four references on purpose — one that resolves, one that climbs out, one
# absolute, one remote — so the single frame this renders carries the refusal placeholders beside the
# figure that arrives, which is the panel state the route can actually produce.
PKG="$HOME_DIR/m30-look-package"
mkdir -p "$PKG/docs"

# A real 8x8 PNG rather than eight bytes of 'A'. The panel decodes what arrives and draws a refusal
# for what it cannot, so a fake body would render the placeholder and look exactly like a failure of
# the route it is here to demonstrate.
python3 - "$PKG/docs/figure.png" <<'PYEOF'
import base64, sys
# 8x8 solid-teal PNG, generated here so the fixture carries no opaque blob.
import struct, zlib
w = h = 8
raw = b''.join(b'\x00' + bytes([0x2f, 0x9c, 0x9c] * w) for _ in range(h))
def chunk(tag, data):
    c = tag + data
    return struct.pack('>I', len(data)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)
png = (b'\x89PNG\r\n\x1a\n'
       + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0))
       + chunk(b'IDAT', zlib.compress(raw))
       + chunk(b'IEND', b''))
open(sys.argv[1], 'wb').write(png)
PYEOF

cat > "$PKG/README.md" <<'MDEOF'
# m30-look

A package built by `scripts/acceptance/m30-document-look.sh` so the capability panel has a real
document to draw. It is **not** a real upstream: 0 of the 21 servers in this machine's own
`servers.json` declare the `cwd` this route reads.

![a figure inside the package](docs/figure.png)

The three references below are each refused by the router, and the panel draws its placeholder
sentence for each rather than dropping the figure.

![climbing out](../../../../etc/passwd)

![absolute](/etc/passwd)

![remote](https://example.invalid/badge.png)
MDEOF

cat > "$PKG/CHANGELOG.md" <<'MDEOF'
# Changelog

## 1.0.0

The first one. This tab exists so the panel draws two tabs rather than one.
MDEOF

cat > "$PKG/CAPABILITIES.md" <<'MDEOF'
# Capabilities

One tool, `look`, which returns what it was given. The third tab, so all three keys the route
serves are on the wire in one response.
MDEOF

# ---------------------------------------------------------------- the router
#
# Two servers: one declaring the package, one declaring nothing. The second is what all 21 real
# upstreams look like to this route, so its frame is a picture of today rather than of a fixture.
cat > "$HOME_DIR/servers.json" <<JSONEOF
{
  "port": $PORT,
  "mcpServers": {
    "m30-look": { "command": "/bin/echo", "cwd": "$PKG" },
    "m30-no-cwd": { "command": "/bin/echo" }
  }
}
JSONEOF

# MCP_ROUTER_HOME is the only variable that moves the router's whole state. The guard below refuses
# to continue unless the scratch home actually took effect — a harness that falls back to the
# developer's real `~/.claude/mcp-router` on a typo is worse than one that fails.
MCP_ROUTER_HOME="$HOME_DIR" node "$DIST/index.js" serve --port "$PORT" >"$HOME_DIR/router.log" 2>&1 &
ROUTER_PID=$!

for _ in $(seq 1 50); do
  curl -fsS -m 2 "http://127.0.0.1:$PORT/servers" -o "$HOME_DIR/servers-probe.json" 2>/dev/null && break
  sleep 0.2
done
[ -s "$HOME_DIR/servers-probe.json" ] || { cat "$HOME_DIR/router.log" >&2; blocked "the scratch router never answered on $PORT"; }
grep -q 'm30-look' "$HOME_DIR/servers-probe.json" || blocked "the scratch router is not reading the scratch config"
[ -f "$HOME_DIR/control.token" ] || blocked "no control token under the scratch home — MCP_ROUTER_HOME did not take"

# ---------------------------------------------------------------- the wire, before the panel
curl -fsS -m 10 "http://127.0.0.1:$PORT/servers/m30-look/document" -o "$OUT/wire-served.json" \
  || fail "the route refused the constructed server"
curl -sS -m 10 "http://127.0.0.1:$PORT/servers/m30-no-cwd/document" -o "$OUT/wire-refused.json" || true

python3 - "$OUT/wire-served.json" "$OUT/wire-refused.json" "$PKG" <<'PYEOF' || exit 1
import json, sys
served, refused, root = sys.argv[1], sys.argv[2], sys.argv[3]
d = json.load(open(served))
body = open(served, encoding='utf-8').read()
ok = True
def check(cond, msg):
    global ok
    print(("  ok — " if cond else "  FAIL — ") + msg)
    ok = ok and cond
check(sorted(d['documents']) == ['capabilities', 'changelog', 'readMe'],
      "all three documents on the wire: %s" % sorted(d['documents']))
check(len(d['images']) == 1 and d['images'][0]['media'] == 'image/png',
      "one image arrived as image/png")
check(sorted(r['reason'] for r in d['refusedImages']) == ['absolutePath', 'escapesPackage', 'remote'],
      "three references refused: %s" % sorted(r['reason'] for r in d['refusedImages']))
check(root not in body, "the package root appears nowhere in the response body")
r = json.load(open(refused))
check(r.get('reason') == 'noPackageDirectory',
      "a server with no cwd refuses noPackageDirectory (what all 21 real upstreams get)")
sys.exit(0 if ok else 1)
PYEOF

# ---------------------------------------------------------------- the panel
#
# One launch, one pass. `.prohibited`, no window ordered in, the picture taken off the view's own
# backing store.
# **A present binary built without MEASURE is a blocked run, not a red one.** The check at the top
# of this file catches a *missing* `MeasureDump`; this is the same condition one step further in.
# Any plain `swift build` against this worktree — `make build`, `make test`, an editor's build on
# save — overwrites `app/.build/debug/MeasureDump` with a non-MEASURE binary: executable, correct,
# and unable to measure anything. (`app/.build` is per-worktree rather than shared: the MeasureDump
# under `.worktrees/M30` and the one under `.worktrees/M32` were measured on 2026-08-27 as separate
# inodes, so the cause is a build in THIS worktree rather than a neighbouring one.) It says so
# itself and exits **3**,
# and folding that into `fail` would report the product broken when only the instrument could not
# run. Observed on 2026-08-27: this harness exited 1 with "the harness could not render the served
# document" over a MeasureDump that was reporting 3/inconclusive exactly as designed.
#
# So exit 3 from the harness becomes exit 2 here — blocked, with the build to run — and every other
# non-zero stays a failure.
render() {
  local server="$1" name="$2" what="$3" status=0
  MCP_ROUTER_HOME="$HOME_DIR" "$MEASURE_BIN" \
    --surface readme --state ideal --appearance dark \
    --width 900 --height 700 --settle 2.0 \
    --document-from "http://127.0.0.1:$PORT" --document-server "$server" \
    --png "$OUT/$name.png" --out "$OUT/$name.dump.json" || status=$?
  case $status in
    0) return 0 ;;
    3) blocked "the measurement harness at $MEASURE_BIN exited 3 (inconclusive): it is present but was
              built without MEASURE, so the in-view harness is not compiled in and it measured
              nothing. Any plain \"swift build\" in this worktree (make build, make test) leaves it
              in this state. Rebuild it with:
                  (cd \"$ROOT/app\" && MCP_ROUTER_MEASURE=1 swift build --product MeasureDump)
              then run this again. Nothing about $what has been measured either way." ;;
    *) fail "the harness could not render $what (MeasureDump exited $status)" ;;
  esac
}

render m30-look   readme.served  "the served document"
render m30-no-cwd readme.refused "the refusal"

# ---------------------------------------------------------------- what landed on the screen
python3 - "$OUT/readme.served.dump.json" "$OUT/readme.refused.dump.json" <<'PYEOF' || exit 1
import json, sys

ok = True
def check(cond, msg):
    global ok
    print(("  ok - " if cond else "  FAIL - ") + msg)
    ok = ok and cond

def nodes(path):
    out = []
    def walk(n):
        out.append(n)
        for c in n.get('children') or []:
            walk(c)
    walk(json.load(open(path))['root'])
    return out

served, refused = nodes(sys.argv[1]), nodes(sys.argv[2])
def role(ns, r):
    return [n.get('text', '') for n in ns if n.get('role') == r]
def blob(ns):
    return ' '.join(n.get('text', '') for n in ns)

# The subject, proven rather than assumed. M19's fixture capability is `trawl`; if this frame were
# the fixture - which is what every dump of this panel has been until now - its name would be in it.
check('m30-look' in role(served, 'titlebar'),
      "the served frame's titlebar names the served package: %s" % role(served, 'titlebar'))
check('trawl' not in blob(served),
      "M19's fixture capability 'trawl' appears nowhere - this is not the fixture")

# The package's own bytes reached the renderer.
check('m30-look' in role(served, 'heading'),
      "the read me's own H1 is drawn: %s" % role(served, 'heading'))
check(any("0 of the 21 servers" in t for t in role(served, 'sentence')),
      "the package's own prose is drawn")
check(role(served, 'tab') == ['Read me', 'Changelog', 'Capabilities'],
      "all three tabs are drawn: %s" % role(served, 'tab'))

# One figure arrived and three were refused, and the panel drew a card for each rather than
# dropping the ones it could not have.
check(len(role(served, 'card')) == 4,
      "four image cards drawn - one resolved, three placeholders: %s" % role(served, 'card'))

# The refusal frame: what every one of the 21 real upstreams produces today.
check(any('has no package to read' in t for t in role(refused, 'state-title')),
      "the refusal frame draws the noPackageDirectory state: %s" % role(refused, 'state-title'))
check(len(role(refused, 'card')) == 0, "the refusal frame draws no figures")
check(blob(served) != blob(refused), "the two frames are not the same drawing")

sys.exit(0 if ok else 1)
PYEOF

for f in readme.served.png readme.refused.png; do
  [ -s "$OUT/$f" ] || fail "no picture at $OUT/$f"
  echo "  ok — $f $(/usr/bin/stat -f%z "$OUT/$f") bytes"
done

# ---------------------------------------------------------------- rule 1, asserted
FRONT_AFTER="$(osascript -e 'tell application "System Events" to get name of first process whose frontmost is true' 2>/dev/null || echo "unknown")"
echo "frontmost after:  $FRONT_AFTER"
[ "$FRONT_BEFORE" = "$FRONT_AFTER" ] || fail "this run changed the frontmost app ($FRONT_BEFORE -> $FRONT_AFTER)"
echo "  ok — the frontmost application is unchanged"
echo "m30-document-look: ok"
