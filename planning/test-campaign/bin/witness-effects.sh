#!/bin/bash
# Effect witnesses for the four requirements that claim an effect outside the process.
#
# The rung's rule is that the recorder must be one the product does not control. Here the
# recorders are the kernel's socket table (lsof), the process table (ps), and filesystem
# metadata (stat) — none of which the router can write to, and each of which is read both
# before and after so a pre-existing state cannot be reported as an effect.
#
# Everything runs against MCP_ROUTER_HOME=/tmp/mcp-witness-home on a port the campaign
# reserves, so the user's own router at 127.0.0.1:8879 is never touched, read or restarted.
#
# REQ-016 is deliberately absent. Its declared outbound-socket effect has no provider in
# production source (DEF-041), so there is nothing for a recorder to see, and a witness that
# saw nothing would be the condition under test rather than proof of it.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../../.." && pwd)"
CLI="$REPO/app/.build/debug/MCPRouterCLI"
HOME_DIR=/tmp/mcp-witness-home
PORT=8973
OUT="$REPO/planning/test-campaign/evidence/witness"
export MCP_ROUTER_HOME="$HOME_DIR"

mkdir -p "$OUT"
LOG="$OUT/witness.log"
: > "$LOG"
say() { printf '%s\n' "$*" | tee -a "$LOG"; }

say "== effect witness pass =="
say "recorded at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
say "binary:      $CLI"
say "sha256:      $(shasum -a 256 "$CLI" | cut -d' ' -f1)"
say "router home: $HOME_DIR   (the user's own home is untouched)"
say "port:        127.0.0.1:$PORT"
say ""

fail=0
declare -a JSON

record() { JSON+=("$1"); }

# ---------------------------------------------------------------- REQ-013, filesystem-write
say "-- REQ-013 filesystem-write --------------------------------------------"
rm -f "$HOME_DIR/manifest.json"
BEFORE_EXISTS=$([ -e "$HOME_DIR/manifest.json" ] && echo yes || echo no)
say "recorder: stat(2) on $HOME_DIR/manifest.json"
say "before:   exists=$BEFORE_EXISTS"
"$CLI" index --force >>"$LOG" 2>&1
IDX_RC=$?
AFTER_EXISTS=$([ -e "$HOME_DIR/manifest.json" ] && echo yes || echo no)
if [ "$AFTER_EXISTS" = yes ]; then
  ST=$(stat -f 'inode=%i bytes=%z mtime=%Sm' -t %Y-%m-%dT%H:%M:%SZ "$HOME_DIR/manifest.json")
  say "after:    exists=yes  $ST"
  say "VERDICT:  witnessed — count=1 (index rc=$IDX_RC)"
  record "{\"req\":\"REQ-013\",\"effect\":\"filesystem-write\",\"recorder\":\"stat(2) filesystem metadata\",\"count\":1,\"before\":\"absent\",\"after\":\"$ST\"}"
else
  say "VERDICT:  NOT witnessed — no file appeared (index rc=$IDX_RC)"
  record "{\"req\":\"REQ-013\",\"effect\":\"filesystem-write\",\"recorder\":\"stat(2) filesystem metadata\",\"count\":0}"
  fail=1
fi
say ""

# ------------------------------------- REQ-001/011 subprocess + REQ-012 inbound-socket
# These two share one live router on purpose. A `ps` reading taken after the parent has
# exited cannot say whose child it was — the first version of this script recorded exactly
# that and reported "witnessed with a caveat", which is a witness that saw the effect and
# not its cause. Holding the router up lets ps answer the causal question directly.
say "-- REQ-012 inbound-socket ----------------------------------------------"
say "recorder: the kernel socket table, read through lsof(8)"
PRE=$(lsof -nP -iTCP@127.0.0.1:$PORT 2>/dev/null | grep -c LISTEN)
say "before:   LISTEN entries on 127.0.0.1:$PORT = $PRE"
if [ "$PRE" -ne 0 ]; then
  say "REFUSING: something already holds that port; a listener found now would not be ours."
  exit 2
fi
rm -f "$HOME_DIR/child.pid"
"$CLI" serve --port $PORT >>"$LOG" 2>&1 &
SPID=$!
for _ in $(seq 1 20); do
  lsof -nP -iTCP@127.0.0.1:$PORT 2>/dev/null | grep -q LISTEN && break
  sleep 0.4
done
LISTEN_ROW=$(lsof -nP -iTCP@127.0.0.1:$PORT 2>/dev/null | grep LISTEN | head -1)
if [ -n "$LISTEN_ROW" ]; then
  LPID=$(printf '%s' "$LISTEN_ROW" | awk '{print $2}')
  say "after:    $(printf '%s' "$LISTEN_ROW" | tr -s ' ')"
  say "owner pid $LPID == serve pid $SPID ? $([ "$LPID" = "$SPID" ] && echo yes || echo "no - pid $LPID")"

  # Hold a connection open across the sample. curl closes as soon as the body lands, and the
  # first version of this script sampled afterwards and recorded ESTABLISHED=0 - a real
  # accepted connection that the recorder was pointed at a moment too late to see.
  ( exec 7<>/dev/tcp/127.0.0.1/$PORT
    printf 'GET /mcp HTTP/1.1\r\nHost: 127.0.0.1\r\nAccept: text/event-stream\r\n\r\n' >&7
    sleep 3 ) &
  HOLD=$!
  sleep 1
  EST_ROWS=$(lsof -nP -iTCP@127.0.0.1:$PORT 2>/dev/null | grep ESTABLISHED)
  EST=$(printf '%s' "$EST_ROWS" | grep -c ESTABLISHED)
  ACCEPTED=$(printf '%s\n' "$EST_ROWS" | awk -v p="$LPID" '$2==p' | wc -l | tr -d ' ')
  wait "$HOLD" 2>/dev/null
  CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "http://127.0.0.1:$PORT/mcp" 2>/dev/null)
  say "a client held a socket open across the sample:"
  say "  ESTABLISHED rows on that port  = $EST"
  say "  of which owned by the router   = $ACCEPTED   (the accepted half of the pair)"
  say "  a separate request returned      HTTP $CODE"
  if [ "$ACCEPTED" -ge 1 ]; then
    say "VERDICT:  witnessed - count=1, an independent recorder saw the router bind the port AND"
    say "          hold the accepted end of a real client connection."
    record "{\"req\":\"REQ-012\",\"effect\":\"inbound-socket\",\"recorder\":\"kernel socket table via lsof(8)\",\"count\":1,\"before\":\"no LISTEN on 127.0.0.1:$PORT\",\"after\":\"$(printf '%s' "$LISTEN_ROW" | tr -s ' ')\",\"ownerPid\":$LPID,\"establishedOwnedByRouter\":$ACCEPTED,\"clientHttpStatus\":\"$CODE\"}"
  else
    say "VERDICT:  witnessed for the bind, NOT for the accept - lsof saw the LISTEN but no"
    say "          ESTABLISHED row owned by pid $LPID while a client held a socket open."
    record "{\"req\":\"REQ-012\",\"effect\":\"inbound-socket\",\"recorder\":\"kernel socket table via lsof(8)\",\"count\":1,\"partial\":\"bind witnessed, accept not\",\"ownerPid\":$LPID,\"establishedOwnedByRouter\":0,\"clientHttpStatus\":\"$CODE\"}"
  fi
else
  say "VERDICT:  NOT witnessed - nothing bound the port"
  record "{\"req\":\"REQ-012\",\"effect\":\"inbound-socket\",\"recorder\":\"kernel socket table via lsof(8)\",\"count\":0}"
  fail=1
fi
say ""

say "-- REQ-001 / REQ-011 subprocess ----------------------------------------"
say "recorder: two records, neither written by the router. The SHELL records the pid it"
say "          launched, through \$!. The CHILD records its own getppid(), which is the"
say "          kernel's answer to who spawned it, into a file under a path passed in the"
say "          environment and never read back by the product. If those two agree, the"
say "          spawn is attributed by two parties that cannot have coordinated."
say ""
say "          A ps(1) sample runs alongside as a third, best-effort reading. It usually"
say "          misses: the index verb spawns, handshakes and exits inside one scheduling"
say "          quantum. Two earlier versions of this witness depended on ps alone and could"
say "          report only that the child had a parent, not whose child it was."
rm -f "$HOME_DIR/child.pid" "$OUT/pstree.txt"
"$CLI" index --force >>"$LOG" 2>&1 &
IPID=$!
PS_ROW=""
for _ in $(seq 1 400); do
  ROW=$(ps -Ao pid=,ppid=,comm= 2>/dev/null | awk -v p="$IPID" '$2==p')
  [ -n "$ROW" ] && { PS_ROW="$ROW"; break; }
  kill -0 "$IPID" 2>/dev/null || break
done
wait "$IPID" 2>/dev/null
SELF=""
[ -s "$HOME_DIR/child.pid" ] && SELF=$(cat "$HOME_DIR/child.pid")
{ echo "recorded at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "shell \$! for the router invocation : $IPID"
  echo "child's own \"getpid getppid\"       : ${SELF:-none}"
  echo "ps(1) rows with that ppid           : ${PS_ROW:-none caught; the spawn was shorter than one sample}"
} > "$OUT/pstree.txt"
if [ -n "$SELF" ]; then
  CPID=$(printf '%s' "$SELF" | awk '{print $1}')
  CPPID=$(printf '%s' "$SELF" | awk '{print $2}')
  say ""
  say "shell recorded launching pid : $IPID"
  say "child reports its parent as  : $CPPID   (child pid $CPID)"
  say "ps sample                    : ${PS_ROW:-missed - spawn shorter than one sample}"
  if [ "$CPPID" = "$IPID" ]; then
    say "VERDICT:  witnessed - count=1. The two independent records name the same parent, so"
    say "          the router process spawned this child. Artifact: evidence/witness/pstree.txt"
    record "{\"req\":\"REQ-001\",\"effect\":\"subprocess\",\"recorder\":\"the shell's \$! for the router invocation and the child's own getppid(); ps(1) sampled alongside\",\"count\":1,\"parentPid\":$IPID,\"childPid\":$CPID,\"childReportedParent\":$CPPID,\"agree\":true,\"psRow\":\"${PS_ROW:-missed}\",\"artifact\":\"evidence/witness/pstree.txt\"}"
    record "{\"req\":\"REQ-011\",\"effect\":\"subprocess\",\"recorder\":\"the shell's \$! for the router invocation and the child's own getppid(); ps(1) sampled alongside\",\"count\":1,\"parentPid\":$IPID,\"childPid\":$CPID,\"childReportedParent\":$CPPID,\"agree\":true,\"psRow\":\"${PS_ROW:-missed}\",\"artifact\":\"evidence/witness/pstree.txt\"}"
  else
    say "VERDICT:  witnessed for the spawn, NOT for its parent - a child ran, but it names"
    say "          pid $CPPID as its parent where the shell launched $IPID. They disagree, so"
    say "          the spawn is not attributed to the router by this run."
    record "{\"req\":\"REQ-001\",\"effect\":\"subprocess\",\"recorder\":\"shell \$! and the child's getppid()\",\"count\":1,\"partial\":\"spawn witnessed, parent disagrees\",\"parentPid\":$IPID,\"childReportedParent\":$CPPID,\"agree\":false}"
    record "{\"req\":\"REQ-011\",\"effect\":\"subprocess\",\"recorder\":\"shell \$! and the child's getppid()\",\"count\":1,\"partial\":\"spawn witnessed, parent disagrees\",\"parentPid\":$IPID,\"childReportedParent\":$CPPID,\"agree\":false}"
    fail=1
  fi
else
  say "VERDICT:  NOT witnessed - no child recorded itself"
  record "{\"req\":\"REQ-001\",\"effect\":\"subprocess\",\"recorder\":\"shell \$! and the child's getppid()\",\"count\":0}"
  record "{\"req\":\"REQ-011\",\"effect\":\"subprocess\",\"recorder\":\"shell \$! and the child's getppid()\",\"count\":0}"
  fail=1
fi
say ""

kill "$SPID" 2>/dev/null; wait "$SPID" 2>/dev/null
sleep 0.5
POST=$(lsof -nP -iTCP@127.0.0.1:$PORT 2>/dev/null | grep -c LISTEN)
say "after teardown: LISTEN entries on 127.0.0.1:$PORT = $POST"
say ""

# ---------------------------------------------------------------- REQ-016, no provider
say "-- REQ-016 outbound-socket ---------------------------------------------"
say "NOT WITNESSABLE. No symbol under app/Sources opens a connection to a paired device"
say "(DEF-041, agreeing with DEF-001 from the effect side). A recorder pointed at this would"
say "see nothing, and nothing seen is the condition under test rather than proof of it."
record "{\"req\":\"REQ-016\",\"effect\":\"outbound-socket\",\"recorder\":null,\"count\":0,\"status\":\"vacuous\",\"why\":\"no provider in production source; DEF-041\"}"
say ""

{ printf '{\n  "recordedAt": "%s",\n  "binary": "%s",\n  "binarySha256": "%s",\n  "routerHome": "%s",\n  "port": %d,\n  "witnesses": [\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$CLI" "$(shasum -a 256 "$CLI" | cut -d' ' -f1)" "$HOME_DIR" "$PORT"
  for i in "${!JSON[@]}"; do
    printf '    %s%s\n' "${JSON[$i]}" "$([ "$i" -lt $((${#JSON[@]}-1)) ] && echo ,)"
  done
  printf '  ]\n}\n'
} > "$OUT/effects.json"

say "wrote $OUT/effects.json"
say "exit: $fail"
exit $fail
