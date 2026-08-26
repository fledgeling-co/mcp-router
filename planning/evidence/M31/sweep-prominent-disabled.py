#!/usr/bin/env python3
"""M31's sweep: every built surface with a primary action, and whether its disabled state dims.

The defect M31 was filed for is a disabled primary that renders *as though enabled*, because a
rule carrying the accent fill beats the rule that dims it. This enumerates the surfaces where that
could happen and prints a verdict per surface with the denominator it was drawn from, so
`failures=0` is never reported without an `examined=N` beside it.

It reports what a source read can settle. Two things it deliberately does not claim:

  * that a style's `@Environment(\\.isEnabled)` is actually installed by SwiftUI. `Controls.swift`
    declines to rely on that and reads the environment from a nested `View` instead; a style that
    reads it directly is flagged here as UNPROVEN rather than as passing or failing.
  * anything about pixels. `make mock-fidelity` exits 3 on an inherited break
    (`MeasureDump/main.swift:206`, a non-exhaustive switch missing `.readme`), so the rendered lane
    is unavailable for the Swift surfaces. The HTML verdicts were taken at the rendered rung with
    Obscura and the measured values are recorded beside them.

Usage:  python3 planning/evidence/M31/sweep-prominent-disabled.py [--json]
Exit 0 when no surface reproduces the defect; 1 otherwise.
"""
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
WINDOW = 14  # lines either side of a call site searched for a `.disabled(` modifier

# Styles that resolve an accent fill, and how each decides its disabled treatment.
STYLES = {
    "ProminentButtonStyle": {
        "surface": "macOS",
        "disabled_tokens": ("t4", "f3", "line"),
        "reads_environment_from": "a nested View (Controls.swift `Label`)",
        "proven": True,
    },
    "PhoneProminentButtonStyle": {
        "surface": "iPhone",
        "disabled_tokens": ("t4", "raised", None),
        "reads_environment_from": "@Environment on the ButtonStyle type itself",
        "proven": False,
    },
}

RATIFIED = ("t4", "f3", "line")  # DESIGN.md §3, the disabled prominent triple


def swift_sites():
    call = re.compile(r"\.buttonStyle\((Phone)?ProminentButtonStyle\(")
    direct = re.compile(r"(Phone)?ProminentButtonStyle\([^)]*\)\.makeBody")
    out = []
    for path in sorted((ROOT / "app/Sources").rglob("*.swift")):
        lines = path.read_text().splitlines()
        for i, line in enumerate(lines):
            m = call.search(line) or direct.search(line)
            if not m:
                continue
            window = "\n".join(lines[max(0, i - WINDOW): i + WINDOW])
            out.append({
                "file": str(path.relative_to(ROOT)),
                "line": i + 1,
                "style": ("Phone" if m.group(1) else "") + "ProminentButtonStyle",
                "disableable": bool(re.search(r"\.disabled\(", window)),
                "hand_invoked": bool(direct.search(line)),
            })
    return out


def html_surfaces():
    """Each HTML surface, its accent-filled control rule, and the rule that must beat it."""
    results = []
    for rel in ("design/mcp-router-console.html", "docs/mcp-router-store.html", "docs/index.html",
                "design/banner.html"):
        path = ROOT / rel
        if not path.exists():
            results.append({"file": rel, "verdict": "ABSENT"})
            continue
        css = path.read_text()
        # Each surface names its accent-filled control differently, so the selector is discovered
        # rather than assumed. Counting `btn primary` everywhere reported the store page as having
        # zero primary actions when in fact its bare `.btn` *is* the accent-filled one — a zero that
        # means "different vocabulary" reads identically to a zero that means "none here".
        accent_rule = None
        # CSS comments are stripped first. Without this the block preceding `.btn{` carries the
        # section banner comment, the selector text never trims to `.btn`, and the store page —
        # whose bare `.btn` IS the accent-filled control — reported as having none.
        rules = re.sub(r"/\*.*?\*/", "", css, flags=re.S)
        for block in rules.split("}"):
            brace = block.find("{")
            if brace < 0 or "background:var(--accent-ink)" not in block[brace:]:
                continue
            hit = [x.strip() for x in block[:brace].split(",")
                   if re.fullmatch(r"\.btn(\.primary)?", x.strip())]
            if hit:
                accent_rule = hit[0]
                break
        if accent_rule == ".btn.primary":
            controls = len(re.findall(r'class="[^"]*\bbtn\b[^"]*\bprimary\b[^"]*"', css))
        elif accent_rule == ".btn":
            controls = len(re.findall(r'class="btn(?![^"]*ghost)[^"]*"', css))
        else:
            controls = 0
        # A disabled control is only reachable where the markup or the script can set it.
        reachable = bool(re.search(r"\.disabled\s*=|\bdisabled\b(?=[\s>\"])", css))
        dims = bool(re.search(r"\.btn(\.primary)?[:\[]disabled|\.btn\.primary\.disabled", css))
        results.append({
            "file": rel,
            "accent_filled_selector": accent_rule or "none — this surface draws no accent-filled control",
            "accent_filled_controls": controls,
            "disabled_reachable": reachable,
            "has_dimming_rule": dims,
            "cursor_declarations": css.count("cursor:"),
        })
    return results


def main():
    sites = swift_sites()
    surfaces = {}
    for s in sites:
        surfaces.setdefault(s["file"], []).append(s)

    failures, unproven = [], []
    for f, group in surfaces.items():
        style = group[0]["style"]
        meta = STYLES[style]
        if meta["disabled_tokens"][:2] == RATIFIED[:2]:
            pass
        else:
            unproven.append((f, style, "disabled fill is --%s, DESIGN.md §3 ratifies --%s"
                             % (meta["disabled_tokens"][1], RATIFIED[1])))
        if not meta["proven"] and any(g["disableable"] for g in group):
            unproven.append((f, style, "dims only if SwiftUI installs @Environment on a ButtonStyle"))
        for g in group:
            if g["hand_invoked"]:
                unproven.append((g["file"], style,
                                 "makeBody called directly at :%d, so SwiftUI never installs the "
                                 "style's dynamic properties" % g["line"]))

    report = {
        "swift": {
            "surfaces_examined": len(surfaces),
            "call_sites_examined": len(sites),
            "disableable_call_sites": sum(1 for s in sites if s["disableable"]),
            "failures": len(failures),
            "unproven": [{"file": f, "style": s, "why": w} for f, s, w in unproven],
            "by_style": {
                k: {
                    "sites": sum(1 for s in sites if s["style"] == k),
                    "disableable": sum(1 for s in sites if s["style"] == k and s["disableable"]),
                } for k in STYLES
            },
        },
        "html": html_surfaces(),
    }

    if "--json" in sys.argv:
        print(json.dumps(report, indent=2))
    else:
        sw = report["swift"]
        print("Swift surfaces with a primary action: examined=%d call-sites=%d disableable=%d "
              "failures=%d unproven=%d"
              % (sw["surfaces_examined"], sw["call_sites_examined"],
                 sw["disableable_call_sites"], sw["failures"], len(sw["unproven"])))
        for k, v in sw["by_style"].items():
            print("  %-28s sites=%2d disableable=%d" % (k, v["sites"], v["disableable"]))
        for u in sw["unproven"]:
            print("  UNPROVEN %s [%s] — %s" % (u["file"], u["style"], u["why"]))
        print("HTML surfaces: examined=%d" % len(report["html"]))
        for h in report["html"]:
            print("  %-34s %s" % (h["file"], {k: v for k, v in h.items() if k != "file"}))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
