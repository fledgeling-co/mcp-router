#!/usr/bin/env python3
"""Say which build description `make test` just compiled, and refuse to be silent about a
directory no lane reads.

M33's defect was not a missing lane. It was a **missing lane that reported success**: `app/`
carries two build descriptions of the same tree — `Package.swift` for SwiftPM and `project.yml`
for xcodebuild — and they disagreed about `MCPRouter/`. SwiftPM declared no target there, so
`swift test` compiled nothing under the directory the Mac app's assembly lives in and still exited
0, while `xcodebuild` called a planted fault in that same directory fatal. A reader of a green
`make test` could not tell which of the two descriptions had run, so a green over a directory
nothing read was indistinguishable from a green over a directory that passed.

This prints the difference, and it is a gate rather than an `echo` because an `echo` is the same
defect one level up: a line that says "SwiftPM compiled the app" while nothing checked whether it
did is exactly the unfalsifiable green M33 is about.

## What it stands on

Three sources, in increasing order of how hard they are to fake:

  declaration   `swift package describe --type json` — which targets SwiftPM *says* it has, and
                which source files each one claims. A declaration alone proves nothing: this is
                the layer that was wrong before M33 was armed.
  build plan    `.build/<config>.yaml`, llbuild's manifest for the build that just ran.
  **object**    `.build/<triple>/<config>/<Target>.build/<Source>.swift.o` — a real artifact that
                only a real compile produces. This is the load-bearing one.

An object file alone is not enough either, and the reason is the same defect wearing a third hat:
**a `.o` outlives the target that produced it.** Delete `MCPRouterApp` from `Package.swift` and the
object from the previous build stays on disk, so a check that only looked for the artifact would go
on reporting the directory compiled after the lane stopped compiling it. So a target counts as
compiled only when it is BOTH declared right now AND carries an object at least as new as its
source. Removing the target drops it from the declaration; editing the source without rebuilding
makes the object stale. Either way the claim falls rather than persisting.

## What it fails on

  1. A path `project.yml` declares that neither the SwiftPM lane nor an iOS lane in `make all`
     covers. That is M33 recurring, on whichever directory it lands next.
  2. A SwiftPM target that declares sources and has compiled none of them — the shape the review
     lane warned about when this was armed, where a target exists in the manifest and the lane
     never builds it.
  3. `make all` no longer running the iOS lanes. The iOS directories are not compiled here and
     that is fine *because another lane in the same gate compiles them*; if that stops being true
     they are uncovered, and this says so instead of continuing to defer to a lane that left.

Exit 0 when every declared path is covered and every declared target compiled; 1 when one is not;
2 when the report could not be produced at all. Exit 2 matters as much as exit 1: "I could not
tell you what was compiled" must not look like "everything was compiled", which is the whole
subject of this file.

`--selftest` runs the analysis against planted inputs and requires each one to go red. It needs no
toolchain and no build, because the analysis is a pure function of the four texts it reads.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path

MARKER = "build-description:"

# The name a green line must carry so `make test` can prove the report was not skipped. Kept
# separate from MARKER because the Makefile greps for MARKER at the head of a line, and a verdict
# line that also began with it would let a FAILING report satisfy the presence check.
VERDICT = "build-description-verdict:"


# =============================================================================================
# Model
# =============================================================================================

@dataclass
class SwiftPMTarget:
    name: str
    kind: str
    path: str
    sources: list[str]
    compiled: list[str] = field(default_factory=list)
    stale: list[str] = field(default_factory=list)
    missing: list[str] = field(default_factory=list)

    @property
    def fully_compiled(self) -> bool:
        return bool(self.sources) and not self.stale and not self.missing


@dataclass
class Finding:
    code: str
    detail: str


@dataclass
class Report:
    lines: list[str] = field(default_factory=list)
    findings: list[Finding] = field(default_factory=list)

    def say(self, text: str = "") -> None:
        self.lines.append(text)

    def fail(self, code: str, detail: str) -> None:
        self.findings.append(Finding(code, detail))


# =============================================================================================
# Readers. Each returns its quantity or raises Unreadable — never a default that reads as clean.
# =============================================================================================

class Unreadable(Exception):
    """The report could not be produced. Distinct from the report being red."""


def read_declaration(app_dir: Path, describe_json: str | None = None) -> tuple[str, list[SwiftPMTarget]]:
    """`swift package describe` — what SwiftPM says its targets are, right now."""
    if describe_json is None:
        try:
            proc = subprocess.run(
                ["swift", "package", "describe", "--type", "json"],
                cwd=app_dir, capture_output=True, text=True, timeout=600,
            )
        except (OSError, subprocess.TimeoutExpired) as exc:
            raise Unreadable(f"could not run `swift package describe` in {app_dir}: {exc}") from exc
        if proc.returncode != 0:
            raise Unreadable(
                "`swift package describe` exited "
                f"{proc.returncode}; the build description could not be read:\n{proc.stderr.strip()[:2000]}"
            )
        describe_json = proc.stdout

    # `swift package describe` prepends warnings to stdout on some toolchains, so seek the JSON.
    brace = describe_json.find("{")
    if brace < 0:
        raise Unreadable("`swift package describe` produced no JSON object")
    try:
        doc = json.loads(describe_json[brace:])
    except json.JSONDecodeError as exc:
        raise Unreadable(f"`swift package describe` produced unparseable JSON: {exc}") from exc

    targets = [
        SwiftPMTarget(
            name=t.get("name", "?"),
            kind=t.get("type", "?"),
            path=t.get("path", ""),
            sources=sorted(t.get("sources", []) or []),
        )
        for t in doc.get("targets", [])
    ]
    if not targets:
        raise Unreadable("`swift package describe` named no targets — a package with no targets "
                         "cannot be reported on, and reporting it clean would be the defect")
    return doc.get("name", "?"), targets


def read_project_yml(text: str) -> list[tuple[int, str, str]]:
    """The xcodebuild description's target source paths: (line, target, path).

    Deliberately a line scan rather than a YAML parse: PyYAML is not a dependency of this repo,
    and the shape being read — `targets:` then an indented target name then `- path:` — is two
    levels deep and stable. A parse that needed an install would be a gate that skips itself on a
    machine without it, which is the failure mode this file exists to remove.
    """
    out: list[tuple[int, str, str]] = []
    in_targets = False
    current = "?"
    for lineno, line in enumerate(text.splitlines(), 1):
        if re.match(r"^targets:\s*$", line):
            in_targets = True
            continue
        if in_targets and re.match(r"^[A-Za-z_]", line):
            in_targets = False           # a new top-level key ends the targets block
            continue
        if not in_targets:
            continue
        name = re.match(r"^  ([A-Za-z_][A-Za-z0-9_]*):\s*$", line)
        if name:
            current = name.group(1)
            continue
        src = re.match(r"^\s+-\s*path:\s*(\S+)\s*$", line)
        if src:
            out.append((lineno, current, src.group(1)))
    if not out:
        raise Unreadable("app/project.yml declared no target source paths — either the file moved "
                         "or this reader stopped matching it; both are 'cannot tell', not 'clean'")
    return out


def read_ios_platforms(text: str) -> set[str]:
    """Which project.yml targets declare `platform: iOS`. Used to decide which lane owns a path."""
    ios: set[str] = set()
    current = None
    in_targets = False
    for line in text.splitlines():
        if re.match(r"^targets:\s*$", line):
            in_targets = True
            continue
        if in_targets and re.match(r"^[A-Za-z_]", line):
            in_targets = False
            continue
        if not in_targets:
            continue
        name = re.match(r"^  ([A-Za-z_][A-Za-z0-9_]*):\s*$", line)
        if name:
            current = name.group(1)
            continue
        if current and re.match(r"^\s+platform:\s*iOS\s*$", line):
            ios.add(current)
    return ios


def read_all_target(makefile: str) -> list[str]:
    """The prerequisite list of `make all` — which lanes the whole gate actually runs."""
    m = re.search(r"^all:[ \t]*(.*)$", makefile, re.M)
    if not m:
        raise Unreadable("the Makefile has no `all:` target, so which lanes run together is unknown")
    return m.group(1).split()


def attribute_objects(app_dir: Path, targets: list[SwiftPMTarget], config: str) -> Path:
    """Attach per-source object evidence to each target. Returns the build root it read.

    A source counts as compiled when `<Target>.build/<name>.swift.o` exists AND its mtime is at
    least the source's. The freshness half is not decoration: an object outlives the target that
    made it, so existence alone would keep reporting a directory compiled after the lane stopped
    compiling it.
    """
    roots = sorted((app_dir / ".build").glob(f"*/{config}"))
    roots = [r for r in roots if r.is_dir() and r.parent.name != "Modules"]
    if not roots:
        raise Unreadable(
            f"no build root at {app_dir}/.build/*/{config} — this report must run after the suite "
            "builds, because it reports what was compiled rather than what was declared"
        )
    root = roots[-1]
    for tgt in targets:
        objdir = root / f"{tgt.name}.build"
        for src in tgt.sources:
            src_path = app_dir / tgt.path / src
            obj = objdir / f"{Path(src).name}.o"
            if not obj.exists():
                tgt.missing.append(src)
            elif src_path.exists() and obj.stat().st_mtime < src_path.stat().st_mtime:
                tgt.stale.append(src)
            else:
                tgt.compiled.append(src)
    return root


# =============================================================================================
# The analysis. A pure function of the texts, so --selftest can plant into it.
# =============================================================================================

def analyse(
    package_name: str,
    targets: list[SwiftPMTarget],
    yml_paths: list[tuple[int, str, str]],
    ios_targets: set[str],
    all_prereqs: list[str],
    build_root: str,
) -> Report:
    rep = Report()
    swiftpm_paths = {t.path.rstrip("/"): t for t in targets}

    rep.say(f"{MARKER} app/Package.swift (SwiftPM, package `{package_name}`) — "
            f"this is the description `make test` compiled")
    rep.say(f"  objects read from app/{build_root}")
    rep.say("")
    rep.say("  compiled by this lane:")
    for tgt in sorted(targets, key=lambda t: t.name):
        # The object lookup keys on the source's basename, which is what SwiftPM names the object
        # after. Two sources in different subdirectories sharing a basename would therefore both
        # resolve to ONE object, and both would count as compiled while at most one of them was —
        # a check reading the wrong quantity, which is the register this whole item belongs to.
        # There are no collisions in this package today; this fires if that changes.
        seen: dict[str, str] = {}
        for src in tgt.sources:
            base = Path(src).name
            if base in seen:
                rep.fail("basename-collision",
                         f"SwiftPM target `{tgt.name}` has two sources named `{base}` "
                         f"({seen[base]} and {src}). Object evidence is keyed on the basename, so "
                         f"one object would vouch for both files and this report would overstate "
                         f"what was compiled.")
            seen[base] = src
        flag = "" if tgt.fully_compiled else "   <-- NOT COMPILED"
        rep.say(f"    {tgt.name:<20} {tgt.kind:<11} {tgt.path:<26} "
                f"{len(tgt.compiled)}/{len(tgt.sources)} sources{flag}")
        if tgt.missing:
            rep.fail("uncompiled-target",
                     f"SwiftPM target `{tgt.name}` declares {len(tgt.sources)} source(s) at "
                     f"{tgt.path} and {len(tgt.missing)} produced no object: "
                     f"{', '.join(tgt.missing[:5])}. A target the lane does not build is a target "
                     f"whose directory this lane's green says nothing about.")
        if tgt.stale:
            rep.fail("stale-object",
                     f"SwiftPM target `{tgt.name}` has object(s) older than their source: "
                     f"{', '.join(tgt.stale[:5])}. The green describes a previous tree.")

    ios_lanes = [p for p in all_prereqs if p.startswith("test-ios")]
    rep.say("")
    rep.say("  declared by app/project.yml and NOT compiled by this lane:")
    deferred = uncovered = 0
    for lineno, tname, path in yml_paths:
        clean = path.rstrip("/")
        if clean in swiftpm_paths:
            continue
        if tname in ios_targets and ios_lanes:
            deferred += 1
            rep.say(f"    {tname:<20} {clean:<26} -> covered by `make {'`, `make '.join(ios_lanes)}`")
        else:
            uncovered += 1
            rep.say(f"    {tname:<20} {clean:<26} -> COVERED BY NOTHING")
            why = ("no iOS lane remains in `make all`" if tname in ios_targets
                   else "no SwiftPM target declares this path")
            rep.fail("uncovered-path",
                     f"app/project.yml:{lineno} declares `{clean}` for target `{tname}`, and "
                     f"{why}. A green `make test` would be silent about that directory rather "
                     f"than clean over it — this is M33 recurring.")
    if deferred == 0 and uncovered == 0:
        rep.say("    (none)")

    here = sum(1 for _, _, p in yml_paths if p.rstrip("/") in swiftpm_paths)
    rep.say("")
    if rep.findings:
        rep.say(f"{VERDICT} RED — {len(rep.findings)} finding(s)")
        for f in rep.findings:
            rep.say(f"    [{f.code}] {f.detail}")
    else:
        rep.say(f"{VERDICT} OK — {here} project.yml path(s) compiled by this lane, "
                f"{deferred} deferred to {' + '.join('make ' + l for l in ios_lanes) or 'nothing'}, "
                f"{uncovered} covered by nothing")
    return rep


# =============================================================================================
# Selftest. Every arm plants a condition and requires the analysis to go red or refuse.
# =============================================================================================

CLEAN_YML = """name: MCPRouter

targets:
  MCPRouter:
    type: application
    platform: macOS
    sources:
      - path: MCPRouter
  MCPRouterIOS:
    type: application
    platform: iOS
    sources:
      - path: MCPRouterIOS
"""

CLEAN_MAKE = "all: tools lint build test test-ios test-ios-glass parity\n"


def _tgt(name: str, path: str, n: int, *, compiled: int | None = None, stale: int = 0) -> SwiftPMTarget:
    srcs = [f"{name}{i}.swift" for i in range(n)]
    t = SwiftPMTarget(name=name, kind="library", path=path, sources=srcs)
    c = n if compiled is None else compiled
    t.compiled = srcs[:c]
    t.stale = srcs[c:c + stale]
    t.missing = srcs[c + stale:]
    return t


def _clean_targets() -> list[SwiftPMTarget]:
    return [_tgt("MCPRouterKit", "Sources/MCPRouterKit", 3), _tgt("MCPRouterApp", "MCPRouter", 1)]


def _run(targets, yml=CLEAN_YML, make=CLEAN_MAKE):
    return analyse("MCPRouterKit", targets, read_project_yml(yml),
                   read_ios_platforms(yml), read_all_target(make), "arm64-apple-macosx/debug")


def selftest() -> int:
    arms: list[tuple[str, str, object]] = []

    # The control. A poison turning a red fixture redder measures nothing.
    ctl = _run(_clean_targets())
    arms.append(("control", "clean inputs must be OK", not ctl.findings))

    # 1. The M33 defect itself: SwiftPM stops declaring a target over MCPRouter/.
    r = _run([_tgt("MCPRouterKit", "Sources/MCPRouterKit", 3)])
    arms.append(("poison", "app target dropped from Package.swift -> uncovered-path",
                 any(f.code == "uncovered-path" for f in r.findings)))

    # 2. The shape the review lane warned about when M33 was armed: the target is declared and the
    #    lane never builds it. Declaration-only checking passes this; object evidence does not.
    r = _run([_tgt("MCPRouterKit", "Sources/MCPRouterKit", 3), _tgt("MCPRouterApp", "MCPRouter", 1, compiled=0)])
    arms.append(("poison", "declared app target with no object -> uncompiled-target",
                 any(f.code == "uncompiled-target" for f in r.findings)))

    # 3. A stale object outliving the source it claims to be evidence for.
    r = _run([_tgt("MCPRouterKit", "Sources/MCPRouterKit", 3),
              _tgt("MCPRouterApp", "MCPRouter", 1, compiled=0, stale=1)])
    arms.append(("poison", "object older than its source -> stale-object",
                 any(f.code == "stale-object" for f in r.findings)))

    # 4. The iOS directories are excused only because another lane in the same gate reads them.
    #    Take that lane out of `all` and the excuse is gone.
    r = _run(_clean_targets(), make="all: tools lint build test parity\n")
    arms.append(("poison", "iOS lanes removed from `make all` -> uncovered-path",
                 any(f.code == "uncovered-path" for f in r.findings)))

    # 5. Two sources sharing a basename, so one object would vouch for both.
    collide = _tgt("MCPRouterKit", "Sources/MCPRouterKit", 1)
    collide.sources = ["A/Same.swift", "B/Same.swift"]
    collide.compiled = list(collide.sources)
    r = _run([collide, _tgt("MCPRouterApp", "MCPRouter", 1)])
    arms.append(("poison", "two sources sharing a basename -> basename-collision",
                 any(f.code == "basename-collision" for f in r.findings)))

    # 5-7. Null arms. Nothing to read must be a refusal, never a clean report.
    for label, fn in (
        ("empty describe JSON", lambda: read_declaration(Path("."), describe_json="{}")),
        ("project.yml with no source paths", lambda: read_project_yml("name: X\ntargets:\n")),
        ("Makefile with no `all:`", lambda: read_all_target("test:\n\tswift test\n")),
    ):
        try:
            fn()
            bit = False
        except Unreadable:
            bit = True
        arms.append(("null", f"{label} -> refuses rather than reports clean", bit))

    width = max(len(d) for _, d, _ in arms)
    bad = 0
    for kind, detail, bit in arms:
        print(f"  {kind:<8} {detail:<{width}}  {'bit' if bit else 'DID NOT BITE'}")
        bad += 0 if bit else 1
    print(f"selftest: {len(arms) - bad}/{len(arms)} arms bit")
    if bad:
        print("error: an arm that does not bite is an assertion that cannot fail")
    return 1 if bad else 0


# =============================================================================================

def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--app-dir", default=None, help="the SwiftPM package root (default: <repo>/app)")
    ap.add_argument("--configuration", default="debug")
    ap.add_argument("--selftest", action="store_true", help="prove every arm can go red, then exit")
    args = ap.parse_args()

    if args.selftest:
        return selftest()

    repo = Path(__file__).resolve().parent.parent
    app_dir = Path(args.app_dir).resolve() if args.app_dir else repo / "app"

    try:
        package_name, targets = read_declaration(app_dir)
        build_root = attribute_objects(app_dir, targets, args.configuration)
        yml_text = (app_dir / "project.yml").read_text(encoding="utf-8")
        yml_paths = read_project_yml(yml_text)
        ios_targets = read_ios_platforms(yml_text)
        all_prereqs = read_all_target((repo / "Makefile").read_text(encoding="utf-8"))
    except (Unreadable, OSError) as exc:
        print(f"error: the build description could not be reported: {exc}", file=sys.stderr)
        print("error: 'cannot tell what was compiled' is not 'everything was compiled'", file=sys.stderr)
        return 2

    rep = analyse(package_name, targets, yml_paths, ios_targets, all_prereqs,
                  str(build_root.relative_to(app_dir)))
    print("\n".join(rep.lines))
    return 1 if rep.findings else 0


if __name__ == "__main__":
    sys.exit(main())
