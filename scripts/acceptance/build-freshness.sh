#!/bin/bash
#
# The one reader of "is the built product the tree's product", sourced by every acceptance script
# that judges a screen.
#
# This exists because the harness has been reporting STALE BUILDS AS PRODUCT DEFECTS. Seven of
# eight acceptance checks were red on a clean `main`; six went green after a rebuild with no source
# change at all, and three of those said a screen "is not built" when it is built. A gate that
# blames the product for the age of the binary is worse than no gate, because it sends a runner to
# fix code that is already correct.
#
# ## Content, never mtime — and that is the whole of D-m11-a
#
# M11 added a freshness check with the right intent and the wrong instrument: it compares source
# MTIMES against the built app. A rebase rewrites mtimes without changing a byte, so `xcodebuild`
# correctly declines to relink, the binary keeps its old mtime, and the check blocks forever —
# `make build-mac` exiting 0 does not clear it, and only deleting the derived product does.
# Rebase-then-gate is this fleet's standard cycle, so an mtime check blocks every merge.
#
# Everything here is decided on a SHA-256 of file contents. A rebase is invisible to it by
# construction, which is the property M11's check could not have.
#
# ## Two hashes, because one of them can be right while the product is wrong
#
# The stamp records the digest of the input tree AND the digest of the built bundle:
#
#     config  Debug
#     sources <sha256 of every file this configuration is built from>
#     binary  <sha256 of every file INSIDE the .app>
#
# The source hash alone would pass an old bundle copied back beside a fresh stamp. The bundle hash
# alone would pass a product that matches its stamp while the tree has moved on. Both are required
# to agree with what is on disk right now.
#
# The bundle side covers every file rather than the mach-o alone, because the mach-o alone leaves a
# real hole: swap an Info.plist, a resource or an embedded framework, leave the executable byte for
# byte identical, and the product would read FRESH. Measured: that is 34 files and 20MB, hashed in
# 0.07s, so there is no reason to check less than all of it.
#
# The tree is also digested BEFORE the build (`build_freshness_begin`) and compared afterwards, so a
# source edited WHILE `xcodebuild` runs cannot be stamped as though the product contained it. That
# window is not hypothetical here: this fleet has repeatedly had two writers in one worktree.
#
# The stamp is written BESIDE the bundle rather than inside it. Writing a file into a signed
# `.app` after the build invalidates its signature, and the Release configuration turns the
# hardened runtime on — so an embedded stamp would break the very configuration it was meant to
# certify.
#
# ## Per configuration, and per that configuration's own inputs
#
# A Debug-only stamp consulted for a Release judgement would certify the wrong artifact, so each
# configuration keeps its own stamp. Each also digests only what it is actually built from: the
# Mac app links `MCPRouterKit` and `MCPRouterUI` and its own target directory, and does NOT link
# `RouterCore`, `MCPRouterCLI`, `ControlDiff`, `ControlProbe` or any test target. Digesting those
# too would be the safe direction for honesty and the wrong one for usability — every router edit
# would block every Mac acceptance run on a product that is genuinely current, which is D-m11-a
# reintroduced wearing different clothes.
#
# ## The hole that is NOT closed, stated rather than hidden
#
# If `xcodebuild` exits 0 having skipped work its own dependency graph did not see, the stamp
# records the current tree beside a product that does not reflect it — and the stamp then asserts a
# PAIRING that xcodebuild never claimed. xcodebuild only said "nothing to do"; the stamp says "this
# tree produced this binary", which is the stronger statement. Detecting it would need evidence
# that the link step actually ran, which xcodebuild does not expose here, so the hole is named
# rather than closed. An embedded digest written by a build phase would not close it either: a
# phase with no declared outputs runs on every build, including the skipped ones.

# The `.app` each configuration produces.
_bf_product() {
    case "$1" in
        Debug | Release) printf 'MCPRouter.app' ;;
        Debug-iphonesimulator) printf 'MCPRouterIOS.app' ;;
        *) return 1 ;;
    esac
}

# The mach-o inside that bundle. macOS nests it under `Contents/MacOS`; iOS does not.
_bf_executable() {
    case "$1" in
        Debug | Release) printf 'Contents/MacOS/MCPRouter' ;;
        Debug-iphonesimulator) printf 'MCPRouterIOS' ;;
        *) return 1 ;;
    esac
}

# The command that makes a stale product current, named in every message so the reader never has
# to guess which build they owe.
_bf_command() {
    case "$1" in
        Debug) printf 'make build-mac' ;;
        Release) printf 'make build-mac-release' ;;
        Debug-iphonesimulator) printf 'make build-ios' ;;
        *) return 1 ;;
    esac
}

# Repo-relative paths this configuration is built from. Directories are walked in full — by path
# rather than by extension, because a resource is an input too: `Package.swift` ships
# `Control/Fixtures` and `Control/Authored` into the bundle, and every `MCPROUTER_SCENARIO` an
# acceptance script drives is one of those JSON files. A Swift-only digest would call a tree fresh
# after the fixture behind the scenario under test had changed.
_bf_inputs() {
    case "$1" in
        Debug | Release)
            printf '%s\n' app/MCPRouter app/Sources/MCPRouterKit app/Sources/MCPRouterUI \
                app/project.yml app/Package.swift app/Package.resolved
            ;;
        Debug-iphonesimulator)
            printf '%s\n' app/MCPRouterIOS app/Sources/MCPRouterKit app/Sources/MCPRouterUI \
                app/project.yml app/Package.swift app/Package.resolved
            ;;
        *) return 1 ;;
    esac
}

_bf_products_dir() { printf '%s/app/.derived/Build/Products/%s' "$1" "$2"; }
_bf_stamp_path() { printf '%s/.mcprouter-build-stamp' "$(_bf_products_dir "$1" "$2")"; }

# The digest of everything <config> is built from, taken inside <root> so the paths that go into
# the hash are repo-relative and two worktrees of the same commit agree.
#
# Both the content and the path of every file are covered: hashing contents alone would call a
# rename a no-op, and a renamed source is a rebuild.
build_freshness_digest() {
    local config="$1" root="$2" list
    list="$(_bf_inputs "$config")" || return 1
    (
        cd "$root" 2>/dev/null || exit 1
        # shellcheck disable=SC2086  # the input list is this file's own, deliberately word-split
        printf '%s\n' $list \
            | while IFS= read -r p; do [ -e "$p" ] && find "$p" -type f -print; done \
            | LC_ALL=C sort \
            | xargs shasum -a 256 \
            | shasum -a 256 \
            | cut -d' ' -f1
    )
}

# The digest of the built PRODUCT — every file in the bundle, not just the mach-o.
#
# Hashing the executable alone leaves a real hole: swap an Info.plist, a resource, or an embedded
# framework and leave the binary untouched, and the product reads FRESH. The bundle here is 34 files
# and 20MB and hashes in 0.07s, so there is no reason to check less than all of it.
build_freshness_binary_digest() {
    local config="$1" root="$2" app exe
    app="$(_bf_products_dir "$root" "$config")/$(_bf_product "$config")"
    exe="$app/$(_bf_executable "$config")"
    [ -f "$exe" ] || return 1
    (
        cd "$app" 2>/dev/null || exit 1
        find . -type f -print | LC_ALL=C sort | xargs shasum -a 256 | shasum -a 256 | cut -d' ' -f1
    )
}

_bf_pre_path() { printf '%s/app/.derived/.mcprouter-build-pre-%s' "$1" "$2"; }

# Record the tree digest BEFORE the build starts, so a source edited WHILE `xcodebuild` runs cannot
# be stamped as though the product contained it. Called by the Makefile immediately before the
# build; `build_freshness_write` refuses to stamp if the two disagree.
build_freshness_begin() {
    local config="$1" root="$2" pre
    pre="$(_bf_pre_path "$root" "$config")"
    mkdir -p "$(dirname "$pre")"
    build_freshness_digest "$config" "$root" > "$pre"
}

# Record what this build was built from. Called by the Makefile after `xcodebuild` exits 0, and by
# nothing else — a stamp written by anything other than a successful build is a stamp that can
# certify a product nobody built.
build_freshness_write() {
    local config="$1" root="$2" stamp sources binary pre
    stamp="$(_bf_stamp_path "$root" "$config")" || return 1
    sources="$(build_freshness_digest "$config" "$root")" || return 1
    binary="$(build_freshness_binary_digest "$config" "$root")" || {
        echo "build-freshness: no product to stamp for $config" >&2
        return 1
    }
    [ -n "$sources" ] || { echo "build-freshness: refusing to stamp an empty digest" >&2; return 1; }

    # If the tree moved WHILE the build ran, the product does not contain what the tree now says.
    # Stamping it would record the new sources against an older product — a stale build certified as
    # fresh, which is the one direction this file must never fail in. Refuse, and leave the previous
    # stamp in place so the next check blocks.
    pre="$(_bf_pre_path "$root" "$config")"
    if [ -f "$pre" ] && [ "$(cat "$pre")" != "$sources" ]; then
        echo "build-freshness: the $config sources changed while the build was running, so this" >&2
        echo "                 product does not contain the tree as it now stands. NOT stamping —" >&2
        echo "                 run '$(_bf_command "$config")' again on a settled tree." >&2
        rm -f "$pre"
        return 1
    fi
    rm -f "$pre"

    # Written temp-then-rename so a stamp is either absent or complete. A half-written stamp that
    # still parses is worse than none: it would answer a freshness question with a truncated hash.
    {
        echo "# Written by the Makefile after a successful build. Content hashes, never mtimes:"
        echo "# a rebase rewrites mtimes and changes nothing, and must not read as stale."
        echo "config $config"
        echo "sources $sources"
        echo "binary $binary"
    } > "$stamp.tmp" && mv "$stamp.tmp" "$stamp"
}

_bf_stamp_field() { [ -f "$1" ] && awk -v k="$2" '$1 == k { print $2; exit }' "$1"; }

# The check itself. Prints the reason on stderr and returns 2 when the product cannot be trusted to
# be this tree's product; returns 0 when it can.
#
# Every message names STALENESS and the command that clears it, and none of them names a screen, a
# string or a board — that separation is the entire point of the item. Exit 1 is a claim about the
# product; anything the harness could not establish is exit 2.
build_freshness_check() {
    local config="$1" root="$2" stamp app recorded_sources recorded_binary now_sources now_binary cmd
    cmd="$(_bf_command "$config")" || {
        echo "build-freshness: unknown configuration '$config'" >&2
        return 2
    }
    app="$(_bf_products_dir "$root" "$config")/$(_bf_product "$config")"
    stamp="$(_bf_stamp_path "$root" "$config")"

    [ -d "$app" ] || {
        echo "no $config build at $app — run '$cmd' first." >&2
        return 2
    }
    [ -f "$stamp" ] || {
        echo "there is no record of what this $config build was built from (no stamp at $stamp), so
this harness cannot tell a current product from a stale one. Run '$cmd'." >&2
        return 2
    }

    # The stamp must say it is this configuration's. Without this the two hashes alone are
    # config-blind: a Debug bundle and its stamp copied into the Release slot satisfy both
    # comparisons and read FRESH, which is a stale build certified by a filename.
    local recorded_config
    recorded_config="$(_bf_stamp_field "$stamp" config)"
    [ "$recorded_config" = "$config" ] || {
        echo "the stamp beside this $config build records configuration
'${recorded_config:-（none）}'. A product and a stamp from another configuration have been put in
this slot, so nothing here describes the $config build. Run '$cmd'." >&2
        return 2
    }

    recorded_binary="$(_bf_stamp_field "$stamp" binary)"
    now_binary="$(build_freshness_binary_digest "$config" "$root")" || {
        echo "the $config bundle has no executable inside it — run '$cmd'." >&2
        return 2
    }
    [ "$recorded_binary" = "$now_binary" ] || {
        echo "the $config bundle is not the one this stamp was written for: its contents hash
${now_binary:0:12} and the build recorded ${recorded_binary:0:12}. Something in the built product —
the executable, a resource, the Info.plist — is not what came out of that build. Run '$cmd'." >&2
        return 2
    }

    recorded_sources="$(_bf_stamp_field "$stamp" sources)"
    now_sources="$(build_freshness_digest "$config" "$root")"
    [ -n "$now_sources" ] || {
        echo "could not digest the $config inputs — treat this as a broken reader, not a pass." >&2
        return 2
    }
    [ "$recorded_sources" = "$now_sources" ] || {
        echo "this $config build is STALE: the sources it was built from hash
${recorded_sources:0:12} and the tree now hashes ${now_sources:0:12}. Nothing below has been
measured against the current tree, so no failure here would be a statement about the product.
Run '$cmd'." >&2
        return 2
    }
    return 0
}

# What acceptance scripts call. Blocks (exit 2) in the house format, never fails (exit 1).
#
# The `|| status=$?` is load-bearing rather than defensive. Callers run under `set -e`, and a bare
# `reason="$(build_freshness_check …)"` aborts the shell AT THE ASSIGNMENT when the check returns
# non-zero — so the script exited 2 having printed nothing at all. A gate that blocks silently is
# the same defect this file exists to remove, one level down.
build_freshness_require() {
    local reason status=0
    reason="$(build_freshness_check "$1" "$2" 2>&1)" || status=$?
    [ "$status" -eq 0 ] && return 0
    echo "BLOCKED: $reason" >&2
    exit 2
}
