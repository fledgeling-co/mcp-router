#!/usr/bin/env python3
"""The Windows half of the surface denominator, reconciled against the shell's own source.

WHY THIS EXISTS BESIDE `surface-reconcile.py`
---------------------------------------------
`bin/surface-reconcile.py` is the Mac reconciler G18 built after G14 found three shipped surfaces
with no row in the campaign to be uncovered in. It derives the denominator from the product by
building and running `bin/surface-oracle.swift`, so it needs `swift` and it does not run on a
Windows host at all: measured 2026-09-02 on `LUKESFF`, it dies in `subprocess.run` with
`FileNotFoundError: [WinError 2]`. Windows shipped ten destinations and three non-glass planes
since, and nothing reconciled any of them.

So this reads the same question off the C# instead, statically, with no build:

  R1  Every id in `DestinationCatalog.All` has a surface whose route is `app://windows/shell#<id>`.
      This is G14's finding as a rule: a destination the shell can open and the campaign never
      enumerated is invisible to every completeness check keyed on enumeration.

  R2  Every Label in `DestinationCatalog.All` is a declared control on the shell surface
      (`app://windows/shell`). This is G28's finding as a rule, on the Windows side: the pane item
      is the control a case presses to reach a board, and until 2026-09-02 the shell row declared
      the four MenuBar titles and none of the ten pane items, so ten passing cases actuated
      controls no surface declared and `control-census.py` refused all ten as strays.

  R3  Every requirement whose `source` names a path under `app/windows/` and that has at least one
      case reaches a surface that exists: some case of that requirement names a `surface` (or an
      `actuatesSurface`) present in `inventory.json`. REQ-035, REQ-036 and REQ-037 were each
      stated, each shipped and each measured by a passing case, and none of the three had a
      surface row - the same shape as G14, found on Windows from the census end rather than by
      counting.

  R4  Every Windows surface that declares `controls` also declares a `controlsSource` saying where
      the list came from, and where that source names a `.xaml` file, every control it declares
      appears verbatim in one of those files. This is the other half of G28's brief: a denominator
      is only as good as its provenance, and fourteen Windows rows carried a control list with
      nothing saying whether it was read off the source, off a UIA dump of the build, or off
      nobody. A list read off the build cannot contain a control the build failed to draw, so
      "where did this come from" is not bookkeeping - it decides whether a missing control can
      ever appear as missing.

THE RECORDER IS NOT THE WRITER
------------------------------
Nothing here reads the registry to check the registry. The denominator comes from C# source that
the WinUI compiler enforces - `ShellWindow` builds its pane by iterating `DestinationCatalog.All`,
so a destination cannot reach a user without appearing in the list this parses - and the registry
is the thing being judged against it. A row somebody types into `inventory.json` cannot make R1 or
R2 pass, and deleting a row cannot make them pass either.

WHAT IT DOES NOT CHECK, said here rather than implied by a green
----------------------------------------------------------------
  * That a declared control is drawn, is reachable, or does anything. That is
    `control-census.py`'s actuated count and the UIA lane behind it.
  * That a surface's OTHER controls are complete. R2 covers the pane items and the shell only;
    each board's own control list is declared per row with its `controlsSource`, and no static
    reader here can tell a complete list from a short one. R4 checks that every declared control
    is real in the source; it cannot check that every control in the source is declared, because
    a board's affordances built in a DataTemplate or in code-behind carry no literal name a static
    reader can see. Every such row says so in its `controlsSourceNote`, and the number is a floor.
  * A surface whose `controlsSource` names only `.cs` files. SURF-045..047's controls are
    operations rather than literals, so R4 checks the presence of the source sentence and stops
    there rather than pretending to verify the names.
  * The non-glass planes' controls. SURF-045..047 declare operations rather than pressable
    controls; DEF-080 records that objection.

EXITS
-----
    0  every rule holds
    1  a rule is broken; each finding names the source fact and the registry fact
    2  the control failed - `DestinationCatalog.cs` parsed to fewer than the ten destinations it
       is known to carry, which means the parser broke rather than the registry being clean. A
       reader that finds nothing must not report a pass.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
CAMPAIGN = ROOT / "planning" / "test-campaign"
CATALOG = ROOT / "app" / "windows" / "MCPRouter.Shell.Model" / "DestinationCatalog.cs"
SHELL_ROUTE = "app://windows/shell"

# `new Destination("<id>", "<Label>", ...` - id and Label are the first two arguments, and both
# are string literals or one of the two `const string` ids declared at the top of the class.
CTOR = re.compile(r"new\s+Destination\(\s*([A-Za-z\"][^,]*?)\s*,\s*\"([^\"]+)\"", re.S)
CONST = re.compile(r'public\s+const\s+string\s+(\w+)\s*=\s*"([^"]+)"')
# A repo-relative source path, as it appears inside a `controlsSource` sentence.
SRC_PATH = re.compile(r"(app/windows/[\w./-]+\.(?:xaml|cs))")


def destinations() -> list[tuple[str, str]]:
    """(id, Label) for every destination the shell's pane is built from."""
    src = CATALOG.read_text(encoding="utf-8-sig")
    consts = dict(CONST.findall(src))
    out = []
    for raw_id, label in CTOR.findall(src):
        raw_id = raw_id.strip()
        if raw_id.startswith('"'):
            ident = raw_id.strip('"')
        else:
            ident = consts.get(raw_id.split(".")[-1], "")
        out.append((ident, label))
    return out


def main() -> int:
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")
        except (AttributeError, ValueError):
            pass

    if not CATALOG.is_file():
        print("win-surface-reconcile: %s is absent; this run measured nothing"
              % CATALOG.relative_to(ROOT).as_posix(), file=sys.stderr)
        return 2

    dests = destinations()
    if len(dests) < 10 or any(not i for i, _ in dests):
        print("win-surface-reconcile: parsed %d destination(s) from DestinationCatalog.cs, and it "
              "is known to carry ten. The reader broke, so nothing below is a verdict."
              % len(dests), file=sys.stderr)
        return 2

    inv = json.loads((CAMPAIGN / "inventory.json").read_text(encoding="utf-8-sig"))
    cases = json.loads((CAMPAIGN / "cases.json").read_text(encoding="utf-8-sig"))
    surfaces = inv.get("surface", [])
    by_route = {s.get("route"): s for s in surfaces}
    ids = {s.get("id") for s in surfaces}

    findings: list[str] = []

    # R1 -- a destination with no row to be uncovered in.
    for ident, label in dests:
        route = "%s#%s" % (SHELL_ROUTE, ident)
        if route not in by_route:
            findings.append(
                "R1  DestinationCatalog ships `%s` (%s) and no surface carries the route `%s`. "
                "A destination nobody enumerated cannot be reported uncovered."
                % (ident, label, route))

    # R2 -- the pane item is a control, and the shell is the surface that carries it.
    shell = by_route.get(SHELL_ROUTE)
    if shell is None:
        findings.append("R2  no surface carries the route `%s`, so the shell's own controls have "
                        "nowhere to be declared." % SHELL_ROUTE)
    else:
        declared = set(shell.get("controls") or [])
        for ident, label in dests:
            if label not in declared:
                findings.append(
                    "R2  the pane item `%s` is built from DestinationCatalog and is not among %s's "
                    "declared controls. A case pressing it actuates a control no surface declares."
                    % (label, shell.get("id")))

    # R3 -- a shipped Windows requirement whose measurement belongs to no surface.
    reqs = {r.get("id"): r for r in inv.get("requirement", [])}
    cases_by_req: dict[str, list[dict]] = {}
    for c in cases:
        cases_by_req.setdefault(c.get("req"), []).append(c)
    for rid, r in sorted(reqs.items()):
        if "app/windows/" not in (r.get("source") or ""):
            continue
        mine = cases_by_req.get(rid) or []
        if not mine:
            continue  # no case is a coverage gap, not a denominator gap; reckon owns that class
        reached = {c.get("surface") for c in mine} | {c.get("actuatesSurface") for c in mine}
        if not (reached & ids):
            findings.append(
                "R3  %s is sourced from app/windows/ and has %d case(s), and none of them names a "
                "surface in the registry (saw %s). The measurement exists and the thing it "
                "measured is not in the denominator."
                % (rid, len(mine), ", ".join(sorted(str(x) for x in reached)) or "nothing"))

    # R4 -- a declared control list with no provenance, and a provenance that does not hold up.
    for s in surfaces:
        route = s.get("route") or ""
        if not route.startswith("app://windows/") and not route.startswith(("task://windows/",
                                                                            "shell://windows/",
                                                                            "package://windows/")):
            continue
        controls = s.get("controls") or []
        if not controls:
            continue  # an empty list is itself a finding, and SURF-044 states why in its note
        src = (s.get("controlsSource") or "").strip()
        if not src:
            findings.append(
                "R4  %s declares %d control(s) and no `controlsSource`. Nothing says whether the "
                "list was read off the design, off the source, or off a UIA dump of the build, so "
                "nothing says whether a control the build never drew could appear in it."
                % (s.get("id"), len(controls)))
            continue
        named = [ROOT / q for q in dict.fromkeys(SRC_PATH.findall(src))]
        missing = [q for q in named if not q.is_file()]
        if missing:
            findings.append(
                "R4  %s's `controlsSource` names %s, which does not exist. A provenance pointing "
                "at nothing is worse than none, because it reads as checked."
                % (s.get("id"), ", ".join(q.as_posix() for q in missing)))
            continue
        # The literal check runs on the glass routes only. SURF-045..047 are the non-glass planes
        # and their `controls` are operations a lane calls rather than names anything renders, so
        # asking whether `MakeAppx pack` appears verbatim in a .cs file would redden a row that is
        # honest. Their provenance sentence is checked; their names are not, and DEF-080 is the
        # standing record that the registry has one word for two different things.
        if not route.startswith("app://windows/") or not named:
            continue
        blob = "\n".join(q.read_text(encoding="utf-8-sig") for q in named)
        for c in controls:
            if c not in blob:
                findings.append(
                    "R4  %s declares the control `%s` and it appears in none of the file(s) its "
                    "`controlsSource` names (%s). Either the source moved or the list is stale."
                    % (s.get("id"), c, ", ".join(q.name for q in named)))

    win_surfaces = [s for s in surfaces if "windows" in (s.get("route") or "")]
    print("win-surface-reconcile: %d destination(s) in DestinationCatalog.cs · %d Windows "
          "surface(s) in the registry · %d requirement(s) sourced from app/windows/"
          % (len(dests), len(win_surfaces),
             sum(1 for r in reqs.values() if "app/windows/" in (r.get("source") or ""))))

    if findings:
        print("\n%d finding(s):" % len(findings), file=sys.stderr)
        for f in findings:
            print("  · " + f, file=sys.stderr)
        return 1

    print("  R1 every destination has a surface · R2 every pane item is a declared shell control · "
          "R3 every measured Windows requirement reaches a surface that exists · "
          "R4 every declared control list names its source and holds up against it")
    return 0


if __name__ == "__main__":
    sys.exit(main())
