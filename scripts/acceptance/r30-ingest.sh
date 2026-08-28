#!/usr/bin/env bash
#
# R30 — `mcp-router ingest`, driven as the shipped binary against a FIXTURE `~/.claude`.
#
# ## What this lane is for, and what it deliberately is not
#
# The unit suite drives `ClaudeExtensionScan`, `ExtensionIngest` and `ClaudeSettingsEdit` directly.
# It can prove the algorithm and it cannot prove the VERB: `ingest` resolves its own tree, its own
# router home and its own exit codes, and this repository has twice shipped a fully unit-tested
# capability that the one binary anybody runs could not reach — `GET /registry/search` answering 502
# with every check green, and `POST /servers/:name/auth` answering 405 until P7. So this asks the
# question the suite cannot: does the real `MCPRouterCLI ingest` do this, end to end, and does it
# refuse the things it is supposed to refuse?
#
# It is NOT a check against the real `~/.claude`, and it is built so that it cannot become one. The
# tree it works on is created here, under `mktemp -d`, from bytes written below. The one thing it
# says about the real tree is measured rather than assumed: the real `settings.json`'s size and
# modification time are recorded before the run and compared after it, so a lane that reached the
# wrong file reddens instead of passing quietly.
#
# Exit codes follow the house pattern:
#   0  every assertion held
#   1  the binary ran and did something wrong
#   2  the environment could not run the check — no binary, no fixture, no python3
#
# A run that asserts nothing exits 1, not 0. `assertions_made` is compared against a floor at the
# end for the reason `G4` records: a check reporting clean having measured nothing is the failure
# the check exists to prevent.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SWIFT_BIN="${SWIFT_BIN:-$REPO_ROOT/app/.build/debug/MCPRouterCLI}"
WORK="$(mktemp -d -t mcprouter-r30)"
CLAUDE="$WORK/claude"
ROUTER_HOME="$WORK/router"
FLOOR=20

pass=0
fail=0
declare -a failures=()

cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT INT TERM HUP

[ -x "$SWIFT_BIN" ] || { echo "environment: no MCPRouterCLI at $SWIFT_BIN (run: make build-cli-debug)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "environment: python3 is not installed"; exit 2; }

check() { # label actual expected
  if [ "$2" = "$3" ]; then
    printf '  ok   %-62s %s\n' "$1" "$2"
    pass=$((pass + 1))
  else
    printf '  FAIL %-62s got %s (wanted %s)\n' "$1" "$2" "$3"
    fail=$((fail + 1)); failures+=("$1")
  fi
}

# ---------------------------------------------------------------- the real tree, untouched
# Recorded before anything runs and compared at the end. If this lane ever grows a path that
# reaches the real settings.json, this is the assertion that says so.
REAL_SETTINGS="${HOME}/.claude/settings.json"
if [ -f "$REAL_SETTINGS" ]; then
  REAL_BEFORE="$(python3 -c 'import os,sys;s=os.stat(sys.argv[1]);print(f"{s.st_size}:{s.st_mtime_ns}")' "$REAL_SETTINGS")"
else
  REAL_BEFORE="absent"
fi

# ---------------------------------------------------------------- the fixture
# The shape is the real tree's, measured 2026-08-28; the bytes are this script's. Six identifiable
# entries and three that are not, so both halves of the acceptance clause have something to be true
# about.
mkdir -p "$CLAUDE/skills/graphify" "$CLAUDE/skills/mermaid-diagrams" "$CLAUDE/skills/half-installed" \
         "$CLAUDE/plugins/marketplaces/fledgeling-plugins/.claude-plugin" \
         "$CLAUDE/plugins/marketplaces/claude-code-plugins/.claude-plugin" \
         "$CLAUDE/plugins/cache/fledgeling-plugins/code-review/2.1.0/.claude-plugin" \
         "$CLAUDE/plugins/cache/claude-code-plugins/code-review/1.4.2/.claude-plugin" \
         "$CLAUDE/plugins/cache/fledgeling-plugins/swift-lsp/1.0.0" \
         "$ROUTER_HOME"

printf -- '---\nname: graphify\ndescription: turns a folder into a graph\n---\n\n# graphify\n' \
  > "$CLAUDE/skills/graphify/SKILL.md"
printf -- '---\nname: mermaid-diagrams\ndescription: draws diagrams\n---\n' \
  > "$CLAUDE/skills/mermaid-diagrams/SKILL.md"
printf 'no descriptor here\n' > "$CLAUDE/skills/half-installed/README.md"
printf 'nothing here\n' > "$CLAUDE/plugins/cache/fledgeling-plugins/swift-lsp/1.0.0/README.md"

for m in fledgeling-plugins claude-code-plugins; do
  printf '{"name":"%s","owner":{"name":"someone"},"plugins":[]}' "$m" \
    > "$CLAUDE/plugins/marketplaces/$m/.claude-plugin/marketplace.json"
done
printf '{"name":"code-review","version":"2.1.0","description":"from fledgeling"}' \
  > "$CLAUDE/plugins/cache/fledgeling-plugins/code-review/2.1.0/.claude-plugin/plugin.json"
printf '{"name":"code-review","version":"1.4.2","description":"from claude-code"}' \
  > "$CLAUDE/plugins/cache/claude-code-plugins/code-review/1.4.2/.claude-plugin/plugin.json"

cat > "$CLAUDE/plugins/installed_plugins.json" <<JSON
{ "version": 1, "plugins": {
  "code-review@fledgeling-plugins": [{"scope":"user","version":"2.1.0",
    "installPath":"$CLAUDE/plugins/cache/fledgeling-plugins/code-review/2.1.0"}],
  "code-review@claude-code-plugins": [{"scope":"user","version":"1.4.2",
    "installPath":"$CLAUDE/plugins/cache/claude-code-plugins/code-review/1.4.2"}],
  "swift-lsp@fledgeling-plugins": [{"scope":"user","version":"1.0.0",
    "installPath":"$CLAUDE/plugins/cache/fledgeling-plugins/swift-lsp/1.0.0"}],
  "studio-proxy@fledgeling-plugins": [{"scope":"user","version":"0.9.0",
    "installPath":"$CLAUDE/plugins/cache/fledgeling-plugins/studio-proxy/0.9.0"}]
} }
JSON

# Eight top-level members in the real file's order. Six of them are none of R30's business.
cat > "$CLAUDE/settings.json" <<'JSON'
{
  "env": { "CLAUDE_CODE_MAX_RETRIES": "4", "DISABLE_AUTOUPDATER": "1" },
  "includeCoAuthoredBy": false,
  "permissions": { "allow": ["Bash(git status)"], "deny": [], "ask": [], "defaultMode": "acceptEdits" },
  "model": "fixture-model",
  "hooks": { "SessionStart": [{"hooks":[{"type":"command","command":"echo start"}]}] },
  "statusLine": { "type": "command", "command": "echo line", "padding": 0 },
  "enabledPlugins": {
    "code-review@fledgeling-plugins": true,
    "code-review@claude-code-plugins": false,
    "swift-lsp@fledgeling-plugins": true
  },
  "extraKnownMarketplaces": { "fledgeling-plugins": { "source": { "source": "github", "repo": "example/one" } } }
}
JSON

# The settle window is set to 0 throughout: the fixture was written a moment ago, and the window's
# own behaviour is the unit suite's subject (`G3`, which plants both sides of it).
run_ingest() { MCP_ROUTER_HOME="$ROUTER_HOME" "$SWIFT_BIN" ingest --claude-home "$CLAUDE" --settle-seconds 0 "$@"; }

digest() { # a stable digest of a whole tree, so "nothing changed" is a comparison
  python3 - "$1" <<'PY'
import hashlib, os, sys
root = sys.argv[1]
h = hashlib.sha256()
for base, dirs, files in os.walk(root):
    dirs.sort()
    for name in sorted(files):
        p = os.path.join(base, name)
        h.update(os.path.relpath(p, root).encode())
        try:
            with open(p, 'rb') as fh: h.update(fh.read())
        except OSError:
            h.update(b'<unreadable>')
print(h.hexdigest())
PY
}

member() { python3 -c 'import json,sys;print(json.dumps(json.load(open(sys.argv[1])).get(sys.argv[2]),sort_keys=True,separators=(",",":")))' "$1" "$2"; }
keys()   { python3 -c 'import json,sys;print(",".join(json.load(open(sys.argv[1]))))' "$1"; }
jfield() { python3 -c 'import json,sys;d=json.load(sys.stdin);print(json.dumps(eval("d"+sys.argv[1]),sort_keys=True,separators=(",",":")))' "$1"; }

echo "R30 — mcp-router ingest against a fixture tree at $CLAUDE"
echo

# ---------------------------------------------------------------- 1. it refuses to pick a tree
out="$(MCP_ROUTER_HOME="$ROUTER_HOME" "$SWIFT_BIN" ingest 2>&1)"; rc=$?
check "no tree named: exits 1" "$rc" "1"
case "$out" in *"--claude-home"*) named=yes ;; *) named=no ;; esac
check "no tree named: the message says how to name one" "$named" "yes"
case "$out" in *"the default would be the real one"*) reason=yes ;; *) reason=no ;; esac
check "no tree named: it says why there is no default" "$reason" "yes"

out="$(MCP_ROUTER_HOME="$ROUTER_HOME" "$SWIFT_BIN" ingest --claude-home "$CLAUDE" --live 2>&1)"; rc=$?
check "--claude-home and --live together: exits 1" "$rc" "1"

# ---------------------------------------------------------------- 2. the dry run changes nothing
BEFORE_TREE="$(digest "$CLAUDE")"
BEFORE_EXT="$(digest "$CLAUDE/skills")|$(digest "$CLAUDE/plugins")"
plan="$(run_ingest --json)"; rc=$?
check "dry run: exits 0" "$rc" "0"
check "dry run: 6 candidates" "$(printf '%s' "$plan" | jfield '["candidateCount"]')" "6"
check "dry run: 3 left alone"  "$(printf '%s' "$plan" | jfield '["blockedCount"]')" "3"
check "dry run: applied is false" "$(printf '%s' "$plan" | jfield '["applied"]')" "false"
check "dry run: the tree is byte-identical afterwards" "$(digest "$CLAUDE")" "$BEFORE_TREE"
check "dry run: the router store was not created" "$([ -d "$ROUTER_HOME/extensions" ] && echo yes || echo no)" "no"

# The two plugins that share a name are both present, under Claude's own identity for them.
names="$(printf '%s' "$plan" | python3 -c 'import json,sys;print(",".join(sorted(c["name"] for c in json.load(sys.stdin)["candidates"])))')"
check "dry run: both code-review plugins survive the flat store" \
  "$names" "claude-code-plugins,code-review@claude-code-plugins,code-review@fledgeling-plugins,fledgeling-plugins,graphify,mermaid-diagrams"

reasons="$(printf '%s' "$plan" | python3 -c 'import json,sys;print(",".join(sorted(b["reason"] for b in json.load(sys.stdin)["blocked"])))')"
check "dry run: the three refusals are named" "$reasons" "sourceMissing,unreadableDescriptor,unreadableDescriptor"

# ---------------------------------------------------------------- 3. apply
SETTINGS="$CLAUDE/settings.json"
ENV_BEFORE="$(member "$SETTINGS" env)"
HOOKS_BEFORE="$(member "$SETTINGS" hooks)"
PERMS_BEFORE="$(member "$SETTINGS" permissions)"
applied="$(run_ingest --apply --json)"; rc=$?
check "apply: exits 0" "$rc" "0"
states="$(printf '%s' "$applied" | python3 -c 'import json,sys;print(",".join(sorted({o["state"] for o in json.load(sys.stdin)["outcomes"]})))')"
check "apply: every outcome is ingested" "$states" "ingested"
check "apply: 3 settings keys withdrawn" "$(printf '%s' "$applied" | jfield '["settingsRemoved"]')" "3"
check "apply: top-level key count is unchanged" \
  "$(printf '%s' "$applied" | jfield '["settingsTopLevelBefore"]')" "$(printf '%s' "$applied" | jfield '["settingsTopLevelAfter"]')"

check "apply: Claude no longer holds the skill" "$([ -e "$CLAUDE/skills/graphify" ] && echo yes || echo no)" "no"
check "apply: the router holds it" "$([ -f "$ROUTER_HOME/extensions/skills/graphify/SKILL.md" ] && echo yes || echo no)" "yes"
check "apply: the colliding plugins are both stored" \
  "$(ls "$ROUTER_HOME/extensions/plugins" | sort | tr '\n' ' ')" "code-review@claude-code-plugins code-review@fledgeling-plugins "

# The clause this item is most careful about.
check "apply: the unidentifiable skill is still where it was" \
  "$([ -f "$CLAUDE/skills/half-installed/README.md" ] && echo yes || echo no)" "yes"
check "apply: the descriptor-less plugin is still where it was" \
  "$([ -f "$CLAUDE/plugins/cache/fledgeling-plugins/swift-lsp/1.0.0/README.md" ] && echo yes || echo no)" "yes"

check "apply: settings.json keeps all eight members, in order" "$(keys "$SETTINGS")" \
  "env,includeCoAuthoredBy,permissions,model,hooks,statusLine,enabledPlugins,extraKnownMarketplaces"
check "apply: env is untouched" "$(member "$SETTINGS" env)" "$ENV_BEFORE"
check "apply: hooks are untouched" "$(member "$SETTINGS" hooks)" "$HOOKS_BEFORE"
check "apply: permissions are untouched" "$(member "$SETTINGS" permissions)" "$PERMS_BEFORE"
check "apply: only the ingested plugin keys left" "$(member "$SETTINGS" enabledPlugins)" '{"swift-lsp@fledgeling-plugins":true}'
check "apply: the ingested marketplace key left" "$(member "$SETTINGS" extraKnownMarketplaces)" '{}'

# ---------------------------------------------------------------- 4. undo, from the router alone
MANIFEST="$(printf '%s' "$applied" | python3 -c 'import json,sys;print(json.load(sys.stdin)["manifestPath"])')"
check "apply: a run manifest was written" "$([ -f "$MANIFEST" ] && echo yes || echo no)" "yes"
undo="$(MCP_ROUTER_HOME="$ROUTER_HOME" "$SWIFT_BIN" ingest --undo "$MANIFEST" --json)"; rc=$?
check "undo: exits 0" "$rc" "0"
check "undo: 3 settings keys restored" "$(printf '%s' "$undo" | jfield '["settingsRestored"]')" "3"
# The extension subtrees, not the whole tree: `settings.json` is re-serialised by the writer, so
# its bytes legitimately differ while every member is restored. Its members are compared as
# values on the next two lines, which is the claim that matters.
check "undo: the extension trees are byte-identical to before the run" \
  "$(digest "$CLAUDE/skills")|$(digest "$CLAUDE/plugins")" "$BEFORE_EXT"
check "undo: enabledPlugins is back" "$(member "$SETTINGS" enabledPlugins)" \
  '{"code-review@claude-code-plugins":false,"code-review@fledgeling-plugins":true,"swift-lsp@fledgeling-plugins":true}'
check "undo: extraKnownMarketplaces is back" "$(member "$SETTINGS" extraKnownMarketplaces)" \
  '{"fledgeling-plugins":{"source":{"repo":"example/one","source":"github"}}}'

# ---------------------------------------------------------------- 5. the presence control
# Every "nothing changed" above is an absence claim by a digest, and an absence claim needs an
# instrument that can see a change. Plant one and require the same comparison to fail.
printf 'planted\n' > "$CLAUDE/skills/graphify/PLANTED.md"
check "control: the digest sees a planted file" \
  "$([ "$(digest "$CLAUDE/skills")|$(digest "$CLAUDE/plugins")" = "$BEFORE_EXT" ] && echo blind || echo sighted)" "sighted"
rm -f "$CLAUDE/skills/graphify/PLANTED.md"

# ---------------------------------------------------------------- 6. the real tree, still untouched
if [ -f "$REAL_SETTINGS" ]; then
  REAL_AFTER="$(python3 -c 'import os,sys;s=os.stat(sys.argv[1]);print(f"{s.st_size}:{s.st_mtime_ns}")' "$REAL_SETTINGS")"
else
  REAL_AFTER="absent"
fi
check "the real ~/.claude/settings.json was not touched" "$REAL_AFTER" "$REAL_BEFORE"

echo
total=$((pass + fail))
echo "r30-ingest: $pass ok, $fail failed, $total assertions (floor $FLOOR)"
if [ "$total" -lt "$FLOOR" ]; then
  echo "r30-ingest: only $total assertions ran, below the floor of $FLOOR — this lane did not measure enough to pass"
  exit 1
fi
if [ "$fail" -gt 0 ]; then
  printf '  failed: %s\n' "${failures[@]}"
  exit 1
fi
exit 0
