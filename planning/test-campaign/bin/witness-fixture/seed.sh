#!/bin/bash
# Materialise a router home holding one stdio upstream, from the fixture kept in this repo.
#
# The witness scripts used to read the fixture straight out of /tmp/mcp-witness-home, which is
# where the first pass happened to build it. /tmp does not survive a reboot, and two of the three
# scripts copied it with `2>/dev/null` -- so the copy would fail silently, the arm would run
# against a home declaring no servers, the recorder would honestly report count=0, and the script
# would print "the recorder discriminates" for entirely the wrong reason. A false arm is worse
# than a missing one, so this fails loudly instead.
set -euo pipefail
HOME_DIR="${1:?usage: seed.sh <home-dir>}"
HERE="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$HOME_DIR"
cp "$HERE/fixture-server.py" "$HOME_DIR/fixture-server.py"
sed "s#__HOME__#$HOME_DIR#g" "$HERE/servers.json.tmpl" > "$HOME_DIR/servers.json"
test -s "$HOME_DIR/fixture-server.py" || { echo "seed.sh: fixture-server.py did not land in $HOME_DIR" >&2; exit 1; }
grep -q "$HOME_DIR/fixture-server.py" "$HOME_DIR/servers.json" || {
  echo "seed.sh: servers.json does not point at the fixture in $HOME_DIR" >&2; exit 1; }
