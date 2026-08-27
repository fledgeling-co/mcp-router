#!/usr/bin/env bash
#
# G32 — can `worktree-preflight.sh` actually refuse?
#
# The guard it tests exists to stop two failures that name nothing: sixty TypeScript errors that
# are one dangling symlink, and a `clang: Segmentation fault: 11` that is one `$PWD`. A guard for
# a trap that costs an hour is worth exactly as much as its ability to go red, so every plant here
# is a tree broken THE WAY THE TRAP BREAKS IT, and the passes are asserted too — a check that
# refuses everything is not a check.
#
# The topology is rebuilt rather than described, because the trap IS the topology:
#
#     $W/real/                 the main checkout (a real git repo)
#     $W/vol/.worktrees/       where worktrees physically live
#     $W/real/.worktrees   ->  $W/vol/.worktrees      the symlink, exactly as ~/Dev has it
#
# `$W` is resolved with `pwd -P` first, because `mktemp -d` on macOS hands back a path under
# `/var`, which is itself a symlink to `/private/var` — a second duality would make a plant pass
# for the wrong reason.
#
# P3 is the discriminator. It is a cache populated before the guard existed, which is the state
# every live worktree is in right now: measured 2026-08-27, `G16`'s two module caches hold 237
# files recording the `/Users/…` spelling and 0 recording `/Volumes/…`. Passing unknown provenance
# would let exactly that build through to the segfault.
#
# Exit: 0 every case held · 1 a case did not hold · 2 the environment could not run one.
set -uo pipefail

GUARD_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/worktree-preflight.sh"
[ -f "$GUARD_SRC" ] || { echo "selftest: no guard at $GUARD_SRC" >&2; exit 2; }
command -v git >/dev/null 2>&1 || { echo "selftest: git is not on PATH" >&2; exit 2; }

W="$(cd "$(mktemp -d -t g32-preflight)" && pwd -P)" || exit 2
trap 'rm -rf "$W"' EXIT
pass=0; failed=0

ok()   { echo "  ok   $1"; pass=$((pass+1)); }
bad()  { echo "  FAIL $1"; failed=$((failed+1)); }

# Rebuild the whole topology from scratch for each plant, so no case inherits another's repair.
fresh_tree() { # $1 = "with-node-modules" | "no-node-modules"
  rm -rf "$W/real" "$W/vol"
  mkdir -p "$W/real/scripts" "$W/vol/.worktrees"
  ln -s "$W/vol/.worktrees" "$W/real/.worktrees"
  cp "$GUARD_SRC" "$W/real/scripts/worktree-preflight.sh"
  chmod +x "$W/real/scripts/worktree-preflight.sh"
  printf '{"name":"t","version":"0.0.0"}\n' > "$W/real/package.json"
  git -C "$W/real" init -q -b main
  git -C "$W/real" -c user.email=t@t -c user.name=t add -A >/dev/null
  git -C "$W/real" -c user.email=t@t -c user.name=t commit -qm base
  [ "$1" = "with-node-modules" ] && mkdir -p "$W/real/node_modules/typescript"
  git -C "$W/real" worktree add -q -b wt "$W/real/.worktrees/T1" main
}

LOG="$W/real/.worktrees/T1"   # the logical spelling, through the symlink
PHY="$W/vol/.worktrees/T1"    # the physical spelling

guard() { # $1=spelling $2=mode ; prints output, sets GRC
  local out
  out="$(cd "$1" && PWD="$1" bash scripts/worktree-preflight.sh "$2" 2>&1)"; GRC=$?
  GOUT="$out"
}

echo "worktree-preflight-selftest: $W"

# ---- P1  the trap itself: the relative link a runner would naturally write ----------------
fresh_tree with-node-modules
ln -s ../../node_modules "$PHY/node_modules"
if [ -d "$PHY/node_modules" ]; then
  bad "P1 setup — the relative link resolved, so this machine is not reproducing the trap"
else
  ok "P1 red before: node_modules -> ../../node_modules does not resolve (this is the ~60-error state)"
fi
guard "$LOG" node
if [ "$GRC" = 0 ] && [ -d "$PHY/node_modules" ] \
   && [ "$(readlink "$PHY/node_modules")" = "$W/real/node_modules" ]; then
  ok "P1 green after: the guard repointed it at the main checkout, absolutely"
else
  bad "P1 the guard did not repair the dangling link (rc=$GRC, link=$(readlink "$PHY/node_modules" 2>/dev/null))"
fi
# P1b — the repair is only half the product; the sentence saying WHY is the other half, and the
# first version of it shipped with a dropped closing quote, so the second line printed as
# `      echo  resolved physically and lands…`. P1 read the symlink and never read the message.
if printf '%s' "$GOUT" | grep -q "is a symlink onto another volume" \
   && printf '%s' "$GOUT" | grep -q "no relative path reaches it" \
   && ! printf '%s' "$GOUT" | grep -qE '^ *echo '; then
  ok "P1b the repair explained itself, and no line of it leaked its own 'echo'"
else
  bad "P1b the repair message is malformed or does not say why: $GOUT"
fi

# ---- P2  nothing to share: the guard must refuse, not link into thin air ------------------
fresh_tree no-node-modules
guard "$LOG" node
if [ "$GRC" = 1 ] && printf '%s' "$GOUT" | grep -q "does not exist" \
   && printf '%s' "$GOUT" | grep -qF "$W/real"; then
  ok "P2 refused with no node_modules anywhere, and named the checkout to install in"
else
  bad "P2 expected rc=1 naming $W/real, got rc=$GRC: $GOUT"
fi

# ---- P3  the discriminator: a cache populated before the guard existed --------------------
fresh_tree with-node-modules
mkdir -p "$PHY/app/.derived/ModuleCache.noindex/1T2R8I3HT0CL9"
: > "$PHY/app/.derived/ModuleCache.noindex/1T2R8I3HT0CL9/_DarwinFoundation1-2YSBQADOLX02V.pcm"
guard "$LOG" swift
if [ "$GRC" = 1 ] && printf '%s' "$GOUT" | grep -q "REFUSING" \
   && printf '%s' "$GOUT" | grep -q "symlink" \
   && printf '%s' "$GOUT" | grep -q "unknown"; then
  ok "P3 refused an unstamped populated cache, and named the symlink rather than the segfault"
else
  bad "P3 expected rc=1 naming the symlink, got rc=$GRC: $GOUT"
fi
# P3b — the message must print BOTH names of the directory. The first version derived the second
# spelling from `$PWD`, so under `make` (which pins PWD to CURDIR) it printed the physical path
# twice under two labels: the one line that had a job to do, doing none of it.
if printf '%s' "$GOUT" | grep -qF "$PHY" && printf '%s' "$GOUT" | grep -qF "$LOG" && [ "$PHY" != "$LOG" ]; then
  ok "P3b the refusal printed both spellings of the one directory, not one of them twice"
else
  bad "P3b the refusal did not name both spellings ($PHY / $LOG): $GOUT"
fi

# ---- P4  the cache was filled under the other spelling --------------------------------------
fresh_tree with-node-modules
mkdir -p "$PHY/app/.build/arm64-apple-macosx/debug/ModuleCache/AB01PAR4CKS6"
: > "$PHY/app/.build/arm64-apple-macosx/debug/ModuleCache/AB01PAR4CKS6/_DarwinFoundation1-2YSBQADOLX02V.pcm"
printf '%s\n' "$LOG" > "$PHY/app/.build/.path-spelling"
guard "$PHY" swift
if [ "$GRC" = 1 ] && printf '%s' "$GOUT" | grep -qF "$LOG" && printf '%s' "$GOUT" | grep -qF "$PHY"; then
  ok "P4 refused a cache stamped with the other spelling, and printed both spellings"
else
  bad "P4 expected rc=1 printing both spellings, got rc=$GRC: $GOUT"
fi

# ---- P5  the same cache, the spelling it was built with: must PASS --------------------------
printf '%s\n' "$PHY" > "$PHY/app/.build/.path-spelling"
guard "$PHY" swift
if [ "$GRC" = 0 ]; then
  ok "P5 passed the same populated cache under the spelling that filled it"
else
  bad "P5 a matching stamp was refused (rc=$GRC): $GOUT"
fi

# ---- P6  an empty cache is not a poisoned one, and gets stamped -----------------------------
fresh_tree with-node-modules
mkdir -p "$PHY/app/.derived/ModuleCache.noindex"
guard "$PHY" swift
if [ "$GRC" = 0 ] && [ "$(cat "$PHY/app/.derived/.path-spelling" 2>/dev/null)" = "$PHY" ]; then
  ok "P6 an empty cache passed and was stamped with the spelling about to fill it"
else
  bad "P6 expected rc=0 and a stamp of $PHY, got rc=$GRC stamp=$(cat "$PHY/app/.derived/.path-spelling" 2>/dev/null)"
fi

# ---- P7  the main checkout has no duality and must be silent --------------------------------
fresh_tree with-node-modules
out="$(cd "$W/real" && PWD="$W/real" bash scripts/worktree-preflight.sh all 2>&1)"; grc=$?
if [ "$grc" = 0 ] && [ -z "$out" ]; then
  ok "P7 the main checkout passed silently — no link made, nothing said"
else
  bad "P7 expected a silent rc=0 in the main checkout, got rc=$grc: $out"
fi

# ---- P8  a REAL node_modules in a worktree is never deleted ---------------------------------
fresh_tree with-node-modules
mkdir -p "$PHY/node_modules/mine"; : > "$PHY/node_modules/mine/keep.txt"
guard "$LOG" node
if [ "$GRC" = 0 ] && [ -f "$PHY/node_modules/mine/keep.txt" ] && [ ! -L "$PHY/node_modules" ]; then
  ok "P8 a real node_modules directory was left exactly as it was"
else
  bad "P8 the guard disturbed a real node_modules (rc=$GRC)"
fi

echo "worktree-preflight-selftest: $pass held, $failed did not"
[ "$failed" -eq 0 ] || exit 1
exit 0
