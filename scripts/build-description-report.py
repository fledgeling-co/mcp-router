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
  **freshness** llbuild's own answer to "is there work left for this tree", asked by running the
                build again and requiring it to do nothing. See below for why nothing on disk
                answers this and only the tool does.

An object file alone is not enough either, and the reason is the same defect wearing a third hat:
**a `.o` outlives the target that produced it.** Delete `MCPRouterApp` from `Package.swift` and the
object from the previous build stays on disk, so a check that only looked for the artifact would go
on reporting the directory compiled after the lane stopped compiling it. So a target counts as
compiled only when it is BOTH declared right now AND was not something SwiftPM still had work to do
for. Removing the target drops it from the declaration; editing the source without rebuilding
leaves work outstanding. Either way the claim falls rather than persisting.

## mtime is not a freshness oracle under SwiftPM

The first cut of this gate asked whether the object was at least as new as its source, and that is
wrong in the direction that produces a FALSE RED over a perfectly current object. Measured here on
2026-08-27 against `MCPRouterUI/Controls.swift`:

  * Append a comment to the source and rebuild. `swift build` reports `Compiling MCPRouterUI
    Controls.swift`, so the compile really happened — and the object's mtime does not move, because
    the bytes it would write are identical to the bytes already there. The object is left older
    than the source it perfectly describes, for ever, and no rebuild will fix it.
  * Append a real declaration instead and the object's mtime DOES move and its sha256 changes. So
    the object's mtime tracks changes to the object's CONTENT, not the occurrence of a compile.

Anything that stamps a source without changing its meaning therefore strands the object in the
past. This repository does that as a matter of routine, because `.build` is shared across every
worktree: one worktree compiles a file at 19:21, merging that branch stamps the same content on
`main` at 00:00, and the object is content-current and mtime-older in every other worktree. An
mtime check cannot tell that from "the green describes a previous tree", and in a repo with this
convention the innocent case is the common one.

The sibling artifacts of the same compile are not a way out. Of the four outputs the frontend
writes for one source, `.dia` and `.d` are rewritten unconditionally while `.o` and `.swiftdeps`
are written only when their bytes change — and there is nothing in the shape of the four that says
which is which. Picking the two that happen to be unconditional would be resting the gate on an
undocumented accident, so the oracle here does not rest on any file's mtime.

llbuild's own build database would answer it, but its per-rule results are a custom binary encoding
whose misparse would read as clean, which is the one failure mode this file may not have. So the
question goes to the tool: run the build again and require it to do nothing.

## What it fails on

  1. A path `project.yml` declares that neither the SwiftPM lane nor an iOS lane in `make all`
     covers. That is M33 recurring, on whichever directory it lands next.
  2. A SwiftPM target that declares sources and has compiled none of them, or whose sources are
     absent from the build plan for this run — the shape the review lane warned about when this
     was armed, where a target exists in the manifest and the lane never builds it. The plan half
     is what catches it when stale objects newer than untouched sources would otherwise vouch.
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

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "planning"))
from input_accounting import Tally  # noqa: E402  — the sys.path line above has to come first

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
    unplanned: list[str] = field(default_factory=list)

    @property
    def fully_compiled(self) -> bool:
        return bool(self.sources) and not (self.stale or self.missing or self.unplanned)


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


def read_project_yml(text: str, source: str = "app/project.yml") -> tuple[list[tuple[int, str, str]], Tally]:
    """The xcodebuild description's target source paths: (line, target, path), and what was skipped.

    The skip list is returned and printed rather than discarded, and on this file that is not
    ceremony. This reader decides which directories the OTHER build description claims, so a line
    it silently fails to match is a directory that drops out of the comparison — which is M33's
    defect relocated into the instrument that reports M33.

    Deliberately a line scan rather than a YAML parse: PyYAML is not a dependency of this repo,
    and the shape being read — `targets:` then an indented target name then `- path:` — is two
    levels deep and stable. A parse that needed an install would be a gate that skips itself on a
    machine without it, which is the failure mode this file exists to remove.
    """
    out: list[tuple[int, str, str]] = []
    tally = Tally("project.yml target source paths", source)
    in_targets = False
    current = "?"
    for lineno, line in enumerate(text.splitlines(), 1):
        if re.match(r"^targets:\s*$", line):
            in_targets = True
            tally.drop(line, "the `targets:` key itself")
            continue
        if in_targets and re.match(r"^[A-Za-z_]", line):
            in_targets = False           # a new top-level key ends the targets block
            tally.drop(line, "a top-level key ending the targets block")
            continue
        if not in_targets:
            tally.drop(line, "outside the targets block")
            continue
        name = re.match(r"^  ([A-Za-z_][A-Za-z0-9_]*):\s*$", line)
        if name:
            current = name.group(1)
            tally.drop(line, "a target name, which carries no source path of its own")
            continue
        src = re.match(r"^\s+-\s*path:\s*(\S+)\s*$", line)
        if src:
            out.append(tally.keep((lineno, current, src.group(1))))
        else:
            tally.drop(line, "inside a target but not a `- path:` entry")
    if not out:
        raise Unreadable("app/project.yml declared no target source paths — either the file moved "
                         "or this reader stopped matching it; both are 'cannot tell', not 'clean'")
    return out, tally


def read_ios_platforms(text: str, source: str = "app/project.yml") -> tuple[set[str], Tally]:
    """Which project.yml targets declare `platform: iOS`, and every line that answered nothing.

    A target this misses is a target with no lane, so it reports as covered by nothing and the
    gate goes red. That is the safe direction — the reader fails closed — but the skip list is
    still returned, because "red for the wrong reason" and "red for the right one" are different
    facts and only the list separates them.
    """
    ios: set[str] = set()
    tally = Tally("project.yml iOS platform declarations", source)
    current = None
    in_targets = False
    for line in text.splitlines():
        if re.match(r"^targets:\s*$", line):
            in_targets = True
            tally.drop(line, "the `targets:` key itself")
            continue
        if in_targets and re.match(r"^[A-Za-z_]", line):
            in_targets = False
            tally.drop(line, "a top-level key ending the targets block")
            continue
        if not in_targets:
            tally.drop(line, "outside the targets block")
            continue
        name = re.match(r"^  ([A-Za-z_][A-Za-z0-9_]*):\s*$", line)
        if name:
            current = name.group(1)
            tally.drop(line, "a target name, which carries no platform of its own")
            continue
        if current and re.match(r"^\s+platform:\s*iOS\s*$", line):
            ios.add(tally.keep(current))
        else:
            tally.drop(line, "inside a target but not a `platform: iOS` line")
    return ios, tally


def read_all_target(makefile: str) -> list[str]:
    """The prerequisite list of `make all` — which lanes the whole gate actually runs."""
    m = re.search(r"^all:[ \t]*(.*)$", makefile, re.M)
    if not m:
        raise Unreadable("the Makefile has no `all:` target, so which lanes run together is unknown")
    return m.group(1).split()


def read_build_plan(app_dir: Path, config: str) -> set[str]:
    """The Swift sources llbuild was asked to compile in the build that just ran.

    This is the answer to a question object files cannot settle. An object outlives the target
    that produced it, so if SwiftPM stopped building a still-declared target every object would
    remain on disk and an oracle resting on artifacts alone would go on reporting the directory
    compiled. That is the exact shape the review lane warned about when this item
    was armed: an `executableTarget` no test depends on might not be built at all.

    The plan is regenerated for each build, so a target missing from it was not part of this one.
    Objects say a compile once happened; the plan says this build asked for it. A claim needs both.
    """
    plan = app_dir / ".build" / f"{config}.yaml"
    if not plan.exists():
        raise Unreadable(
            f"no build plan at {plan} — without it, an object file cannot be distinguished from "
            "a leftover of a build that no longer happens, which is the failure this gate exists "
            "to catch"
        )
    text = plan.read_text(encoding="utf-8", errors="replace")
    return set(re.findall(r'"(/[^"]+\.swift)"', text))


# A build that is fully up to date prints exactly these steps, and they run on every invocation
# whether or not anything needed doing. Every OTHER step line means llbuild found work outstanding.
# The list is a whitelist rather than a blacklist on purpose: an unrecognised step counts as work
# and the gate goes red, where a blacklist would let an unrecognised compile step read as clean —
# and a compile step reading as clean is the exact defect this whole file exists to refuse.
BENIGN_STEPS = re.compile(r"^(?:Write\b|Planning build\b|Copying\b)")

STEP = re.compile(r"^\[\s*\d+/\d+\]\s+(?P<step>.*\S)\s*$")
COMPILING = re.compile(r"^Compiling\s+(?P<target>\S+)\s+(?P<sources>\S.*)$")


def probe_remaining_work(
    app_dir: Path, config: str, output: str | None = None
) -> tuple[dict[str, set[str]], list[str]]:
    """Ask SwiftPM whether the build that just ran left anything undone.

    This is the freshness oracle, and it is the tool's own answer rather than an inference from
    the filesystem. A build that compiles nothing is a build with nothing left to compile, so
    every declared source's object describes the tree as it stands. The header explains at length
    why no mtime on disk can be asked this question.

    `--build-tests` is not decoration. `make test` runs `swift test`, which plans test targets as
    well as products; a bare `swift build` plans only products, and since both write the same
    `.build/<config>.yaml` the probe would replace the build plan this report reads two steps
    later with a narrower one, and every test source would report as absent from it. Measured
    2026-08-27: after `swift test list`, `swift build --build-tests` compiles nothing and returns
    in 0.73s, so the two are a fixed point and the probe is a sub-second no-op on a settled tree.

    The probe repairs what it reports, because SwiftPM has no dry-run. That is honest rather than
    convenient: the finding says the suite ran against a tree that was not the current one, which
    stays true after the repair, and the next run is green because it genuinely tested the current
    tree rather than because the evidence was tidied away.

    Returns (per-target recompiled source basenames, unattributable step lines).
    """
    if output is None:
        try:
            proc = subprocess.run(
                ["swift", "build", "--build-tests", "--configuration", config],
                cwd=app_dir, capture_output=True, text=True, timeout=1800,
            )
        except (OSError, subprocess.TimeoutExpired) as exc:
            raise Unreadable(f"could not ask SwiftPM for remaining work in {app_dir}: {exc}") from exc
        if proc.returncode != 0:
            raise Unreadable(
                f"the freshness probe `swift build --build-tests` exited {proc.returncode}, so "
                "whether the suite compiled the current tree is unknown:\n"
                + (proc.stderr.strip() or proc.stdout.strip())[:2000]
            )
        output = proc.stdout + "\n" + proc.stderr

    per_target: dict[str, set[str]] = {}
    unattributed: list[str] = []
    for line in output.splitlines():
        m = STEP.match(line.strip())
        if not m:
            continue
        step = m.group("step")
        if BENIGN_STEPS.match(step):
            continue
        c = COMPILING.match(step)
        if c:
            srcs = {s.strip() for s in c.group("sources").split(",") if s.strip()}
            if srcs:
                per_target.setdefault(c.group("target"), set()).update(srcs)
                continue
        unattributed.append(step)
    return per_target, unattributed


def resolve_build_root(app_dir: Path, config: str) -> Path:
    """Where this toolchain puts objects, asked rather than guessed.

    Globbing `.build/*/<config>` returns one directory per architecture ever built here, and
    picking one of several — a Rosetta `x86_64-apple-macosx` beside a native `arm64-apple-macosx`,
    or a stale triple left by a deployment-target bump — reads objects from a build unrelated to
    the one that just ran. `swift build --show-bin-path` is the toolchain's own answer for the
    configuration in force. An ambiguous glob is refused rather than resolved by sort order.
    """
    try:
        proc = subprocess.run(
            ["swift", "build", "--configuration", config, "--show-bin-path"],
            cwd=app_dir, capture_output=True, text=True, timeout=600,
        )
        if proc.returncode == 0 and proc.stdout.strip():
            root = Path(proc.stdout.strip().splitlines()[-1])
            if root.is_dir():
                return root
    except (OSError, subprocess.TimeoutExpired):
        pass

    roots = []
    globbed = Tally("build roots under .build", f"{app_dir}/.build/*/{config}")
    for r in sorted((app_dir / ".build").glob(f"*/{config}")):
        if r.is_dir():
            roots.append(globbed.keep(r))
        else:
            globbed.drop(r, "matched the glob but is not a directory")
    for reason, n in globbed.reasons().items():
        print(f"  note: {n} path(s) under .build ignored — {reason}", file=sys.stderr)
    if not roots:
        raise Unreadable(
            f"no build root at {app_dir}/.build/*/{config} — this report must run after the suite "
            "builds, because it reports what was compiled rather than what was declared"
        )
    if len(roots) > 1:
        raise Unreadable(
            "several build roots exist and the toolchain would not name one: "
            + ", ".join(str(r.relative_to(app_dir)) for r in roots)
            + " — reading objects from the wrong architecture would report a directory compiled "
              "by a build that did not just run"
        )
    return roots[0]


def attribute_objects(
    app_dir: Path, targets: list[SwiftPMTarget], config: str
) -> tuple[Path, list[str]]:
    """Attach per-source object, build-plan AND freshness evidence to each target.

    A source counts as compiled when it is in the plan for this build, carries an object, and was
    not something SwiftPM still had work to do for. Each half alone is defeatable: the plan without
    the object says the build intended a compile that may never have produced anything, the object
    without the plan says a compile happened at some point in history, and either without the
    freshness probe says nothing about whether it happened over the tree that is here now.

    The probe runs first because it may write `.build/<config>.yaml`, which `read_build_plan` reads
    immediately after — the plan this report describes must be the one in force when it is read.
    """
    remaining, unattributed = probe_remaining_work(app_dir, config)
    root = resolve_build_root(app_dir, config)
    planned = read_build_plan(app_dir, config)

    for tgt in targets:
        objdir = root / f"{tgt.name}.build"
        # Whole-module builds emit one object for the module instead of one per source, so the
        # per-source lookup below would report every file uncompiled. That is a FALSE RED rather
        # than a false green, but a gate that cannot be trusted when it is red gets switched off,
        # so it refuses instead of guessing. `make test` builds debug non-WMO, where per-source
        # objects are what SwiftPM emits.
        per_source = list(objdir.glob("*.swift.o"))
        if tgt.sources and not per_source and (objdir / f"{tgt.name}.o").exists():
            raise Unreadable(
                f"target `{tgt.name}` was built whole-module: one object for the module rather "
                "than one per source, so this gate cannot say which sources were compiled"
            )
        for src in tgt.sources:
            src_path = app_dir / tgt.path / src
            obj = objdir / f"{Path(src).name}.o"
            if str(src_path.resolve()) not in planned:
                tgt.unplanned.append(src)
            elif not obj.exists():
                tgt.missing.append(src)
            elif Path(src).name in remaining.get(tgt.name, frozenset()):
                tgt.stale.append(src)
            else:
                tgt.compiled.append(src)
    return root, unattributed


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
    tallies: list[Tally] | None = None,
    unattributed_work: list[str] | None = None,
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
        if tgt.unplanned:
            rep.fail("unbuilt-target",
                     f"SwiftPM target `{tgt.name}` is declared at {tgt.path} and "
                     f"{len(tgt.unplanned)} of its source(s) are absent from the build plan for "
                     f"this run: {', '.join(tgt.unplanned[:5])}. The lane no longer builds them, "
                     f"and any object still on disk is a leftover rather than evidence.")
        if tgt.stale:
            rep.fail("stale-object",
                     f"SwiftPM had work left for source(s) of `{tgt.name}` after the suite built: "
                     f"{', '.join(tgt.stale[:5])}. Asked to build again, it compiled them, so what "
                     f"the suite ran against was not the tree that is here now. The green "
                     f"describes a previous tree.")

    for step in unattributed_work or []:
        rep.fail("build-work-remaining",
                 f"asked to build again after the suite, SwiftPM did `{step}` — work the suite "
                 f"left outstanding that this report cannot pin to a declared source. Unrecognised "
                 f"build steps count as work rather than as clean, so this may be a step that is "
                 f"always benign; it is red until the step is known to be one.")

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

    # What the readers behind this report did NOT read. A report about a lane that was silent over
    # a directory has no business being silent about its own input.
    for tally in tallies or []:
        reasons = ", ".join(f"{n} {why}" for why, n in tally.reasons().most_common())
        rep.say("")
        rep.say(f"  read {tally.source}: kept {len(tally.kept)} of {tally.total} lines for "
                f"`{tally.subject}`; dropped {reasons or 'nothing'}")

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


def _tgt(name: str, path: str, n: int, *, compiled: int | None = None, stale: int = 0,
         unplanned: int = 0) -> SwiftPMTarget:
    srcs = [f"{name}{i}.swift" for i in range(n)]
    t = SwiftPMTarget(name=name, kind="library", path=path, sources=srcs)
    c = n if compiled is None else compiled
    t.compiled = srcs[:c]
    t.stale = srcs[c:c + stale]
    t.unplanned = srcs[c + stale:c + stale + unplanned]
    t.missing = srcs[c + stale + unplanned:]
    return t


def _clean_targets() -> list[SwiftPMTarget]:
    return [_tgt("MCPRouterKit", "Sources/MCPRouterKit", 3), _tgt("MCPRouterApp", "MCPRouter", 1)]


def _run(targets, yml=CLEAN_YML, make=CLEAN_MAKE, unattributed=None):
    paths, yml_tally = read_project_yml(yml)
    ios, ios_tally = read_ios_platforms(yml)
    return analyse("MCPRouterKit", targets, paths, ios, read_all_target(make),
                   "arm64-apple-macosx/debug", tallies=[yml_tally, ios_tally],
                   unattributed_work=unattributed)


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

    # 3. The suite built, and SwiftPM still had work to do for a source afterwards.
    r = _run([_tgt("MCPRouterKit", "Sources/MCPRouterKit", 3),
              _tgt("MCPRouterApp", "MCPRouter", 1, compiled=0, stale=1)])
    arms.append(("poison", "source SwiftPM still had work for -> stale-object",
                 any(f.code == "stale-object" for f in r.findings)))

    # 4. The iOS directories are excused only because another lane in the same gate reads them.
    #    Take that lane out of `all` and the excuse is gone.
    r = _run(_clean_targets(), make="all: tools lint build test parity\n")
    arms.append(("poison", "iOS lanes removed from `make all` -> uncovered-path",
                 any(f.code == "uncovered-path" for f in r.findings)))

    # 5. The hole an out-of-family review found in the first cut of this gate: the target is
    #    still DECLARED and its objects are still on disk and still newer than sources nobody
    #    edited, but the lane has stopped building it. Objects and mtimes both read clean; only
    #    the build plan for this run knows. Without this arm the gate reports a green over a
    #    directory it did not compile, which is M33 rebuilt one level up.
    r = _run([_tgt("MCPRouterKit", "Sources/MCPRouterKit", 3),
              _tgt("MCPRouterApp", "MCPRouter", 1, compiled=0, unplanned=1)])
    arms.append(("poison", "declared target absent from this build's plan -> unbuilt-target",
                 any(f.code == "unbuilt-target" for f in r.findings)))

    # 6. Two sources sharing a basename, so one object would vouch for both.
    collide = _tgt("MCPRouterKit", "Sources/MCPRouterKit", 1)
    collide.sources = ["A/Same.swift", "B/Same.swift"]
    collide.compiled = list(collide.sources)
    r = _run([collide, _tgt("MCPRouterApp", "MCPRouter", 1)])
    arms.append(("poison", "two sources sharing a basename -> basename-collision",
                 any(f.code == "basename-collision" for f in r.findings)))

    # 7. The freshness probe's reading of a build that had work left, and of one that did not.
    #    These are the arms that stand where the mtime comparison used to: the header records why
    #    a `.o` can be older than the source it perfectly describes, so the oracle is llbuild's own
    #    verdict and these prove the verdict is read in both directions.
    settled = ("Building for debugging...\n"
               "[0/12] Write swift-version--58304C5D6DBC2206.txt\n"
               "Build complete! (0.15s)\n")
    per_target, unattr = probe_remaining_work(Path("."), "debug", output=settled)
    arms.append(("null", "up-to-date build output -> no work attributed",
                 per_target == {} and unattr == []))

    worked = ("Building for debugging...\n"
              "[0/12] Write swift-version--58304C5D6DBC2206.txt\n"
              "[4/8] Compiling MCPRouterUI Controls.swift, Palette.swift\n"
              "Build complete! (1.47s)\n")
    per_target, unattr = probe_remaining_work(Path("."), "debug", output=worked)
    arms.append(("poison", "`Compiling` after the suite -> attributed to that target's sources",
                 per_target == {"MCPRouterUI": {"Controls.swift", "Palette.swift"}} and unattr == []))

    # 8. A step the whitelist does not know is work, not silence. A blacklist would read it clean.
    odd = "[3/9] Emitting module MCPRouterUI\nBuild complete! (0.9s)\n"
    r = _run(_clean_targets(), unattributed=probe_remaining_work(Path("."), "debug", output=odd)[1])
    arms.append(("poison", "unrecognised build step -> build-work-remaining",
                 any(f.code == "build-work-remaining" for f in r.findings)))

    # 9-11. Null arms. Nothing to read must be a refusal, never a clean report.
    for label, fn in (
        ("empty describe JSON", lambda: read_declaration(Path("."), describe_json="{}")),
        ("project.yml with no source paths", lambda: read_project_yml("name: X\ntargets:\n")[0]),
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
        build_root, unattributed = attribute_objects(app_dir, targets, args.configuration)
        yml_text = (app_dir / "project.yml").read_text(encoding="utf-8")
        yml_paths, yml_tally = read_project_yml(yml_text)
        ios_targets, ios_tally = read_ios_platforms(yml_text)
        all_prereqs = read_all_target((repo / "Makefile").read_text(encoding="utf-8"))
    except (Unreadable, OSError) as exc:
        print(f"error: the build description could not be reported: {exc}", file=sys.stderr)
        print("error: 'cannot tell what was compiled' is not 'everything was compiled'", file=sys.stderr)
        return 2

    rep = analyse(package_name, targets, yml_paths, ios_targets, all_prereqs,
                  str(build_root.relative_to(app_dir)), tallies=[yml_tally, ios_tally],
                  unattributed_work=unattributed)
    print("\n".join(rep.lines))
    return 1 if rep.findings else 0


if __name__ == "__main__":
    sys.exit(main())
