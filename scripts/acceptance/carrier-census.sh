#!/usr/bin/env bash
#
# R33 — the carrier census: which router implementation each landing on this branch touched.
#
# It prints one tab-separated row per landing that touched EITHER router, and nothing else:
#
#     landing  <sha>  <label>  <carrier>  <swift-files>  <ts-files>
#
# where `carrier` is `swift-only`, `typescript-only` or `both`.
#
# **Why this exists.** This repository ships two routers. `src/*.ts` is the reference the
# differential harness drives; `app/Sources/RouterCore` plus `app/Sources/MCPRouterCLI` is the
# Swift one. `docs/install.sh` points the launchd agents at Swift by default since R4-C1, and
# `REQ-020` reserves retiring the TypeScript tree to the owner. So a change landing in ONE of the
# two is a normal, expected, deliberate act — and it is also the thing nothing in this repo could
# see. R33 was filed after a deployment measured `GET /caches` answering 404 on the running router
# while `GET /sessions` answered 200: four of five items delivered for the 2026-08-28 goal were
# Swift-only and one was TypeScript-only, and every gate in the tree was green throughout.
#
# The parity harness cannot report this and is not meant to. It compares BEHAVIOUR on rows that
# exist on both sides. A capability that exists on one side has no row to compare, so it is
# invisible to a comparison by construction — the absence and the agreement look identical.
#
# **This file measures and never judges.** The judging is `planning/carrier-parity-gate.py`'s,
# which requires a disposition for each one-sided landing at or after a pinned commit. Exit codes
# follow the house pattern that `surface-census.sh` set: 0 the census printed, 2 the census could
# not be taken. There is no exit 1.
#
# **A census of zero rows is a broken reader, never a repository nobody has touched.** Both path
# sets are probed against the working tree before anything is walked, and a set that matches no
# tracked file exits 2 as a locator failure rather than reporting every landing as untouched. That
# is R4-C1's lesson from `install-router-default.sh`: a stale anchor exits 2, not 0, because an
# extraction that finds nothing otherwise reports a clean sweep of nothing.
#
# **The walk is first-parent, and that is load-bearing rather than a performance choice.** A
# census over `git log --merges` misses R30 outright: `516be61`, subject `Merge ai/r30: ingest what
# Claude acquires, copy-verify-remove, reversibly`, has ONE parent. It reads like a merge, it is
# named like a merge, and `--merges` does not select it. R30 is one of the four items R33 exists
# about, so the obvious census would have been blind to a quarter of its own subject. First-parent
# is what "landed on this branch" actually means, and it takes fast-forwards, squashes and merges
# alike.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REV="${CARRIER_CENSUS_REV:-HEAD}"

cd "$REPO_ROOT" || { echo "environment: cannot enter $REPO_ROOT" >&2; exit 2; }

git rev-parse --git-dir >/dev/null 2>&1 || {
  echo "environment: $REPO_ROOT is not a git repository, so there are no landings to walk." >&2
  exit 2
}

# ---------------------------------------------------------------------------------------------
# The two implementations, named as path prefixes and checked against the tree before use.
#
# TypeScript router: `src/*.ts`. The whole directory is the reference router — index, router,
# control, pool, manifest, auth, oauth, registry, usage, sessions, watch, log, lock, config,
# document, livereload. There is no non-router code in it.
#
# Swift router: `app/Sources/RouterCore` (the library) and `app/Sources/MCPRouterCLI` (the process
# that serves, and the verbs). Deliberately NOT `MCPRouterKit` or `MCPRouterUI`, which are the Mac
# app, and not `ControlDiff`, `ControlProbe` or `MeasureDump`, which are harness instruments. The
# same three-way split is the one ORCHESTRATOR.md already uses when it records that "M6's diff over
# RouterCore, MCPRouterCLI and src/ is empty".
SWIFT_RE='^app/Sources/(RouterCore|MCPRouterCLI)/'
TS_RE='^src/[^/]+\.ts$'

probe_swift="$(git ls-tree -r --name-only "$REV" | grep -cE "$SWIFT_RE")"
probe_ts="$(git ls-tree -r --name-only "$REV" | grep -cE "$TS_RE")"

if [ "$probe_swift" -eq 0 ] || [ "$probe_ts" -eq 0 ]; then
  echo "environment: a path set matched nothing at $REV — swift=$probe_swift typescript=$probe_ts." >&2
  echo "             Every landing would be classified as touching neither router, and this census" >&2
  echo "             would report a clean sweep of nothing. Fix the pattern; do not read the zero." >&2
  exit 2
fi

# ---------------------------------------------------------------------------------------------
# The walk. ONE `git log` pass and ONE `awk` over it, rather than a `git diff` and two `grep`s per
# commit. Measured on this repository over 472 landings: 0.9s here against 16s for the per-commit
# form the first version used. That is not tidiness — `carrier-parity-selftest.sh` runs the gate
# eight times, and at 16s a pass the gate is not armable within a sensible run.
#
# `--first-parent -m --name-only` emits each landing's files against its first parent, which for a
# merge is the whole branch and for an ordinary commit is the commit. `-z` is deliberately NOT
# passed: it would NUL-terminate every PATH as well, and the record separator would stop separating
# records. `core.quotePath=false` keeps a path with unusual bytes readable as itself rather than as
# a C-escaped string the path patterns would then miss.
#
# The ROOT commit is included. It has no first parent, so a per-commit `git diff "$sha^1"` form
# cannot take it and the first version of this file skipped it by name — which dropped the very
# landing that introduced the TypeScript router, `dc63c60`, 7 files under `src/`. `git log`
# reports a root commit against the empty tree, so this form takes it and the census is one row
# larger and one row more honest.
#
# `\001` introduces a header line and separates the sha from the subject. A path could in principle
# contain that byte; none in this repository does, and the sha is length-checked below, so a header
# line that is really a path is dropped rather than mistaken for a landing.
census="$(git -c core.quotePath=false log --first-parent -m --name-only \
            --format="%x01%H%x01%s" "$REV" \
  | awk -v swift_re="$SWIFT_RE" -v ts_re="$TS_RE" '
      function flush() {
        if (sha == "" || (swift == 0 && ts == 0)) return
        carrier = (swift > 0 && ts > 0) ? "both" : (swift > 0 ? "swift-only" : "typescript-only")
        printf "%s\t%s\t%s\t%s\t%s\n", sha, subject, carrier, swift, ts
      }
      /^\001/ {
        flush()
        rest = substr($0, 2)
        p = index(rest, "\001")
        sha = (p ? substr(rest, 1, p - 1) : rest)
        subject = (p ? substr(rest, p + 1) : "")
        if (length(sha) != 40) { sha = "" }
        swift = 0; ts = 0
        next
      }
      $0 == "" { next }
      { if ($0 ~ swift_re) swift++; else if ($0 ~ ts_re) ts++ }
      END { flush() }
    ')"

rows=0
while IFS=$'\t' read -r sha subject carrier swift ts; do
  [ -z "${sha:-}" ] && continue
  # The label is the branch or item name the landing announced itself under, which is what a
  # reader recognises. It is a convenience: the sha is the key, and the gate joins on the sha.
  label="$(printf '%s\n' "$subject" \
    | sed -E "s/:.*\$//; s/^Merge +//; s/^branch +'([^']*)'/\\1/; s|^ai/||" \
    | cut -c1-48)"
  [ -z "$label" ] && label='-'
  printf 'landing\t%s\t%s\t%s\t%s\t%s\n' "$sha" "$label" "$carrier" "$swift" "$ts"
  rows=$((rows + 1))
done <<< "$census"

if [ "$rows" -eq 0 ]; then
  echo "environment: $REV yielded no landing that touched either router. This repository has held" >&2
  echo "             both implementations since R1, so that is a broken walk and not an empty" >&2
  echo "             history." >&2
  exit 2
fi

exit 0
