#!/bin/bash
# Prove `planning/hooks/pre-commit` fires, and prove each direction is capable of failing.
#
# The README claims the hook was "proved in four directions before being trusted". That proof was
# a one-off nobody can re-run — the shape G6 filed: a verdict sound when given and unfalsifiable
# now. This re-runs it over the TRACKED hook, in throwaway repositories, on every invocation.
# Nothing is planted in the real repository and the hook's sha256 is reported before and after.
#
# Two directions carry a presence control, because an absence check cannot detect its own
# blindness. D4 is run twice — against the tracked hook, which must REFUSE, and against a
# reconstructed pre-G9 hook, which must ALLOW. D6 is run twice for the same reason. If a control
# arm agrees with the treated arm, the plant never reached the mechanism and this exits 2 rather
# than printing a pass: an assertion that cannot fail has measured nothing, whatever it prints.
#
# Exit 0 all directions hold; 1 a direction failed; 2 a presence control did not fire.

set -u
ROOT=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
HOOK="$ROOT/planning/hooks/pre-commit"
[ -f "$HOOK" ] || { echo "FATAL: no hook at $HOOK"; exit 2; }

HOOK_SHA=$(shasum -a 256 "$HOOK" | cut -d' ' -f1)
echo "hook under test : planning/hooks/pre-commit"
echo "sha256 before   : $HOOK_SHA"

grep -q '^git_dir=\$(git rev-parse --absolute-git-dir)' "$HOOK" || {
    echo "FATAL: the tracked hook does not read --absolute-git-dir; D4's control strips that line."; exit 2; }
grep -q '^unset GIT_DIR GIT_WORK_TREE$' "$HOOK" || {
    echo "FATAL: the tracked hook has no bare 'unset GIT_DIR GIT_WORK_TREE' line; D6's control strips it."; exit 2; }

TMP=$(mktemp -d "${TMPDIR:-/tmp}/g9-prove.XXXXXX") || exit 2
trap 'rm -rf "$TMP"' EXIT

build() {   # build <dir> <hook-file> — a main checkout on `main` plus one linked worktree
    local d=$1 h=$2
    mkdir -p "$d"
    git init -q -b main "$d/co"
    git -C "$d/co" config user.email prove@local; git -C "$d/co" config user.name prove
    echo seed > "$d/co/seed"; git -C "$d/co" add seed
    git -C "$d/co" -c core.hooksPath=/dev/null commit -q -m seed
    install -m 0755 "$h" "$d/co/.git/hooks/pre-commit"
    git -C "$d/co" worktree add -q "$d/wt" -b runner
}

# try <cwd> [env...] -> ALLOWED | REFUSED | ERROR:<code>
#
# The verdict is read from the HOOK'S OWN refusal text, not from git's exit code. An earlier cut
# read the exit code, and every failure looked like a refusal: `GIT_DIR` redirected at a worktree
# leaves nothing staged in that worktree's index, so `git commit` exits 1 with "nothing to
# commit" and the hook never speaks. That reported a direction as REFUSED which the hook had not
# even seen. A verdict that cannot separate its cases is not a verdict.
#
# The env is applied to `add` as well as `commit`, because a caller who exported it would have
# it exported for both, and staging into the wrong index is half of what the env does.
try() {
    local cwd=$1; shift
    date +%s%N > "$cwd/probe.$$"
    # The probe must land in the EFFECTIVE work tree, or `add` stages nothing and the direction
    # reports ERROR:nothing-staged having tested no hook at all. A caller who exports
    # GIT_WORK_TREE edits files in that tree; reproduce that rather than a tree it never touches.
    local e; for e in "$@"; do case "$e" in GIT_WORK_TREE=*) date +%s%N > "${e#GIT_WORK_TREE=}/probe.$$" ;; esac; done
    ( cd "$cwd" && env "$@" git add -A ) >/dev/null 2>&1
    local out rc
    out=$( cd "$cwd" && env "$@" git commit -m probe 2>&1 ); rc=$?
    if [ $rc -eq 0 ]; then echo ALLOWED
    elif printf '%s' "$out" | grep -q 'commit refused'; then echo REFUSED
    elif printf '%s' "$out" | grep -qi 'nothing to commit\|no changes added'; then echo ERROR:nothing-staged
    else echo "ERROR:git-rc-$rc"; fi
}

fails=0
check() {   # check <label> <expected> <actual>
    if [ "$2" = "$3" ]; then printf '  ok    %-56s %s\n' "$1" "$3"
    else printf '  FAIL  %-56s expected %s, got %s\n' "$1" "$2" "$3"; fails=$((fails+1)); fi
}

echo
echo "=== the tracked hook (a fresh repository per direction) ==="
n=0
fresh() { n=$((n+1)); F="$TMP/d$n"; build "$F" "$HOOK"; }

fresh; check "D1 on main, main checkout, clean env"            REFUSED "$(try "$F/co")"
fresh; check "D2 on main, main checkout, orchestrator"         ALLOWED "$(try "$F/co" MCPR_ORCHESTRATOR=1)"
fresh; check "D3 in a runner's own worktree"                   ALLOWED "$(try "$F/wt")"
fresh; check "D4 on main, GIT_WORK_TREE aimed at the worktree" REFUSED "$(try "$F/co" "GIT_WORK_TREE=$F/wt")"
D4REPO=$F
check "D4b …and main did not move"                            seed    "$(git -C "$D4REPO/co" log --oneline -1 --format=%s main)"

# D5 is an expected ALLOW, recorded so that nobody later "closes" it. With GIT_DIR aimed at the
# worktree, git REDIRECTS the whole commit there: it lands on `runner`, not on `main`, so there is
# no commit on the integration branch to refuse and allowing it is the correct verdict. D5b is the
# assertion that carries the claim — main must still be at `seed`.
fresh; check "D5 on main, GIT_DIR redirected to the worktree"  ALLOWED "$(try "$F/co" "GIT_DIR=$F/co/.git/worktrees/wt")"
check "D5b …the commit landed on runner, not main"            "seed|probe" \
      "$(git -C "$F/co" log --oneline -1 --format=%s main)|$(git -C "$F/co" log --oneline -1 --format=%s runner)"

echo
echo "=== D6 what a descendant inherits (a worktree commit, where git exports GIT_DIR) ==="
git init -q -b main "$TMP/elsewhere"
for variant in with-unset without-unset; do
    { echo '#!/bin/sh'
      [ "$variant" = with-unset ] && echo 'unset GIT_DIR GIT_WORK_TREE'
      echo "cd \"$TMP/elsewhere\" && git rev-parse --absolute-git-dir > \"$TMP/d6.$variant\""
      echo 'exit 1'; } > "$D4REPO/co/.git/hooks/pre-commit"
    chmod +x "$D4REPO/co/.git/hooks/pre-commit"
    try "$D4REPO/wt" >/dev/null
done
d6_with=$(cat "$TMP/d6.with-unset" 2>/dev/null)
d6_without=$(cat "$TMP/d6.without-unset" 2>/dev/null)
echo "  a child standing in $TMP/elsewhere resolved:"
echo "    without unset : $d6_without"
echo "    with unset    : $d6_with"
case "$d6_without" in *"/co/.git/worktrees/"*) leaked=LEAKED ;; *) leaked=clean ;; esac
case "$d6_with"    in *"/elsewhere/.git")      held=HELD     ;; *) held=leaked ;; esac
check "D6a without the unset, the child inherits the committer's repo" LEAKED "$leaked"
check "D6b with the unset, the child resolves its own"                 HELD   "$held"
[ "$leaked" = LEAKED ] || { echo "  CONTROL DID NOT FIRE — D6b is not evidence, nothing leaked to stop."; exit 2; }

echo
echo "=== presence control for D4: the pre-G9 hook must let the bypass through ==="
CTRL="$TMP/pre-commit.preg9"
sed -e 's|^git_dir=\$(git rev-parse --absolute-git-dir) .*|git_dir=$(git rev-parse --git-dir)|' \
    -e 's|^branch=\$(git --git-dir="\$git_dir" symbolic-ref|branch=$(git symbolic-ref|' \
    -e 's|\*/\.git/worktrees/\*|*/worktrees/*|' "$HOOK" > "$CTRL"
chmod +x "$CTRL"
cmp -s "$CTRL" "$HOOK" && { echo "  FATAL: the strip changed nothing"; exit 2; }
sh -n "$CTRL" || { echo "  FATAL: the reconstructed pre-G9 hook does not parse"; exit 2; }
B="$TMP/b"; build "$B" "$CTRL"
ctrl_d4=$(try "$B/co" "GIT_WORK_TREE=$B/wt")
ctrl_d1=$(try "$B/co")
echo "  pre-G9 hook, D4 (the bypass) : $ctrl_d4   [must be ALLOWED, or D4 proves nothing]"
echo "  pre-G9 hook, D1 (plain main) : $ctrl_d1   [must be REFUSED, or the plant broke the hook]"
if [ "$ctrl_d4" != ALLOWED ] || [ "$ctrl_d1" != REFUSED ]; then
    echo "  CONTROL DID NOT FIRE — D4 above is not evidence."; exit 2
fi
echo "  control fired: the bypass existed before G9 and does not now."

echo
after=$(shasum -a 256 "$HOOK" | cut -d' ' -f1)
echo "sha256 after    : $after"
[ "$after" = "$HOOK_SHA" ] || { echo "FATAL: the hook changed during the run"; exit 2; }

echo
if [ "$fails" -eq 0 ]; then echo "PASS  8 assertions over 6 directions, 2 presence controls fired"; exit 0
else echo "FAIL  $fails direction(s)"; exit 1; fi
