#!/usr/bin/env bash
#
# G32 — the two spellings of a worktree's own path, refused before a build rather than after one.
#
# `<home>/Dev/mcp-router/.worktrees` is a symlink onto another volume, so every worktree has two
# names for itself: the logical `<home>/Dev/mcp-router/.worktrees/<ID>` a runner cd's into, and the
# physical `<volume>/Dev/mcp-router/.worktrees/<ID>` the OS resolves it to. Two toolchains read that
# differently, and NEITHER failure mentions a symlink. Both cost real time in Wave B.
#
# ## The node half — sixty type errors that are one missing directory
#
# The documented worktree convention is to symlink `node_modules` to the main checkout. Written the
# obvious way that is `ln -s ../../node_modules node_modules`, and a relative link is resolved
# PHYSICALLY: from `<volume>/Dev/mcp-router/.worktrees/<ID>`, `../../` is `<volume>/Dev/mcp-router/`,
# which holds `.worktrees` and nothing else. Measured 2026-08-27:
#
#     $ ls <volume>/Dev/mcp-router/
#     .worktrees
#
# So the link dangles, and `npm run build` reports it as ~60 `Cannot find module 'node:os'` and
# `Cannot find name 'process'` errors — the exact shape of a broken `tsconfig`, which is where the
# next hour goes.
#
# The repair here is an ABSOLUTE link, and that is not a shortcut. The main checkout lives under
# the home directory and the worktree physically on the other volume; below `/` the two trees
# share no ancestor at all. There is therefore NO relative path from a worktree that
# reaches the main checkout's `node_modules` — relative is not fragile here, it is unrepresentable.
# The absolute target is COMPUTED from `git rev-parse --git-common-dir` on every run rather than
# written down, so nothing here is pinned to one machine, and `.gitignore` ignores `node_modules`
# under both the trailing-slash and the bare spelling (a hard-coded one was committed once), so the
# link cannot enter a branch.
#
# Why link rather than `npm install` per worktree: the install is 49 MB and there are 24 live
# worktrees, so installing costs ~1.2 GB and an install step to save a symlink. The one thing a
# shared install cannot cover is a branch that changes its dependencies, so the lockfiles are
# compared and a difference is reported rather than assumed away.
#
# ## The swift half — a compiler segfault that is one `$PWD`
#
# `swift-frontend` resolves a relative `-module-cache-path` against `$PWD`, NOT against `getcwd()`.
# Measured 2026-08-27 with a two-line `import Foundation` file, one shared cache, cwd held constant
# and only `PWD` changed:
#
#     PWD=<logical spelling>   -module-cache-path mc   -> rc=0
#     PWD=<physical spelling>  -module-cache-path mc   -> rc=139 (SIGSEGV), preceded by
#       error: module '_DarwinFoundation1' is defined in both
#         '<logical>/mc/1T2R8I3HT0CL9/_DarwinFoundation1-2YSBQADOLX02V.pcm' and
#         '<physical>/mc/1T2R8I3HT0CL9/_DarwinFoundation1-2YSBQADOLX02V.pcm'
#
# Those two paths are the SAME FILE — same hash directory, same name. Only the spelling differs.
#
# The duality itself is removed in the Makefile (`export PWD := $(CURDIR)`, and make's `CURDIR` is
# already the physical spelling), so nothing make drives can produce a second spelling. What that
# cannot fix is a cache POPULATED BEFORE the change, or a `swift test` a runner types by hand in
# `app/`. Measured on a live worktree the same evening: `G16`'s module caches hold 237 files
# recording the logical spelling and 0 recording the physical one, so its first canonical build
# segfaults.
# This script refuses that build and names the cause, which is the whole of the ask.
#
# The spelling is recorded per cache root in `.path-spelling`, beside the cache and inside the
# throwaway build directory that `make clean` deletes. A stamp is compared, never trusted: an
# EXISTING non-empty cache with NO stamp is unknown provenance, and unknown provenance is refused
# rather than passed — a check that could not run is not a check that passed.
#
# Reading the spelling out of the cache instead was measured and rejected on cost: the strings are
# there (`grep -rlF` finds them), but G16's two module caches are 368 MB and a full scan is 4.7 s
# on every `make lint`. The stamp answers the same question in one `cat`.
#
# Modes: `node` (what `npm run build` needs) · `swift` (what a compile needs) · `all` (default).
# Exit: 0 clear · 1 refused, with the cause named · 2 the environment could not be read.
set -uo pipefail

MODE="${1:-all}"
case "$MODE" in node|swift|all) ;; *) echo "usage: $0 [node|swift|all]" >&2; exit 2 ;; esac

# The physical spelling of this checkout, which is the one canonical name it has.
PHYS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)" || { echo "error: cannot resolve the repo root" >&2; exit 2; }

# The spelling the toolchain will actually record. Measured above: it is `$PWD`, not `getcwd()`.
# Walk up from `$PWD` to whichever prefix names this same physical root, so being called from
# `app/` or from `scripts/` still reports the root's spelling rather than a subdirectory's.
build_spelling() {
  local p="${PWD:-}"
  while [ -n "$p" ] && [ "$p" != "/" ]; do
    if [ "$(cd "$p" 2>/dev/null && pwd -P)" = "$PHYS_ROOT" ]; then printf '%s\n' "$p"; return 0; fi
    p="$(dirname "$p")"
  done
  printf '%s\n' "$PHYS_ROOT"
}
SPELL="$(build_spelling)"

# The OTHER spelling this directory answers to, established rather than assumed: git records a
# worktree by its physical path and the common dir by its logical one, so neither alone shows the
# duality. `<main checkout>/.worktrees/<name>` is the layout, and it is CHECKED to resolve back to
# this same physical root before being reported — a message that prints one spelling twice is the
# one line in it that had a job to do.
other_spelling() {
  local common main cand
  common="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 1
  main="$(dirname "$common")"
  cand="$main/.worktrees/$(basename "$PHYS_ROOT")"
  [ -d "$cand" ] || return 1
  [ "$(cd "$cand" 2>/dev/null && pwd -P)" = "$PHYS_ROOT" ] || return 1
  [ "$cand" = "$PHYS_ROOT" ] && return 1
  printf '%s\n' "$cand"
}
OTHER="$(other_spelling || true)"

note() { printf '%s\n' "$*" >&2; }

fail() { echo "$@" >&2; }
rc=0

# ---------------------------------------------------------------- node_modules
preflight_node() {
  local common main
  common="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || {
    fail "worktree-preflight: not a git checkout — cannot locate the main checkout."; return 2; }
  main="$(dirname "$common")"
  [ -d "$main" ] || { fail "worktree-preflight: the main checkout '$main' does not exist."; return 2; }

  # In the main checkout there is nothing to link; a missing install is the runner's own `npm i`.
  if [ "$(cd "$main" && pwd -P)" = "$PHYS_ROOT" ]; then
    [ -d "$PHYS_ROOT/node_modules" ] && return 0
    fail "worktree-preflight: node_modules is missing in the main checkout. Run: npm install"
    return 1
  fi

  if [ -d "$PHYS_ROOT/node_modules" ]; then
    :  # resolves — a real install or a link that works. Leave it exactly as it is.
  else
    # A symlink that does not resolve to a directory is the trap, and it is an ignored file, so
    # replacing it changes nothing a branch can see. A REAL directory is never touched.
    if [ -L "$PHYS_ROOT/node_modules" ]; then
      echo "worktree-preflight: node_modules -> $(readlink "$PHYS_ROOT/node_modules") does not resolve."
      echo "                    '.worktrees' is a symlink onto another volume, so a relative link is"
      echo "                    resolved physically and lands outside the main checkout. Repointing it."
      rm -f "$PHYS_ROOT/node_modules"
    fi
    if [ ! -d "$main/node_modules" ]; then
      fail "worktree-preflight: no node_modules to share — '$main/node_modules' does not exist."
      fail "                    Run 'npm install' in $main, then build again."
      return 1
    fi
    ln -s "$main/node_modules" "$PHYS_ROOT/node_modules" || {
      fail "worktree-preflight: could not create the node_modules link."; return 2; }
    echo "worktree-preflight: node_modules -> $main/node_modules (absolute: the worktree's physical"
    echo "                    parent chain does not contain the main checkout, so no relative path reaches it)"
  fi

  # The one thing a shared install cannot cover.
  if [ -f "$PHYS_ROOT/package-lock.json" ] && [ -f "$main/package-lock.json" ] \
     && ! cmp -s "$PHYS_ROOT/package-lock.json" "$main/package-lock.json"; then
    echo "worktree-preflight: NOTE this branch's package-lock.json differs from the main checkout's,"
    echo "                    and node_modules is the main checkout's install. Run 'npm install' here"
    echo "                    if this branch changed a dependency."
  fi

  # `dist` is build OUTPUT, not shared input: `tsc` writes THROUGH a symlink, so a worktree whose
  # `dist` points at another checkout silently overwrites that checkout's build with this branch's.
  if [ -L "$PHYS_ROOT/dist" ]; then
    local t; t="$(cd "$(dirname "$PHYS_ROOT/dist")" && cd "$(readlink "$PHYS_ROOT/dist")" 2>/dev/null && pwd -P)" || t=""
    if [ -n "$t" ] && [ "${t#"$PHYS_ROOT"}" = "$t" ]; then
      echo "worktree-preflight: WARNING dist -> $t leaves this worktree. 'npm run build' writes through"
      echo "                    a symlink, so building here overwrites that checkout's dist with this"
      echo "                    branch's output. Drive a foreign reference with MCP_ROUTER_DIST instead."
    fi
  fi
  return 0
}

# ------------------------------------------------------------ module-cache spelling
preflight_swift() {
  local root ret=0
  for root in "$PHYS_ROOT/app/.derived" "$PHYS_ROOT/app/.build"; do
    [ -d "$root" ] || continue
    local stamp="$root/.path-spelling" populated=0 mc
    while IFS= read -r mc; do
      [ -n "$mc" ] || continue
      if [ -n "$(find "$mc" -type f -name '*.pcm' -print -quit 2>/dev/null)" ]; then populated=1; break; fi
    done < <(find "$root" -maxdepth 4 -type d -name 'ModuleCache*' 2>/dev/null)

    if [ "$populated" = 0 ]; then
      printf '%s\n' "$SPELL" > "$stamp" 2>/dev/null || true   # empty cache: record what fills it
      continue
    fi

    local was=""
    [ -f "$stamp" ] && was="$(cat "$stamp" 2>/dev/null)"
    if [ "$was" = "$SPELL" ]; then continue; fi

    # No stamp means this cache predates the check. Refusing there blocks every cache that
    # already existed, once, including in the main checkout where the duality cannot occur —
    # and it did: the first `make lint` after this guard landed died at `tools` over a cache
    # holding one spelling and no second one anywhere in it. An unknown is not a failure, and
    # here it is cheap to MEASURE rather than default: the cache's own bytes name the spellings
    # it was filled under. So adopt a cache that demonstrably holds only this spelling, and keep
    # refusing one that holds both — which is the condition the segfault actually comes from.
    if [ -z "$was" ] && [ -n "$PHYS_ROOT" ]; then
      local found_phys=0 found_other=0
      grep -rlqs -- "$PHYS_ROOT" "$root" 2>/dev/null && found_phys=1
      if [ -n "$OTHER" ]; then
        grep -rlqs -- "$OTHER" "$root" 2>/dev/null && found_other=1
      fi
      if [ "$found_phys" -eq 1 ] && [ "$found_other" -eq 0 ] && [ "$SPELL" = "$PHYS_ROOT" ]; then
        printf '%s' "$SPELL" > "$stamp" 2>/dev/null || true
        note "worktree-preflight: adopted the existing module cache under"
        note "  $root"
        note "It holds only $PHYS_ROOT and no second spelling, so its provenance is measured"
        note "rather than unknown. Stamped; a later build under the other spelling still refuses."
        continue
      fi
    fi

    fail "worktree-preflight: REFUSING to build — the Swift module cache under"
    fail "  $root"
    if [ -n "$was" ]; then
      fail "was built with PWD spelled"
      fail "  $was"
      fail "and this build spells the same directory"
      fail "  $SPELL"
    else
      fail "was built before this check existed, so which of the two spellings it holds is unknown,"
      fail "and unknown provenance is not a pass. This build spells the directory"
      fail "  $SPELL"
    fi
    fail ""
    fail "CAUSE: '.worktrees' is a symlink, so this ONE directory answers to two names:"
    fail "  physical  $PHYS_ROOT"
    if [ -n "$OTHER" ]; then
      fail "  through the symlink  $OTHER"
    else
      fail "  (the second spelling could not be established from this checkout — see .worktrees)"
    fi
    fail "and this build is using  $SPELL"
    fail "swift-frontend resolves a relative -module-cache-path against \$PWD, so a cache filled"
    fail "under one spelling and read under the other reports"
    fail "  error: module '_DarwinFoundation1' is defined in both '…' and '…'"
    fail "naming one file twice, and then exits with SIGSEGV. That segfault is this, and nothing"
    fail "in it mentions a symlink."
    fail ""
    fail "FIX: discard the cache — it is build output and costs a rebuild, nothing else."
    fail "  rm -rf $root"
    fail "Builds driven through 'make' cannot reach this state: the Makefile pins PWD to CURDIR."
    ret=1
  done
  return $ret
}

case "$MODE" in
  node)  preflight_node  || rc=$? ;;
  swift) preflight_swift || rc=$? ;;
  all)   preflight_node  || rc=$?
         preflight_swift || { s=$?; [ "$s" -gt "$rc" ] && rc=$s; } ;;
esac
exit $rc
