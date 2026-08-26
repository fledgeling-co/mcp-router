#!/usr/bin/env python3
"""Which branches' green `swift test` covered nothing under `app/MCPRouter/`.

M33's third clause. Until `MCPRouterApp` was added to `app/Package.swift`, the SwiftPM lane
declared no target over `app/MCPRouter/`, so `swift test` compiled nothing in the directory the
Mac app's assembly lives in and exited 0 anyway. Any branch that changed a file under that
directory while the lane could not read it therefore carries a green that was **silent about**
the directory rather than clean over it. M20 is the known case. This is the rest.

M18 was named alongside it in the brief and **this sweep does not reproduce that**: `ai/m18`'s own
range (`2c5b6ad..72873b6`, via merge `4391f86`) changes no file under `app/MCPRouter/` at all, so
whatever explains M18's recurrence, it is not this directory going uncompiled. Recorded as a
correction rather than forced into the affected set — the sweep's job is the denominator, and an
expected case that does not appear is a result.

## Why the population is not `git branch`

A merged branch is usually deleted, so the refs that survive are a biased sample — the unmerged
ones. Reporting `examined=<live branches>` would put the answer's denominator on the population
least likely to contain the defect. So the population here is the union of:

  * every local branch ref, and
  * every merge commit on the integration branch, whose second parent is the tip of the branch
    that was merged and whose subject usually still names it.

That reaches branches that no longer exist as refs, which is where most of the history is.

## The two questions per unit

  touched   did any commit in the unit's own range change a file under `app/MCPRouter/`?
            The range is derived from the merge (`merge-base(p1, p2)..p2`), never guessed, so a
            branch's own work is separated from what it inherited by branching later.
  armed     does `app/Package.swift` AT THAT TIP declare a target rooted at `MCPRouter`?
            Read out of the tree object rather than from a date, because a branch cut before the
            fix and rebased after it is armed, and a branch cut after it and never rebased is not.

  affected  = touched AND NOT armed.

A unit that never touched the directory is `n/a` — not `clean`. Its green is neither a true nor a
false coverage claim about `app/MCPRouter/`, because it made no claim; folding those into a pass
would inflate the reassuring number with units that were never at risk.

Exit 0 always: this is a census, not a gate. The number it must never print is a bare `affected=0`
with no denominator beside it.
"""

from __future__ import annotations

import re
import subprocess
import sys
from dataclasses import dataclass

INT = "main"
DIRECTORY = "app/MCPRouter/"
PACKAGE = "app/Package.swift"

# The arming, read as a tree fact. `path: "MCPRouter"` with its closing quote, so `MCPRouterIOS`
# does not match — a prefix match here would report every branch armed and the sweep would find
# nothing, which is the failure mode that looks most like success.
ARMED = re.compile(r'path:\s*"MCPRouter"')


def git(*args: str) -> str:
    return subprocess.run(["git", *args], capture_output=True, text=True,
                          cwd=None, check=False).stdout.strip()


def git_ok(*args: str) -> bool:
    return subprocess.run(["git", *args], capture_output=True, text=True).returncode == 0


@dataclass
class Unit:
    name: str
    tip: str
    base: str
    origin: str          # "ref" | "merge"
    swift: list[str]     # .swift files under the directory — what the lane would compile
    other: list[str]     # resources under it; Package.swift excludes these, so they are not a claim
    armed: bool | None   # None = no Package.swift at that tip

    @property
    def verdict(self) -> str:
        if not self.swift:
            return "n/a"
        if self.armed is None:
            return "affected"
        return "covered" if self.armed else "affected"


def collect() -> list[Unit]:
    units: dict[str, Unit] = {}

    # --- merges on the integration branch: reaches branches that no longer have a ref.
    for line in git("log", "--merges", "--format=%H %P|%s", INT).splitlines():
        shas, _, subject = line.partition("|")
        parts = shas.split()
        if len(parts) < 3:
            continue                       # not a two-parent merge
        _, p1, p2 = parts[0], parts[1], parts[2]

        # A BACKFLOW merge — `Merge main into ai/xyz` — has the integration branch as its SECOND
        # parent, so `merge-base(p1, p2)..p2` is a range of main's own commits. Left in, main is
        # examined as though it were a branch and every file it accumulated is attributed to it a
        # second time, on top of the branch that actually changed them. Measured on this history:
        # 56 of the 147 two-parent merges are backflow (25 spelled `Merge main into ...`, caught
        # here; 31 spelled `Merge branch 'main' into ...`, caught by the `name == INT` test below).
        # Two of them carried main's own touch of the directory, and left in they inflated
        # `affected` from 7 to 9 — main counted twice as though it were a branch.
        if BACKFLOW.match(subject):
            continue

        m = re.search(r"Merge\s+(?:branch\s+)?'?([A-Za-z0-9._/-]+)'?", subject)
        name = m.group(1).rstrip(":") if m else f"merge:{parts[0][:7]}"
        if name == INT:
            continue
        base = git("merge-base", p1, p2)
        if not base:
            continue
        units.setdefault(p2, _unit(name, p2, base, "merge"))

    # --- live refs, including the unmerged ones the merges above cannot see.
    for name in git("for-each-ref", "--format=%(refname:short)", "refs/heads").splitlines():
        if name == INT:
            continue
        tip = git("rev-parse", name)
        if tip in units:
            units[tip].name = name         # prefer the real ref name over one parsed from a subject
            continue
        base = _base_for_ref(tip)
        if not base:
            continue
        units[tip] = _unit(name, tip, base, "ref")

    return sorted(units.values(), key=lambda u: u.name)


def _base_for_ref(tip: str) -> str:
    """The point a ref's own work starts.

    For an UNMERGED ref that is `merge-base(INT, tip)`. For a ref that has been merged and whose
    branch still exists, `merge-base(INT, tip)` collapses to the tip itself and the range is empty
    — the branch would report as having touched nothing, whatever it did. `ai/m18` is exactly that
    shape, and it is one of the two branches this sweep was told to expect a verdict on, so the
    collapse would have silently answered the question it was asked. So a merged ref is resolved
    through the merge commit that first contains it instead.
    """
    mb = git("merge-base", INT, tip)
    if mb != tip:
        return mb
    merge = git("rev-list", "--ancestry-path", f"{tip}..{INT}", "--merges").splitlines()
    if not merge:
        return ""                          # merged by fast-forward: no branch-shaped range exists
    return git("merge-base", git("rev-parse", f"{merge[-1]}^1"), tip)


def _unit(name: str, tip: str, base: str, origin: str) -> Unit:
    touched = sorted({
        p for p in git("log", "--format=", "--name-only", f"{base}..{tip}", "--", DIRECTORY).splitlines()
        if p.strip()
    })
    # `Package.swift` excludes Info.plist, the entitlements and Assets.xcassets from the app target,
    # so a branch that only changed an app icon made no claim the SwiftPM lane could have checked
    # either before or after the arming. Counting those as affected would report the fix as more
    # overdue than it was. Measured on this history the split changes no verdict — `F1` is the only
    # unit with resources under the directory (10 icon files) and it also changed `MCPRouterApp.swift`,
    # so it is affected on the .swift file rather than on the icons. The split is here because a
    # resource-only branch would otherwise be reported as a coverage failure it never was.
    swift = [p for p in touched if p.endswith(".swift")]
    other = [p for p in touched if not p.endswith(".swift")]
    pkg = git("show", f"{tip}:{PACKAGE}") if git_ok("cat-file", "-e", f"{tip}:{PACKAGE}") else None
    return Unit(name, tip, base, origin, swift, other, None if pkg is None else bool(ARMED.search(pkg)))


BACKFLOW = re.compile(rf"\s*Merge\s+{re.escape(INT)}\b")


def selftest() -> int:
    """Prove each verdict is reachable and each exclusion fires.

    The live sweep reports `covered=0`, because no branch has yet changed a `.swift` file under
    the directory since the target was armed. A classifier whose only observed output is
    `affected` has not been shown to distinguish anything, so the positive case is proved here
    rather than assumed — and was proved once against the real repository too, with a planted
    branch that carried one commit touching `MCPRouterApp.swift` on an armed `Package.swift`:
    it reported `covered=1` while the seven stayed `affected`, and deleting it returned the
    census to `examined=100 affected=7 covered=0` with the source blob byte-identical
    (sha256 `3ae480004c9b` both ends).
    """
    def u(swift, other, armed):
        return Unit("t", "0" * 40, "0" * 40, "ref", swift, other, armed)

    arms = [
        ("verdict", "changed .swift, target NOT declared -> affected",
         u(["a.swift"], [], False).verdict == "affected"),
        ("verdict", "changed .swift, target declared     -> covered",
         u(["a.swift"], [], True).verdict == "covered"),
        ("verdict", "changed .swift, no Package.swift     -> affected",
         u(["a.swift"], [], None).verdict == "affected"),
        ("verdict", "changed only excluded resources      -> n/a",
         u([], ["Assets.xcassets/x.png"], False).verdict == "n/a"),
        ("exclude", "`Merge main into ai/x` is backflow",
         bool(BACKFLOW.match("Merge main into ai/m19: aligned"))),
        ("exclude", "`Merge branch 'main' into ai/x` parses to the integration branch",
         (re.search(r"Merge\s+(?:branch\s+)?'?([A-Za-z0-9._/-]+)'?",
                    "Merge branch 'main' into ai/m18").group(1) == INT)),
        ("guard", "the arming regex does not match MCPRouterIOS",
         ARMED.search('path: "MCPRouterIOS"') is None and ARMED.search('path: "MCPRouter"') is not None),
    ]
    width = max(len(d) for _, d, _ in arms)
    bad = 0
    for kind, detail, bit in arms:
        print(f"  {kind:<8} {detail:<{width}}  {'bit' if bit else 'DID NOT BITE'}")
        bad += 0 if bit else 1
    print(f"selftest: {len(arms) - bad}/{len(arms)} arms bit")
    return 1 if bad else 0


def main() -> int:
    if "--selftest" in sys.argv:
        return selftest()
    units = collect()
    if not units:
        print("error: the sweep enumerated no branch — a census over nothing is a usage error, "
              "not an empty result", file=sys.stderr)
        return 2

    head = git("rev-parse", INT)
    print(f"# M33 branch sweep — frame: `{INT}` at `{head[:7]}`, {git('log', '-1', '--format=%cI', INT)}")
    print()
    print(f"Population: every local branch ref plus every two-parent merge on `{INT}`, "
          f"deduplicated by tip sha.")
    print(f"`affected` = the unit changed a file under `{DIRECTORY}` while `{PACKAGE}` at its tip "
          f"declared no target rooted there, so its `swift test` compiled none of what it changed.")
    print()

    rows = [u for u in units if u.verdict != "n/a"]
    print("| unit | tip | origin | .swift under app/MCPRouter/ | resources | Package.swift armed | verdict |")
    print("| --- | --- | --- | --- | --- | --- | --- |")
    for u in rows:
        armed = {True: "yes", False: "**no**", None: "absent"}[u.armed]
        print(f"| `{u.name}` | `{u.tip[:7]}` | {u.origin} | "
              f"{len(u.swift)} ({', '.join(p.split('/')[-1] for p in u.swift[:3])}) | "
              f"{len(u.other)} | {armed} | **{u.verdict}** |")
    if not rows:
        print("| — | — | — | — | — | — | no unit changed a .swift file under the directory |")

    resource_only = [u for u in units if not u.swift and u.other]
    if resource_only:
        print()
        print("Resource-only units — they changed files under the directory that "
              "`Package.swift` excludes from the target, so no lane compiled them before the fix "
              "or after it, and they are `n/a` rather than `affected`:")
        for u in resource_only:
            print(f"  - `{u.name}` (`{u.tip[:7]}`) — {len(u.other)} file(s), 0 .swift")

    examined = len(units)
    affected = sum(1 for u in units if u.verdict == "affected")
    covered = sum(1 for u in units if u.verdict == "covered")
    na = sum(1 for u in units if u.verdict == "n/a")
    print()
    print(f"**examined={examined} affected={affected} covered={covered} n/a={na}**")
    print()
    print(f"{na} of the {examined} changed no .swift file under `{DIRECTORY}` and are `n/a` rather "
          f"than `clean`: they made no coverage claim about it either way. The denominator that "
          f"matters for the defect is the {affected + covered} that did.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
