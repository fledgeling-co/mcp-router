#!/usr/bin/env bash
#
# The watch half of the install lane — `install-launchd-watch`, and nothing else.
#
# SOURCED, never executed: `parity-install.sh` sources it to measure the row, and
# `parity-install-watch-mutations.sh` sources it to prove the terms it decides can go red. One copy
# of the observation, two callers. The mutation harness therefore runs THE GATE'S OWN CODE rather
# than a re-implementation of it — which matters here more than usual, because this row's whole
# history is a term that agreed sixteen times and measured the wrong thing (D-p1-e). A second copy
# of that term would have been free to drift, and a drifted copy agrees with the wrong answer.
#
# The caller owns the scratch and the cleanup, and must set, before sourcing:
#
#   WORK           a scratch directory this file may write under
#   STAMP          a per-process suffix, so two runs cannot collide on a launchd label
#   LAUNCHD_PATH   the PATH given to the agent (a launchd job inherits almost no environment)
#   LABELS         accumulator; every label bootstrapped here is appended, and the CALLER boots
#                  them out on every exit path. A stray agent left in the user's session keeps
#                  starting things they did not ask for.
#
# THE AGENT'S CONTRACT, which is not the serve agent's. `RunAtLoad` plus `WatchPaths` and **no**
# `KeepAlive`, because it is a one-shot: it runs, adopts what it can, and exits. Four observations
# per binary — it ran at load, a change to the watched path ran it again and that run observed the
# change, it did not stay resident, and which streams carry bytes.
#
# Nothing here restarts a real router. The staged `mcpServers` holds nothing adoptable, so neither
# binary reaches its `restartRouter()`, and both run under a scratch `MCPR_LAUNCHD_LABEL`.

# The watch agent's plist. The same supervision skeleton as the serve agent's, minus KeepAlive and
# plus WatchPaths — exactly the difference `docs/install.sh:147-151` writes between the two agents.
watch_plist() { # label home claudejson label-override program args...
  local label="$1" home="$2" claude="$3" override="$4"; shift 4
  local program_args=""
  for arg in "$@"; do program_args="$program_args    <string>$arg</string>
"; done
  cat <<XML
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$label</string>
  <key>ProgramArguments</key>
  <array>
$program_args  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>MCP_ROUTER_HOME</key><string>$home</string>
    <key>HOME</key><string>$(dirname "$claude")</string>
    <key>MCPR_LAUNCHD_LABEL</key><string>$override</string>
    <key>PATH</key><string>$LAUNCHD_PATH</string>
  </dict>
  <key>RunAtLoad</key><true/>
  <key>ThrottleInterval</key><integer>10</integer>
  <key>WatchPaths</key><array><string>$claude</string></array>
  <key>StandardOutPath</key><string>$home/agent.out</string>
  <key>StandardErrorPath</key><string>$home/agent.err</string>
</dict>
</plist>
XML
}

# Nothing adoptable, deliberately: the watcher still runs, still hashes and still writes its state,
# and never reaches a config write — so no router is restarted (X12b).
#
# The marker is the STIMULUS STAMP (P8). It lands in the server's NAME, and both binaries write
# that name into their own `watch.log` — `skipped "<name>": stdio server has no command` — on any
# run that got as far as reading a changed file. Measured on 2026-08-19 with a scratch HOME: the
# two log lines are byte-identical, as are the two `watch-state.json` hashes. That is what makes an
# observed re-run attributable to a particular staged change rather than merely concurrent with it.
stage() { # claude-json-path marker
  mkdir -p "$(dirname "$1")"
  # Written temp-then-rename. `cat >` truncates and then fills, so a watcher can observe the file
  # twice (empty, then complete) or parse it mid-write — either of which presents as a spurious or
  # a malformed event rather than as the single change this is meant to be.
  cat > "$1.staging" <<JSON
{
  "numStartups": 41,
  "mcpServers": { "notadoptable-$2": { "note": "no command and no url" } }
}
JSON
  mv "$1.staging" "$1"
}

# ---------------------------------------------------------------------------------------------
# P5 — the two watch terms, each given its OWN named fix, with the bound written down here rather
# than discovered by re-running until the answer was nice.
#
# What was measured first, on this machine, with a scratch launchd agent whose program was a plain
# bash script — NEITHER node NOR Swift, so neither router could be the cause:
#
#   · `launchctl print` carries `runs = N` and `state = not running`. That is launchd's OWN
#     accounting of how many times it has spawned the job, and it is the observable both terms were
#     missing. Everything before this inferred them from a file the job writes and from whether a
#     `pid` line happened to be present at the instant it was sampled.
#   · one `mv` onto the watched path incremented `runs` in FOUR of five trials, 9-14s later
#     (ThrottleInterval is 10, so the floor is the throttle). In the fifth it never incremented at
#     all inside 60s. The event was dropped.
#
# That fifth trial is the whole story: WatchPaths delivery is lossy, the loss is launchd's, and it
# happens with no router involved. A lane that treats one `mv` as a reliable stimulus is therefore
# nondeterministic BY CONSTRUCTION, and no amount of waiting on the observer side fixes a stimulus
# that was never delivered.
#
# TERM `oneshot` — FIX: stop inferring residency from the absence of a `pid` sample.
#   The old predicate was "`agent_pid` printed nothing", which is equally true when the job has
#   finished and when it is BETWEEN two runs. A second run — a spurious WatchPaths delivery, or the
#   throttled re-run of a stimulus staged earlier — makes the second case real, and the two are
#   indistinguishable to a pid probe. `runs` distinguishes them exactly, because it changes when a
#   new run STARTS. So settled now means: launchd says `not running` AND the run counter has not
#   moved for a whole settling window.
#
# TERM `reran` — FIX: stop deciding it from the CONTENT OF A FILE THE JOB WRITES, and stop treating
#   one `mv` as a reliable stimulus.
#   Deciding it from `watch-state.json` asks the wrong question twice over: it is written by the
#   process rather than by launchd, so it cannot see a run that started and it cannot see a run that
#   wrote nothing. `runs` answers the actual question — did launchd spawn it again. And because
#   delivery is lossy, the stimulus is RE-DELIVERED on a schedule until the counter moves or the
#   bound expires.
#
#   RE-DELIVERING THE STIMULUS IS NOT RE-RUNNING UNTIL GREEN, and the difference is worth stating
#   because this fleet has made that mistake once. Re-running until green repeats the MEASUREMENT
#   and keeps the answer it likes. This repeats the INPUT — a change to the watched file, which is
#   the thing a user's ~/.claude.json does many times a day — and keeps whatever the first delivered
#   event produces.
#
# ---------------------------------------------------------------------------------------------
# P8 — `reran` counted spawns, and a spawn is not an observation.
#
# WHAT WAS MEASURED (D-p1-e). Everything above is kept and none of it is in dispute. What broke the
# term was the MUTATION, not the series: point the agent's `WatchPaths` at a decoy in a fresh
# `mktemp -d` the lane never touches, so a genuine delivery is impossible and the only correct
# answer is `no`, and six trials read 4 correctly red and **2 spuriously green** — `runs=1->2`,
# byte-identical in the report to a genuine first-delivery re-run. The gate runs this lane once, so
# a watcher that never re-ran would have recorded the row green about one run in three.
#
# THE DEFECT, NAMED. `runs` moving proves launchd SPAWNED the job. The row's claim is that a change
# to the watched path is PICKED UP. Those differ by exactly one thing — whether the run that
# happened has anything to do with the change that was staged — and launchd spawns a WatchPaths job
# for reasons of its own often enough to make the difference decidable one run in three.
#
# THE FIX, IN TWO HALVES. Neither is sufficient alone.
#
#   1. THE STIMULUS IS STAMPED, AND THE STAMP MUST COME BACK. Each staged change carries a token
#      unique to this side and this run, in the name of a server neither binary can adopt. Both
#      binaries log that name — and only on a run that read a CHANGED file, because the hash fast
#      path returns before the parse. So `reran` now asks "did a run observe THIS change", which is
#      the row's actual claim, instead of "did the counter move", which is launchd's business.
#
#   2. THE STIMULUS GOES TO THE PATH THE PLIST DECLARES, read back out of the generated file with
#      `plutil` rather than taken from the variable that was passed in. The lane delivers the change
#      to the path this agent is actually configured to watch, whatever that turns out to be.
#
#      Half 2 is what makes the decoy mutation decidable at all. With the stimulus hard-wired to the
#      agent's `$HOME/.claude.json`, a decoy `WatchPaths` still leaves the lane changing the file
#      the watcher reads, so any spawn — spurious or not — observes the staged change and reports
#      the stamp. Following the plist means a decoy agent is stimulated at its decoy, the file it
#      reads never changes after load, and every spawn takes the hash fast path and writes nothing.
#      That is not left as an argument: the mutation harness carries a `stamp-only` arm which
#      reverts half 2 and reports the rate at which the stamp alone still goes green.
#
#      The plist's path is REPORTED (`watched=self` or the path) and never ASSERTED. Asserting it
#      would redden the mutation by having the lane notice its own configuration, which measures the
#      lane rather than the binary. The stamp round-trip is the measurement; the path is context.
#
# WHAT THIS TERM NOW CLAIMS, stated at its real strength: a change written to the path this agent
# watches is observed by a run that follows it. It does NOT claim launchd delivers every change —
# that is false of launchd, measured, and is why the stimulus is re-delivered up to six times. Nor
# does it distinguish a launchd delivery from an unrelated spawn that read the same changed file;
# it does not need to, because a run that reports the stamp has observed the change either way,
# which is the thing the installer's watch agent exists to do.
#
# MEASURED AFTER THE FIX, by `parity-install-watch-mutations.sh`, which runs this exact code:
# see that script's own roll-up for the arms, the trial counts and the rates.
#
# THE BOUNDS, fixed here in advance:
WATCH_SETTLE_TICKS=240        # 60s at 0.25s — how long a first run may take before it is resident
WATCH_SETTLE_STABLE=12        # 3s of `not running` with an unmoved counter is "settled"
WATCH_RESTAGE_ATTEMPTS=6      # re-deliver the change up to six times
WATCH_RESTAGE_TICKS=30        # 15s at 0.5s per attempt, so 90s total against a 10s throttle
WATCH_STAMP_TICKS=20          # 10s more for the stamp of a delivery that landed inside the last
                              # attempt's window — the counter moves when the job STARTS and the
                              # log line is written a moment later, so a hard stop at the last
                              # attempt would fail a genuine observation on that gap alone
# Per-side evidence for the report: what launchd's counter did, how many deliveries it took, and
# WHICH staged change came back. A FILE rather than a variable, because `observe_watch` is invoked
# through command substitution and anything it assigns dies with that subshell. Printed rather than
# merely kept, because "it agreed", "it agreed on the first delivery" and "it agreed and named the
# change it saw" are three different facts, and a future reader deciding whether to keep this row
# needs the third one.
WATCH_EVIDENCE="$WORK/watch-evidence"
: > "$WATCH_EVIDENCE"

# Every label this file bootstraps, one per line, so the CALLER can boot them out on a path that
# never reaches the end of `observe_watch`. A FILE for the same reason the evidence is a file:
# `observe_watch` is invoked through command substitution, so the `LABELS` accumulator it appends to
# is a variable in a subshell that is discarded the instant it returns. The accumulator is kept as
# well — it costs nothing and it is what the serve half uses — but this is the copy that survives.
WATCH_LABELS="$WORK/watch-labels"
: > "$WATCH_LABELS"

agent_state() { launchctl print "gui/$(id -u)/$1" 2>/dev/null | awk -F'= ' '/^\tstate = /{print $2; exit}'; }
agent_runs() { launchctl print "gui/$(id -u)/$1" 2>/dev/null | awk '/^\truns = /{print $3; exit}'; }

# The path this agent will actually watch, read out of the plist that is about to be loaded.
watched_path_of() { # plist
  /usr/bin/plutil -extract WatchPaths.0 raw -o - "$1" 2>/dev/null
}

# The stamp the watcher reported back, or `none`.
#
# `skipped "<name>": <reason>` is written by both binaries for a staged entry they cannot adopt,
# and only from a run that read a file whose `mcpServers` hash had changed — the fast path returns
# before any candidate is parsed. The last such line is the most recent change this watcher saw.
watch_stamp_seen() { # logpath token-prefix
  [ -s "$1" ] || { printf none; return 0; }
  local seen
  seen="$(sed -n "s/.*skipped \"notadoptable-\($2-[0-9][0-9]*\)\".*/\1/p" "$1" | tail -1)"
  printf '%s' "${seen:-none}"
}

# Settled: launchd reports the job not running, and its run counter has stopped moving.
#
# Both halves are load-bearing. `not running` alone is momentarily true in the gap between two runs;
# an unmoved counter alone is true while a long single run is still going. Requiring both, for a
# whole window, is what separates "this is a one-shot that has finished" from "this is a one-shot
# that is about to be started again" — the two the old pid probe could not tell apart.
watch_settled() { # label ticks
  local label="$1" bound="$2" tick stable=0 last="" state runs
  for ((tick = 0; tick < bound; tick++)); do
    state="$(agent_state "$label")"
    runs="$(agent_runs "$label")"
    if [ "$state" = "not running" ] && [ -n "$runs" ] && [ "$runs" = "$last" ]; then
      stable=$((stable + 1))
      [ "$stable" -ge "$WATCH_SETTLE_STABLE" ] && return 0
    else
      stable=0
    fi
    last="$runs"
    sleep 0.25
  done
  return 1
}

observe_watch() { # side program args...
  local side="$1"; shift
  local label="app.fledgeling.mcp-router.parity-watch-$side-$STAMP"
  local home="$WORK/watch-$side" claudehome="$WORK/watch-$side-home"
  mkdir -p "$home" "$claudehome"
  stage "$claudehome/.claude.json" "base-$side-$STAMP"
  watch_plist "$label" "$home" "$claudehome/.claude.json" \
    "gg.rhodes.mcp-router-parity-$STAMP" "$@" > "$WORK/watch-$side.plist"
  LABELS="$LABELS $label"
  printf '%s\n' "$label" >> "$WATCH_LABELS"

  # Where the stimulus goes — the plist's own WatchPaths, not the variable above. See P8's block.
  local watched
  watched="$(watched_path_of "$WORK/watch-$side.plist")"
  [ -n "$watched" ] || { printf 'no-watchpaths-in-plist'; return 0; }
  local watched_note="self"
  [ "$watched" = "$claudehome/.claude.json" ] || watched_note="$watched"

  launchctl bootout "gui/$(id -u)/$label" >/dev/null 2>&1
  if ! launchctl bootstrap "gui/$(id -u)" "$WORK/watch-$side.plist" \
       >"$WORK/watch-$side.bootstrap" 2>&1; then
    printf 'bootstrap-refused'
    return 0
  fi

  local ran=no reran=no oneshot=no logged=none
  local state="$home/watch-state.json"
  # `ran` stays on the state file deliberately. `runs` proves LAUNCHD spawned something; the state
  # file proves the BINARY got as far as doing its job, and that second one is the parity claim.
  for _ in $(seq 1 80); do [ -s "$state" ] && { ran=yes; break; }; sleep 0.25; done

  # TERM `oneshot`, decided from launchd's own state and run counter — see the block above
  # `watch_settled` for why the pid probe this replaces could not tell a finished one-shot from a
  # one-shot between two runs.
  local settled=yes
  watch_settled "$label" "$WATCH_SETTLE_TICKS" || settled=no
  [ "$settled" = yes ] && oneshot=yes

  # TERM `reran` — launchd's counter moved AND the run that followed named the change that was
  # staged. The stimulus is re-delivered because WatchPaths delivery is lossy (measured 4 of 5 with
  # a plain bash agent, so neither router is implicated); the stamp is required because a counter
  # that moved is a spawn and the row's claim is an observation. Both blocks above argue it in full.
  local before_runs attempt tick now stamp=none token prefix="stim-$side-$STAMP"
  before_runs="$(agent_runs "$label")"
  for ((attempt = 0; attempt < WATCH_RESTAGE_ATTEMPTS; attempt++)); do
    token="$prefix-$attempt"
    stage "$watched" "$token"
    for ((tick = 0; tick < WATCH_RESTAGE_TICKS; tick++)); do
      stamp="$(watch_stamp_seen "$home/watch.log" "$prefix")"
      now="$(agent_runs "$label")"
      if [ "$stamp" != none ] && [ -n "$now" ] && [ -n "$before_runs" ] \
         && [ "$now" -gt "$before_runs" ]; then
        reran=yes
        break 2
      fi
      sleep 0.5
    done
  done
  local delivered=$((attempt + 1))
  [ "$delivered" -gt "$WATCH_RESTAGE_ATTEMPTS" ] && delivered="$WATCH_RESTAGE_ATTEMPTS"
  # The stamp of a delivery that landed at the end of the last attempt is written a moment after the
  # counter moves. Nothing is re-staged here — this waits on the run already in flight.
  if [ "$reran" = no ]; then
    for ((tick = 0; tick < WATCH_STAMP_TICKS; tick++)); do
      stamp="$(watch_stamp_seen "$home/watch.log" "$prefix")"
      now="$(agent_runs "$label")"
      if [ "$stamp" != none ] && [ -n "$now" ] && [ -n "$before_runs" ] \
         && [ "$now" -gt "$before_runs" ]; then
        reran=yes
        break
      fi
      sleep 0.5
    done
  fi
  # Appended to a FILE, not to a variable. `observe_watch` is called through `$( … )`, which runs it
  # in a subshell, so an assignment here would be discarded the moment it returned — the same trap
  # the harness lock documents for its own release guard.
  #
  # `stages` carries its denominator so a reader sees whether agreement needed one delivery or six.
  # `stamp` is which staged change came back; `watched` is `self` when the agent watches the file it
  # reads, and the path when it does not.
  printf '%s:runs=%s->%s:stages=%s/%s:stamp=%s:watched=%s ' \
    "$side" "${before_runs:-?}" "$(agent_runs "$label")" "$delivered" \
    "$WATCH_RESTAGE_ATTEMPTS" "$stamp" "$watched_note" >> "$WATCH_EVIDENCE"

  logged="$([ -s "$home/agent.out" ] && printf o || printf -)$([ -s "$home/agent.err" ] && printf e || printf -)"
  launchctl bootout "gui/$(id -u)/$label" >/dev/null 2>&1
  printf '%s,%s,%s,%s' "$ran" "$reran" "$oneshot" "$logged"
}
