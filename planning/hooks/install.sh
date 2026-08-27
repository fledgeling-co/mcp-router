#!/bin/bash
# Install the tracked fleet hooks into .git/hooks, or check the installed copies against them.
#
#   planning/hooks/install.sh           install, then report each sha256
#   planning/hooks/install.sh --check   report drift only; exit 1 if any copy differs or is absent
#   planning/hooks/install.sh --gate    the same reading, scoped so `make lint` can carry it
#
# `.git/hooks` is not tracked, so the tracked files here are the source of record and the
# installed copies are derived state that can drift from them without anything going red. That is
# the same shape as the defect this item exists for (G9): a control that is believed armed, and
# nothing checks. `--check` is the thing that was missing — the README's `cp` line told a fresh
# clone how to install and gave it no way to find out afterwards whether it had worked.
#
# The repository root is derived, never pinned.
#
# `.git/hooks` is shared by every linked worktree, so installing from inside one changes the
# controls under every runner in flight. Run this from the orchestrating session.
#
# WHY `--gate` EXISTS, AND WHY IT IS NOT JUST `--check`. Measured 2026-08-27 (G9).
#
# `--check` was written and then invoked by nothing: no Makefile target, no goals script, no hook.
# That is G9's own finding one layer up — the item's brief says of the two dead R2 scripts "nothing
# went red, because nothing invoked them", and the drift detector built to stop a control going
# silently stale was itself a control nothing ran. It is how the hook reached a third hand-off
# still uninstalled: two verifiers recorded the gap, and no instrument could.
#
# `--check` cannot go into `make lint` as it stands, because `.github/workflows/swift.yml` runs
# `make lint` on a fresh `actions/checkout@v4` clone, where `.git/hooks` holds only the samples.
# `--check` reds on ABSENT, so wiring it in would turn CI permanently red for a reason that has
# nothing to do with the tree — the failure mode that workflow's own Xcode comment warns against.
#
# So `--gate` separates the two states `--check` conflates, because only one of them is a lie:
#
#   DRIFTED  — an installed copy that silently disagrees with the tracked source. This is the
#              defect itself: an edited tracked hook and a stale installed copy are indistinguishable
#              from outside, so the control is believed armed while a different one runs. Always red.
#   ABSENT   — nothing was ever installed, so nothing is claiming to be armed. Red only where a
#              fleet is relying on it, which is exactly where the hook has a job: it exists to tell
#              the main checkout apart from linked worktrees. With no linked worktrees there is no
#              shared checkout to protect and no runner to distinguish.
#
# The discriminator is counted, not sniffed: linked worktrees, from `git worktree list`. Measured
# the same day — a fresh clone of this repo reports 1 worktree and no installed hooks, this
# checkout reports 29. NOT EXECUTABLE stays red in every mode: that is an installed hook which
# cannot run, which is the believed-armed shape again.

set -u
ROOT=$(git -C "$(dirname "$0")" rev-parse --show-toplevel) || { echo "FATAL: not in a checkout"; exit 2; }
SRC="$ROOT/planning/hooks"
DEST=$(git -C "$ROOT" rev-parse --git-common-dir)/hooks
case "$DEST" in /*) ;; *) DEST="$ROOT/$DEST" ;; esac

mode=install
case "${1-}" in
    --check) mode=check ;;
    --gate)  mode=gate  ;;
esac

# Linked worktrees, not total: `git worktree list` always names the main checkout first.
linked=$(( $(git -C "$ROOT" worktree list --porcelain | grep -c '^worktree ') - 1 ))

# ---------------------------------------------------------------------------------------------
# Presence control. Runs on every `--gate`, never behind a flag, because `--gate` reports an
# ABSENCE — no drift — and an absence check that has never been shown to fire returns zero for
# reasons it cannot tell apart. It plants all five states in throwaway repositories under
# `mktemp -d` and never touches this one. If any plant reads wrong, no verdict is printed and the
# exit is 2, distinct from 1 (drift found) and 0 (clean), so a rotted control cannot wear a
# findings code — the defect `G8`'s gap-fix closed and `G9`'s own control arm reintroduced once.
#
# The inner `--gate` runs with MCPR_HOOKGATE_CONTROL set, which is what stops it recursing.
control() {
    local t plant got name expected read_ n
    got=""
    for plant in sync drift absent_solo absent_fleet notexec; do
        t=$(mktemp -d) || { echo "  control could not create a scratch dir"; return 2; }
        # The repository goes in a subdirectory and the linked worktree beside it, both INSIDE $t.
        # An earlier draft used `git worktree add ../wt`, which from the repo root resolved to the
        # shared temp PARENT: the first run created it and every run afterwards silently failed to,
        # so absent_fleet read EXEMPT and the control passed once and then lied. Measured
        # 2026-08-27 — it passed from a terminal and failed under `sweep-control-gate.py`, which is
        # the only reason it was caught. Everything a plant makes must be under its own $t.
        mkdir -p "$t/repo"
        (
            cd "$t/repo" || exit 1
            git init -q . && git config user.email c@x && git config user.name c
            mkdir -p planning/hooks
            printf '#!/bin/sh\nexit 0\n' > planning/hooks/pre-commit
            printf '#!/bin/sh\nexit 0\n' > planning/hooks/pre-push
            chmod +x planning/hooks/pre-commit planning/hooks/pre-push
            cp "$SELF" planning/hooks/install.sh
            git add -A && git commit -qm seed
            case "$plant" in
                sync)         MCPR_HOOKGATE_CONTROL=1 bash planning/hooks/install.sh >/dev/null 2>&1 ;;
                drift)        MCPR_HOOKGATE_CONTROL=1 bash planning/hooks/install.sh >/dev/null 2>&1
                              printf '# stale\n' >> .git/hooks/pre-commit ;;
                absent_solo)  : ;;
                absent_fleet) git worktree add -q "$t/wt" -b runner >/dev/null 2>&1 || exit 9 ;;
                notexec)      MCPR_HOOKGATE_CONTROL=1 bash planning/hooks/install.sh >/dev/null 2>&1
                              chmod -x .git/hooks/pre-commit ;;
            esac
            out=$(MCPR_HOOKGATE_CONTROL=1 bash planning/hooks/install.sh --gate 2>&1); code=$?
            case "$out" in
                *"DRIFTED"*)        r=DRIFT ;;
                *"NOT EXECUTABLE"*) r=NOTEXEC ;;
                *"ABSENT"*)         r=ABSENT ;;
                *"not installed"*)  r=EXEMPT ;;
                *)                  r=OK ;;
            esac
            echo "$r/$code"
        ) > "$t/verdict" 2>/dev/null
        # A plant whose setup failed must not read as a verdict. Exit 9 above is the setup saying
        # so, and an empty file is the subshell dying before it printed; both read NOT_SET_UP (kept
        # space-free, because these readings are parsed out of a space-separated list), which
        # matches no expectation and so fails the control rather than passing quietly.
        if [ $? -ne 0 ]; then
            read_="NOT_SET_UP"
        else
            read_=$(tail -1 "$t/verdict" 2>/dev/null)
            [ -n "$read_" ] || read_="NOT_SET_UP"
        fi
        got="$got$plant=$read_ "
        rm -rf "$t"
    done
    n=0
    for name in sync:OK/0 drift:DRIFT/1 absent_solo:EXEMPT/0 absent_fleet:ABSENT/1 notexec:NOTEXEC/1; do
        plant=${name%%:*}; expected=${name#*:}
        read_=$(printf '%s' "$got" | tr ' ' '\n' | sed -n "s|^$plant=||p")
        [ -n "$read_" ] || read_="NOT_ASSESSED"
        if [ "$read_" = "$expected" ]; then
            printf '  ok    %-13s expected %-11s read %s\n' "$plant" "$expected" "$read_"
        else
            printf '  MISS  %-13s expected %-11s read %s\n' "$plant" "$expected" "$read_"; n=$((n+1))
        fi
    done
    [ "$n" -eq 0 ] || return 2
    return 0
}

if [ "$mode" = gate ] && [ -z "${MCPR_HOOKGATE_CONTROL-}" ]; then
    SELF=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")
    echo "presence control (throwaway repositories; nothing is planted here)"
    if ! control; then
        echo
        echo "CONTROL DID NOT FIRE — a planted hook state read wrong."
        echo "The verdict below would be an absence this instrument cannot see, so none is printed."
        exit 2
    fi
    echo "  control fired: every planted state read exactly."
    echo
fi

# Only `install` creates the directory. A gate that has to make something before it can look is
# mutating as a side effect of checking, and this repo's gates state that writing a floor is a
# deliberate flag rather than a consequence of reading.
[ "$mode" = install ] && mkdir -p "$DEST"
rc=0
for h in pre-commit pre-push; do
    s="$SRC/$h"; d="$DEST/$h"
    [ -f "$s" ] || { echo "FATAL: no tracked hook at planning/hooks/$h"; exit 2; }
    if [ "$mode" = install ]; then install -m 0755 "$s" "$d"; fi
    if [ ! -f "$d" ]; then
        if [ "$mode" = gate ] && [ "$linked" -eq 0 ]; then
            printf '  %-12s not installed  — 0 linked worktrees, so nothing relies on it here\n' "$h"
        else
            printf '  %-12s ABSENT      (tracked %s)\n' "$h" "$(shasum -a 256 "$s" | cut -c1-12)"; rc=1
        fi
        continue
    fi
    ss=$(shasum -a 256 "$s" | cut -d' ' -f1); ds=$(shasum -a 256 "$d" | cut -d' ' -f1)
    if [ "$ss" = "$ds" ]; then
        x=$([ -x "$d" ] && echo "" || echo "  NOT EXECUTABLE"); [ -n "$x" ] && rc=1
        printf '  %-12s in sync     %s%s\n' "$h" "${ss:0:12}" "$x"
    else
        printf '  %-12s DRIFTED     tracked %s  installed %s\n' "$h" "${ss:0:12}" "${ds:0:12}"; rc=1
    fi
done
echo "  hooks dir: $DEST   linked worktrees: $linked"
[ "$mode" != install ] && [ $rc -ne 0 ] && echo "  the installed hooks do not match the tracked source — run planning/hooks/install.sh"
exit $rc
