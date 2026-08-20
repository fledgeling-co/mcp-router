#!/usr/bin/env python3
"""Phase 8, vocabulary vector: what the design of record specifies that the build never renders.

This is the only pass that can see what the build LACKS. A control the design
specifies and the build never drew has no selector, so no assertion fails on it
and no screenshot of the build contains it — the absence is invisible to every
other phase.

Not a pixel diff. The build half is a macOS accessibility tree (axkit dump); the
design half is the prototype's rendered text. They are not framing-comparable —
prescan says so, with a 1.637x scale that is not a DPR step — so the comparison
runs on the words, where framing is irrelevant.

Three subtractions, in the order references/differential.md gives them:
  1. the shell — sidebar rows, window title and menu bar appear on every board,
     so a term present on all of them carries no signal about any one of them;
  2. the tenant's own data — server names, counts, timestamps and durations are
     fixtures, not vocabulary, so anything matching a numeric/identifier shape is
     dropped rather than reported as drift;
  3. what was already decided — terms listed in ACCEPTED below, each with the
     reason it is not a finding.

Prints a denominator per board. `examined=0` is a pass that never ran.
"""
import json, re, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
CAMPAIGN = ROOT / "planning/test-campaign"
AX = CAMPAIGN / "evidence/ax"
MOCK = ROOT / "design/mocks/prototype.html"

BOARDS = [("SURF-002", "servers"), ("SURF-003", "activity"), ("SURF-004", "skills"),
          ("SURF-005", "discover"), ("SURF-006", "evals"), ("SURF-007", "cleanup"),
          ("SURF-008", "inbox"), ("SURF-011", "settings")]

# Decided, with the reason. A term here is not a finding; it is a closed question.
ACCEPTED = {
    "evals": "the mock's board is named Evals and the app's is named Checks — DEF-007, "
             "raised by the capture tie pass; the rename went one way only",
    "conduit": "the prototype carries the product's former name; the app ships as MCP Router",
}

# Comparing every word on both sides was tried first and produced 257 "missing" and
# 274 "drifted" terms across eight boards — a uniform flood, which detector-defects.md
# names as the signature of a dead predicate rather than a broken product. It was
# comparing an app's terse control labels against a prototype's explanatory prose. The
# comparison that carries signal is CONTROLS: a control the design specifies and the
# build never drew has no selector, so nothing else in the campaign can see it.
CONTROL_ROLES = {"AXButton", "AXCheckBox", "AXPopUpButton", "AXTextField", "AXRadioButton",
                 "AXSlider", "AXDisclosureTriangle", "AXMenuItem", "AXTabGroup", "AXLink"}
NUMERICISH = re.compile(r"\d")

def normalise(label: str) -> str:
    """One control, one key — case, punctuation and trailing counts removed."""
    t = re.sub(r"[\u2000-\u206f]", " ", label)
    t = re.sub(r"[^A-Za-z ]+", " ", t)
    return " ".join(t.lower().split())

def is_control_label(key: str) -> bool:
    """Subtraction 2: the tenant's own data, which is a row and not a control.

    Both sides render rows as buttons — a server row, a skill row, an activity line — and
    those carry fixture names and timings that vary per run. A control's accessible name is
    short and imperative; a row's is a sentence. Four words is where the corpus splits on
    these two surfaces: 'Reset call history' and 'Manage marketplaces' survive, 'succeeded
    browser navigate on obscura in mcp router …' does not.
    """
    return bool(key) and 2 < len(key) <= 40 and len(key.split()) <= 4

def ax_controls(sid: str) -> set[str]:
    """Actionable elements the running app published, by accessible name.

    Columns are axkit's: 0 depth, 1 role, 2 subrole, 3 title, 4 value,
    5 description, 6 help, 7 enabled, 8 selected, …
    """
    p = AX / f"{sid}.window.txt"
    if not p.exists():
        return set()
    out = set()
    for line in p.read_text(errors="replace").splitlines():
        cols = line.split("\t")
        if len(cols) < 7 or cols[1] not in CONTROL_ROLES:
            continue
        name = next((c for c in (cols[3], cols[5], cols[4], cols[6]) if c.strip()), "")
        key = normalise(name)
        if is_control_label(key):
            out.add(key)
    return out

# `offsetParent` is 0 for all 39 of the prototype's buttons under the sanctioned engine —
# measured 20 Aug 2026, and consistent with the divergences already recorded for it. Using
# it as the visibility filter returned zero controls on every board, which read as "the
# design specifies nothing" rather than as a broken probe. getBoundingClientRect() is
# documented correct on this engine, so visibility is taken from the box.
MOCK_CONTROLS_JS = (
    "(()=>{const q='button,[role=button],[data-a],input,select,summary';"
    "const seen=new Set();document.querySelectorAll(q).forEach(e=>{"
    "const r=e.getBoundingClientRect(); if(r.width<=0||r.height<=0)return;"
    "const t=(e.getAttribute('aria-label')||e.placeholder||e.textContent||'').trim();"
    "if(t)seen.add(t.slice(0,80));});return JSON.stringify([...seen])})()"
)

def mock_controls(pane: str) -> set[str]:
    url = f"file://{MOCK}?pane={pane}&only=mac"
    r = subprocess.run(["obscura", "fetch", url, "--eval", MOCK_CONTROLS_JS],
                       capture_output=True, text=True, timeout=120)
    line = next((l for l in reversed(r.stdout.splitlines()) if l.strip().startswith("[")), "")
    try:
        labels = json.loads(line)
    except Exception:
        return set()
    out = {normalise(x) for x in labels}
    return {x for x in out if is_control_label(x)}

def main() -> int:
    shell_build, shell_mock = None, None
    rows = []
    for sid, pane in BOARDS:
        b, m = ax_controls(sid), mock_controls(pane)
        if not b:
            print(f"{sid}: no accessibility dump on disk — inconclusive, not clean")
            continue
        shell_build = b if shell_build is None else (shell_build & b)
        shell_mock = m if shell_mock is None else (shell_mock & m)
        rows.append((sid, pane, b, m))

    if not rows:
        print("examined=0 — the differential did not run")
        return 2

    total_missing = total_drift = 0
    print(f"shell subtraction: {len(shell_build)} term(s) common to every build board, "
          f"{len(shell_mock)} common to every mock board — removed from each comparison\n")
    findings = {}
    for sid, pane, b, m in rows:
        bb, mm = b - shell_build, m - shell_mock
        missing = {t for t in mm - bb if t not in ACCEPTED}
        drift = {t for t in bb - mm if t not in ACCEPTED}
        total_missing += len(missing); total_drift += len(drift)
        findings[sid] = {"pane": pane, "buildControls": len(bb), "designControls": len(mm),
                         "inDesignNotBuild": sorted(missing), "inBuildNotDesign": sorted(drift)}
        print(f"{sid} ({pane}): examined build={len(bb)} design={len(mm)} "
              f"· in design not build={len(missing)} · in build not design={len(drift)}")
        if missing:
            print(f"    control(s) the design specifies and the build never drew: "
                  f"{'; '.join(sorted(missing)[:10])}" + (" …" if len(missing) > 10 else ""))
        if drift:
            print(f"    control(s) the build draws and the design never specified: "
                  f"{'; '.join(sorted(drift)[:10])}" + (" …" if len(drift) > 10 else ""))
    print(f"\nexamined={len(rows)} boards · in-design-not-build={total_missing} "
          f"· in-build-not-design={total_drift} · accepted={len(ACCEPTED)}")
    out = CAMPAIGN / "evidence/vocab-differential.json"
    out.write_text(json.dumps({"accepted": ACCEPTED, "boards": findings}, indent=2) + "\n")
    print(f"wrote {out.relative_to(ROOT)}")
    return 0

if __name__ == "__main__":
    sys.exit(main())
