#!/usr/bin/env python3
"""Bind every committed piece of glass evidence to the build it was taken from.

WHY THIS EXISTS, MEASURED
-------------------------
The `macos-glass` lane was green for seven days over window evidence captured on
20-27 Aug from a build that predates M22. M22 added two destinations and RENUMBERED
four accelerators; M15 moved Settings out of the sidebar. Nothing re-took the
pictures, and nothing could notice: a committed capture carried a subject, a target,
a channel, a digest of its own bytes and a window-title readback -- and NO TIE TO THE
BUILD IT CAME FROM. So the lane went on asserting a shell that no longer shipped, and
the only reason anybody found out is that somebody re-took the pictures by hand
(DEF-058; DEF-059 is the same illness one step on, where the Settings selection
silently stopped taking and the shutter filed a neighbouring board under SURF-011).

Every other staleness question in this repository already has an instrument.
`scripts/acceptance/build-freshness.sh` refuses to judge a screen against a product
the tree has moved past. This is that check moved one layer out: not "is the BINARY
this tree's product" but "is the PICTURE this build's picture".

WHAT A BUILD IDENTITY IS HERE, AND WHY IT IS NOT AN MTIME OR A DATE
------------------------------------------------------------------
The identity of a Mac build is the git blob identity of everything that build is
compiled from -- the same input set `build-freshness.sh` digests, named in one place
below. Blob ids are what git stores, so they are normalised: a checkout with CRLF
line endings on Windows and one with LF on macOS produce the SAME identity for the
same commit, and this gate returns the same verdict on either host. A date would not
survive a rebase and an mtime would not survive a checkout; a content identity
survives both and changes exactly when the product does.

THREE PASSES, ALL EXACT, NONE NEEDING A MODEL OR A BUILD
--------------------------------------------------------
  1 stale      the identity a capture records is not the identity of the tree the
               lane is being read against -- the picture outlived its build
  2 unstamped  a glass-lane artifact no build record covers, so its age cannot be
               established at all. Not a pass; an unanswerable question
  3 ordering   a published capture whose row cannot be shown to have been written
               AT THE SHUTTER -- no capture timestamp, or no capture-time readback.
               A manifest that post-dates its capture records what somebody
               believed, not what the channel did, so it is not lineage

WHAT THIS GATE CANNOT DO, STATED RATHER THAN HIDDEN
---------------------------------------------------
It cannot re-take a picture. Every finding it reports is owed to a macOS host with
Xcode and a display server, and it says so in the finding rather than in a note
somewhere else. Turning any of these green by editing an assertion, a stamp or a
recorded identity is the one move forbidden here: the stale record is the instrument.

    python3 glass-build-gate.py                 # report; exit 2 on any hard finding
    python3 glass-build-gate.py --json
    python3 glass-build-gate.py --reconstruct   # rebuild the record from git history
    python3 glass-build-gate.py --selftest      # watch it go red AND green
    python3 glass-build-gate.py --emit <app> <artifact>...   # macOS, at capture time
"""
from __future__ import annotations

import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path

for _stream in (sys.stdout, sys.stderr):
    if hasattr(_stream, "reconfigure"):
        _stream.reconfigure(encoding="utf-8")

ROOT = Path(os.environ.get("MCP_ROUTER_GLASS_REPO_ROOT", Path(__file__).resolve().parents[3])).resolve()
CAMPAIGN = Path(os.environ.get("MCP_ROUTER_GLASS_CAMPAIGN", ROOT / "planning/test-campaign")).resolve()
RECORD = CAMPAIGN / "evidence/ax/glass-build.json"
CASES = CAMPAIGN / "cases.json"
MANIFEST = CAMPAIGN / "evidence/shots/captures.json"

LANE = "macos-glass"

# The inputs a Mac build is compiled from. Copied deliberately from
# `_bf_inputs()` in scripts/acceptance/build-freshness.sh (Debug/Release), so the two
# readers answer "which build" over the same tree. A path added there and not here
# would leave this gate blind to a change that rebuilds the app, so the drift check
# below reads that file and fails rather than trusting this list.
MAC_BUILD_INPUTS = (
    "app/MCPRouter",
    "app/Sources/MCPRouterKit",
    "app/Sources/MCPRouterUI",
    "app/project.yml",
    "app/Package.swift",
    "app/Package.resolved",
)
FRESHNESS = ROOT / "scripts/acceptance/build-freshness.sh"

# Evidence directories the Mac glass channel writes into. A case citing a source
# file, a log or a router observation is citing something no shutter produced.
GLASS_EVIDENCE_PREFIXES = ("evidence/ax/", "evidence/shots/")

# Two files live under those prefixes and are not pictures of anything: the capture
# manifest, and this gate's own record. A case may legitimately cite either as the
# thing it asserts over, and demanding a build stamp for a registry file would be
# the gate asking who photographed its own paperwork.
NOT_A_CAPTURE = {
    "evidence/shots/captures.json",
    "evidence/ax/glass-build.json",
}


def git(*args: str) -> str:
    out = subprocess.run(("git", "-C", str(ROOT)) + args,
                         capture_output=True, check=True)
    return out.stdout.decode("utf-8", "replace")


def _identity_from_pairs(pairs: dict[str, str]) -> str:
    """One hex digest over `path blob` lines, sorted. Blob ids, so a Windows
    checkout and a macOS checkout of one commit agree."""
    body = "\n".join(f"{p} {pairs[p]}" for p in sorted(pairs))
    return hashlib.sha256(body.encode("utf-8")).hexdigest()


def blobs_at_rev(rev: str) -> dict[str, str]:
    out = git("ls-tree", "-r", rev, "--", *MAC_BUILD_INPUTS)
    pairs: dict[str, str] = {}
    for line in out.splitlines():
        if not line.strip():
            continue
        meta, _, path = line.partition("\t")
        parts = meta.split()
        if len(parts) >= 3 and parts[1] == "blob":
            pairs[path] = parts[2]
    return pairs


def blobs_in_worktree() -> dict[str, str]:
    """What the lane is ACTUALLY being read against: the files on disk now, hashed
    through git's own clean filter, so an uncommitted edit to the Mac app counts."""
    listing = git("ls-files", "-z", "--", *MAC_BUILD_INPUTS)
    paths = [p for p in listing.split("\0") if p]
    if not paths:
        return {}
    proc = subprocess.run(("git", "-C", str(ROOT), "hash-object", "--stdin-paths"),
                          input="\n".join(paths).encode("utf-8"),
                          capture_output=True, check=True)
    shas = proc.stdout.decode().split()
    if len(shas) != len(paths):
        raise SystemExit("glass-build-gate: git hash-object returned "
                         f"{len(shas)} digests for {len(paths)} paths — refusing to "
                         "guess which is which")
    return dict(zip(paths, shas))


def group_identities(pairs: dict[str, str]) -> dict[str, str]:
    """One digest per input root, so a finding can name WHAT moved rather than only
    that something did."""
    out: dict[str, str] = {}
    for root in MAC_BUILD_INPUTS:
        sub = {p: s for p, s in pairs.items() if p == root or p.startswith(root + "/")}
        out[root] = _identity_from_pairs(sub) if sub else ""
    return out


def input_drift() -> list[str]:
    """The list above must stay the build's list. Read build-freshness.sh rather
    than trust the copy: a Mac input added there and missed here would make every
    verdict below quietly narrower than it reads."""
    if not FRESHNESS.exists():
        return [f"{FRESHNESS.relative_to(ROOT)} is missing, so the input list this gate "
                f"digests cannot be checked against the build's own."]
    text = FRESHNESS.read_text(encoding="utf-8", errors="replace")
    marker = "Debug | Release)"
    i = text.find(marker, text.find("_bf_inputs()"))
    if i < 0:
        return ["could not find the Debug/Release input list in build-freshness.sh; "
                "this gate's copy is unverified."]
    block = text[i:text.find(";;", i)]
    declared = {tok for tok in block.replace("\\", " ").split()
                if tok.startswith("app/")}
    missing = sorted(declared - set(MAC_BUILD_INPUTS))
    extra = sorted(set(MAC_BUILD_INPUTS) - declared)
    rows = []
    if missing:
        rows.append(f"build-freshness.sh builds the Mac app from {', '.join(missing)} and "
                    f"this gate does not digest it — every identity below is narrower "
                    f"than the build it claims to name.")
    if extra:
        rows.append(f"this gate digests {', '.join(extra)}, which build-freshness.sh does "
                    f"not name as a Mac build input.")
    return rows


# --------------------------------------------------------------------------------
# The record
# --------------------------------------------------------------------------------

def load_record() -> dict:
    if not RECORD.exists():
        return {}
    return json.loads(RECORD.read_text(encoding="utf-8"))


def glass_artifacts() -> dict[str, list[str]]:
    """Every artifact a `macos-glass` case rests on that a shutter or an AX dump
    produced, with the cases that cite it."""
    rows = json.loads(CASES.read_text(encoding="utf-8"))
    out: dict[str, list[str]] = {}
    for case in rows:
        if case.get("lane") != LANE:
            continue
        for path in case.get("evidence", []) or []:
            if path.startswith(GLASS_EVIDENCE_PREFIXES) and path not in NOT_A_CAPTURE:
                out.setdefault(path, []).append(case.get("id", "?"))
    return out


def reconstruct() -> int:
    """Write the record from git history, and SAY that is where it came from.

    This is a reconstruction, not a capture-time stamp, and the difference is the
    whole of the ordering pass below. What git can prove is which commit last wrote
    each artifact; from that, the Mac build inputs as they stood at that commit are
    exact. What git cannot prove is that the build running at the shutter WAS that
    tree — only the capture channel can record that, and it did not until
    `capture-mac-glass.sh` began calling `--emit`. So every row written here is
    marked `reconstructed-from-git`, and the gate treats that as the weaker claim
    it is.
    """
    arts = glass_artifacts()
    if not arts:
        print("no macos-glass case cites a capture — nothing to stamp")
        return 1
    prior = load_record()
    kept = {k: v for k, v in (prior.get("groups") or {}).items()
            if v.get("provenance") == "capture-channel"}
    claimed = {p for g in kept.values() for p in g.get("artifacts", [])}
    if kept:
        print(f"keeping {len(kept)} capture-time group(s) covering {len(claimed)} "
              f"artifact(s) — a reconstruction never replaces a record the channel "
              f"wrote at the shutter.")
    groups: dict[str, dict] = dict(kept)
    for path in sorted(arts):
        if path in claimed:
            continue
        rel = f"planning/test-campaign/{path}"
        sha = git("log", "-1", "--format=%H", "--", rel).strip()
        if not sha:
            groups.setdefault("UNCOMMITTED", {"artifacts": []})["artifacts"].append(path)
            continue
        g = groups.setdefault(sha, {"artifacts": []})
        g["artifacts"].append(path)
    for sha, g in groups.items():
        g["artifacts"].sort()
        if sha == "UNCOMMITTED" or g.get("provenance") == "capture-channel":
            continue
        g["provenance"] = "reconstructed-from-git"
        pairs = blobs_at_rev(sha)
        g["writtenAt"] = git("log", "-1", "--format=%cI", sha).strip()
        g["subject"] = git("log", "-1", "--format=%s", sha).strip()
        g["buildIdentity"] = _identity_from_pairs(pairs)
        g["byInput"] = group_identities(pairs)
    record = {
        "lane": LANE,
        "stampProvenance": "reconstructed-from-git",
        "stampProvenanceNote": (
            "These rows were NOT written by the capture channel at capture time; no "
            "capture in this lane recorded a build identity, which is DEF-058 itself. "
            "What is recorded here is exact but weaker: the commit that last wrote each "
            "artifact, and the git blob identity of the Mac build inputs as they stood "
            "at that commit. It establishes the build the evidence CANNOT BE NEWER THAN. "
            "A capture taken from a build older than its own commit would read as "
            "current here and does not, so this is a floor on staleness rather than a "
            "measurement of it. Only a re-capture through `capture-mac-glass.sh --emit` "
            "on a macOS host replaces a reconstructed row with a capture-time one."),
        "buildIdentityIs": (
            "sha256 over sorted `<path> <git blob id>` lines for every file under "
            + ", ".join(MAC_BUILD_INPUTS)
            + " — the same input set scripts/acceptance/build-freshness.sh compiles the "
              "Mac app from. Blob ids are line-ending normalised, so this identity is the "
              "same on macOS and on Windows for one commit."),
        "groups": groups,
    }
    RECORD.parent.mkdir(parents=True, exist_ok=True)
    RECORD.write_text(json.dumps(record, indent=1, ensure_ascii=False) + "\n",
                      encoding="utf-8")
    covered = sum(len(g["artifacts"]) for g in groups.values())
    print(f"wrote {RECORD.relative_to(ROOT)}: {covered} artifact(s) in "
          f"{len(groups)} capture commit(s)")
    return 0


# --------------------------------------------------------------------------------
# The passes
# --------------------------------------------------------------------------------

def analyse(now_pairs: dict[str, str] | None = None,
            record: dict | None = None,
            manifest: list | None = None) -> dict:
    record = load_record() if record is None else record
    arts = glass_artifacts()
    pairs = blobs_in_worktree() if now_pairs is None else now_pairs
    now = _identity_from_pairs(pairs)
    now_by_input = group_identities(pairs)

    stale, unstamped, ordering = [], [], []
    covered: set[str] = set()

    # An artifact a CURRENT group stamps has been re-captured against this build, and an older
    # group naming it is history, not a claim. Without this the gate's own remedy ("re-capture on
    # a macOS host") could never clear it: the capture channel appends a group rather than
    # rewriting the old one, so every superseded group stayed red after the re-capture it asked
    # for. Measured 2026-10-19: 55 of 56 artifacts re-stamped at 5a7c06969d69, all still STALE.
    current = {path for g in (record.get("groups") or {}).values()
               if g.get("buildIdentity") == now for path in g.get("artifacts", [])}

    for sha, g in sorted((record.get("groups") or {}).items()):
        for path in g.get("artifacts", []):
            covered.add(path)
        if g.get("buildIdentity") != now and current:
            g = dict(g, artifacts=[a for a in g.get("artifacts", []) if a not in current])
            if not g["artifacts"]:
                continue
        if sha == "UNCOMMITTED":
            for path in g.get("artifacts", []):
                unstamped.append(f"{path}: never committed, so no build identity can be "
                                 f"read for it.")
            continue
        if g.get("buildIdentity") == now:
            continue
        moved = [k for k, v in (g.get("byInput") or {}).items()
                 if now_by_input.get(k) != v]
        n = len(g.get("artifacts", []))
        stale.append(
            f"{n} artifact(s) stamped {str(g.get('buildIdentity'))[:12]} "
            f"({g.get('writtenAt', '?')[:10]}, {sha[:9]}) — the lane is being read "
            f"against {now[:12]}. Moved since: {', '.join(moved) or 'the input set itself'}. "
            f"Owed: re-capture on a macOS host. Artifacts: "
            + ", ".join(g.get("artifacts", [])[:4])
            + (f" … and {n - 4} more" if n > 4 else ""))

    for path, cases in sorted(arts.items()):
        if path not in covered:
            unstamped.append(f"{path}: no build record covers it, so nothing can say which "
                             f"build it depicts. Cited by {', '.join(sorted(cases))}.")

    # Pass 3 — ordering. A row that carries no capture timestamp and no capture-time
    # readback could have been typed at any point after the shutter.
    if manifest is None and MANIFEST.exists():
        manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    if manifest is not None:
        published = {p for p in arts}
        for entry in manifest:
            path = str(entry.get("path", ""))
            if path not in published:
                continue
            if entry.get("provenanceGap"):
                continue
            cond = entry.get("conditions") or {}
            missing = []
            if not entry.get("capturedAt"):
                missing.append("capturedAt")
            if not cond.get("windowTitleReadback"):
                missing.append("conditions.windowTitleReadback")
            if not cond.get("cgWindowID"):
                missing.append("conditions.cgWindowID")
            if missing:
                ordering.append(
                    f"{path}: the row carries no {', '.join(missing)}, so it cannot be "
                    f"shown to have been written at the shutter rather than afterwards.")

    return {
        "buildIdentityNow": now,
        "byInputNow": now_by_input,
        "recordProvenance": record.get("stampProvenance", "none"),
        "artifacts": len(arts),
        "covered": len(covered & set(arts)),
        "stale": stale,
        "unstamped": unstamped,
        "ordering": ordering,
        "inputDrift": input_drift(),
    }


def report(a: dict) -> int:
    print(f"macos-glass build lineage · {a['artifacts']} artifact(s) cited by the lane, "
          f"{a['covered']} carrying a build record ({a['recordProvenance']})")
    print(f"the build this lane is being read against: {a['buildIdentityNow'][:16]}")
    hard = 0
    for label, rows, why in (
        ("INPUT DRIFT — this gate is not digesting the build's own inputs", a["inputDrift"],
         "Bring MAC_BUILD_INPUTS back in line with build-freshness.sh's `_bf_inputs`."),
        ("STALE — the picture outlived the build it was taken from", a["stale"],
         "Re-capture on a macOS host. Editing the stamp, or the assertion it makes "
         "stale, is the one move forbidden here."),
        ("UNSTAMPED — nothing says which build this artifact depicts", a["unstamped"],
         "Stamp it at capture time. It cannot be recovered afterwards, and a "
         "reconstruction from git is a floor rather than a measurement."),
        ("ORDERING — the row cannot be shown to precede its own manifest", a["ordering"],
         "A manifest written after the shutter records what somebody believed. Write "
         "it in the capture channel, as the shutter opens."),
    ):
        if rows:
            hard += len(rows)
            print(f"\n{label}:")
            for r in rows[:20]:
                print(f"   {r}")
            if len(rows) > 20:
                print(f"   ... and {len(rows) - 20} more")
            print(f"   -> {why}")
    if hard:
        print(f"\n{hard} hard finding(s). A green lane over evidence older than the build "
              f"is a statement about a product that no longer ships.")
        return 2
    print("\nEvery glass artifact names the build it was taken from, and that build is "
          "the one this lane is being read against.")
    return 0


def selftest() -> int:
    """Watch every pass go both ways, on copies, changing nothing on disk.

    An assertion nobody has seen go red is indistinguishable from one that cannot,
    and a gate nobody has seen go green is indistinguishable from one that always
    fails. Both directions matter here because this gate is red on the tree it
    ships on -- the evidence really is stale -- so the green half cannot be
    observed by simply running it.
    """
    real = blobs_in_worktree()
    record = load_record()
    groups = {k: v for k, v in (record.get("groups") or {}).items()
              if k != "UNCOMMITTED"}
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8")) if MANIFEST.exists() else []
    if not real or not groups:
        print("selftest: no Mac build inputs, or no build record to read")
        return 2

    current = _identity_from_pairs(real)
    stamped = {sha: dict(g, buildIdentity=current, byInput=group_identities(real))
               for sha, g in groups.items()}
    fresh = dict(record, groups=stamped)
    results: list[tuple[str, bool, str]] = []

    # 1 GREEN. Every artifact restamped with the tree the lane is read against.
    a = analyse(real, record=fresh, manifest=manifest)
    results.append(("a capture taken from THIS build reads current",
                    not a["stale"] and not a["unstamped"] and not a["ordering"],
                    f"stale={len(a['stale'])} unstamped={len(a['unstamped'])} "
                    f"ordering={len(a['ordering'])}"))

    # 2 RED, stale. One Mac source file's blob moves; nothing else changes.
    victim = sorted(p for p in real if p.startswith("app/Sources/MCPRouterUI/"))[0]
    moved = dict(real, **{victim: "0" * 40})
    a = analyse(moved, record=fresh, manifest=manifest)
    results.append((f"one file's content moves ({victim})", bool(a["stale"]),
                    f"stale={len(a['stale'])}: "
                    + (a["stale"][0][:96] if a["stale"] else "nothing")))

    # 3 RED, unstamped. A build record that has stopped covering one artifact.
    thin = {sha: dict(g, artifacts=g["artifacts"][1:]) if g.get("artifacts") else g
            for sha, g in stamped.items()}
    a = analyse(real, record=dict(record, groups=thin), manifest=manifest)
    results.append(("an artifact no build record covers", bool(a["unstamped"]),
                    f"unstamped={len(a['unstamped'])}: "
                    + (a["unstamped"][0][:96] if a["unstamped"] else "nothing")))

    # 4 RED, ordering. A manifest row with its capture-time fields taken out --
    # which is exactly what a row typed up after the shutter looks like.
    cited = {p for p in glass_artifacts() if p.startswith("evidence/shots/")}
    doctored, hit = [], None
    for e in manifest:
        if hit is None and e.get("path") in cited and e.get("capturedAt"):
            hit = e["path"]
            e = {k: v for k, v in e.items() if k != "capturedAt"}
        doctored.append(e)
    a = analyse(real, record=fresh, manifest=doctored)
    results.append((f"a row with no capture timestamp ({hit})", bool(a["ordering"]),
                    f"ordering={len(a['ordering'])}: "
                    + (a["ordering"][0][:96] if a["ordering"] else "nothing")))

    for label, ok, detail in results:
        print(f"{'PASS' if ok else 'FAIL'}  {label}")
        print(f"        {detail}")
    bad = [label for label, ok, _ in results if not ok]
    if bad:
        print(f"\n{len(bad)} arm(s) did not behave: {'; '.join(bad)}")
        return 2
    print("\nAll four arms behaved: the gate is green over a current capture and red "
          "over a stale one, an uncovered one and one whose row cannot be dated.")
    return 0


def emit(app_bundle: str, artifacts: list[str]) -> int:
    """Stamp, at capture time, from what the BUILD produced. macOS only.

    Called by `bin/capture-mac-glass.sh` in the same run as the shutter. Three of
    the four things it records come out of the build rather than out of this
    script: `CFBundleShortVersionString` and `CFBundleVersion` from the bundle's own
    `Info.plist`, and the `sources`/`binary` digests from
    `.mcprouter-build-stamp`, which the Makefile writes only after `xcodebuild`
    exits 0. The fourth, the git blob identity, is what makes the record comparable
    from another host and another checkout. A row written here is
    `capture-channel` provenance and replaces whatever `--reconstruct` had guessed.
    """
    bundle = Path(app_bundle)
    if not bundle.is_dir():
        print(f"glass-build-gate --emit: no build at {bundle}")
        return 2
    stamp = bundle.parent / ".mcprouter-build-stamp"
    if not stamp.exists():
        print(f"glass-build-gate --emit: no build stamp at {stamp}. The Makefile writes "
              f"one after a successful build, and without it nothing here can say which "
              f"tree produced this bundle. Run 'make build-mac'.")
        return 2
    fields = {}
    for line in stamp.read_text(encoding="utf-8", errors="replace").splitlines():
        parts = line.split()
        if len(parts) == 2 and not line.startswith("#"):
            fields[parts[0]] = parts[1]

    version = build = None
    plist = bundle / "Contents/Info.plist"
    if plist.exists():
        try:
            import plistlib
            info = plistlib.loads(plist.read_bytes())
            version = info.get("CFBundleShortVersionString")
            build = info.get("CFBundleVersion")
        except Exception as exc:  # noqa: BLE001 — a missing version is drawn, never defaulted
            print(f"glass-build-gate --emit: could not read {plist}: {exc}")

    pairs = blobs_in_worktree()
    dirty = git("status", "--porcelain", "--", *MAC_BUILD_INPUTS).strip()
    record = load_record() or {"lane": LANE, "groups": {}}
    key = f"capture:{git('rev-parse', 'HEAD').strip()[:9]}"
    record["stampProvenance"] = "capture-channel"
    # Two lanes can stamp at one HEAD (capture-mac-glass.sh, then forced-state.sh). Replacing the
    # group here dropped the first lane's artifacts from the record: measured 2026-10-19, 55
    # artifacts lost their current stamp to a forced-state run one minute later. A group for the
    # same build keeps what it already covers; a different build at the same HEAD (a dirty tree)
    # gets its own key rather than overwriting.
    prior_group = record.setdefault("groups", {}).get(key)
    identity = _identity_from_pairs(pairs)
    if prior_group and prior_group.get("buildIdentity") == identity:
        artifacts = set(artifacts) | set(prior_group.get("artifacts", []))
    elif prior_group:
        key = f"{key}:{identity[:12]}"
    record["groups"][key] = {
        "artifacts": sorted(artifacts),
        "provenance": "capture-channel",
        "writtenAt": _now(),
        "subject": "written by bin/capture-mac-glass.sh in the run that took these pictures",
        "buildIdentity": identity,
        "byInput": group_identities(pairs),
        "bundleVersion": version,
        "bundleBuild": build,
        "buildStampSources": fields.get("sources"),
        "buildStampBinary": fields.get("binary"),
        "worktreeDirty": bool(dirty),
    }
    RECORD.write_text(json.dumps(record, indent=1, ensure_ascii=False) + "\n",
                      encoding="utf-8")
    print(f"  stamped {len(artifacts)} artifact(s) with build "
          f"{_identity_from_pairs(pairs)[:12]} "
          f"(bundle {version or 'no version'} build {build or 'none'})")
    return 0


def _now() -> str:
    from datetime import datetime, timezone
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def main() -> int:
    args = sys.argv[1:]
    if "--emit" in args:
        i = args.index("--emit")
        rest = args[i + 1:]
        if len(rest) < 2:
            print("--emit <app-bundle> <artifact> [artifact ...]")
            return 2
        return emit(rest[0], rest[1:])
    if "--reconstruct" in args:
        return reconstruct()
    if "--selftest" in args:
        return selftest()
    a = analyse()
    if "--json" in args:
        print(json.dumps(a, indent=1, ensure_ascii=False))
        return 0
    return report(a)


if __name__ == "__main__":
    raise SystemExit(main())
