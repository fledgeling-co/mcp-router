#!/usr/bin/env python3
"""DEF-043 / M27 — the sidebar foot's two elements, read out of the Mac shell's own source.

## What this is, and the rung it stands on

DEF-043 recorded that the design paints a loopback readout at the foot of the shared sidebar on
every board and the build painted it on none, and that the readout card above it had lost the
label `Child processes` — `0 of 9` accessibility dumps carried the string. M27 asked for both to
be settled independently, and both were: `app/Sources/MCPRouterUI/Shell/SidebarFoot.swift` draws
the line and `Readout.swift` draws the label.

THIS ARM IS `source-analysis` AND NOTHING STRONGER, and the distinction is the whole reason it is
worth writing down. It reads Swift source. It does not run the Mac app, it does not photograph a
board, and it cannot: the shell is a SwiftPM target with no Windows build and `swift` is not on
this machine. A green here means *the code that draws these two elements is present and composed
the way the design requires*. It does not mean either element reached a screen. M27 asked for
on-glass coverage as well, and that is still owed — on a Mac, through the campaign's own capture
lane, and it is recorded as owed rather than implied by this green.

## Why the honesty arm is the one that can actually fail

Three of the four checks below assert that something is present, and a presence check on a file in
the tree is a weak instrument: it passes the day somebody stops reading the value it names. The
fourth is the one with teeth, and it is the defect DEF-043's own brief warned about in the other
direction:

    The prototype DREW the literal `127.0.0.1:8879` while the fixture router answered on 8971.

A restored readout that hard-codes a port is the honesty rule broken outward — a user who moved
the port is told to reach for the wrong one. So this arm sweeps both shell source trees for a
literal host:port and requires both the foot line and the Settings endpoint row to compose through
`LoopbackAddress`, which is what stops the two drifting apart.

THE SWEEP'S SCOPE WAS WRONG ON ITS FIRST RUN, and the correction is recorded here rather than
quietly applied. It refused a literal anywhere in either tree and reported
`ShellClientFactory.shippingEndpoint` — which is not a displayed value at all but the URL a shipped
build DIALS, consumed only by `Choice.live`, the two client constructors and the Release guard, and
reaching no view. That was checked by reading every reference to the symbol, not assumed. The
honesty rule governs what a user is told, not what the app connects to, and a client with no
default endpoint would not be more honest — it would not start. So the verdict is now split rather
than the sweep narrowed: a literal in a file that DISPLAYS an address fails, and a literal outside
those files fails too unless its symbol is declared in `ALLOWED_OUTSIDE_DISPLAY` with why it is not
a readout. A new dial literal therefore still has to be adjudicated instead of passing for not
being in a view.

## Which product this is about, since the row never said

macOS. `planning/features-to-triage/M27-sidebar-foot-readout.md` reads `Category: mac`; the
evidence is nine accessibility dumps at 1156x680 and line numbers in the Mac design of record; and
`DESIGN.md`'s sidebar-foot specification sits in §2, the Mac half. The Windows floor (§11-13)
specifies no sidebar foot, its own `What the Windows floor still owes` list does not name one, and
`app/windows/MCPRouter.Shell/Shell/ShellWindow.xaml` declares a `NavigationView` with no pane
footer content at all. So the absence is not a Windows defect — Windows was never promised it.
That is a statement about the Windows build, not an assertion this file makes: a gate saying
"Windows must not grow a sidebar foot" would redden on somebody adding a good thing.

    exit 0   every check ran and passed
    exit 1   a check ran and FAILED
    exit 2   NO VERDICT — a source file this arm reads is missing, so nothing was measured
"""
from __future__ import annotations

import io
import os
import re
import sys

for _stream in (sys.stdout, sys.stderr):
    if hasattr(_stream, "reconfigure"):
        _stream.reconfigure(encoding="utf-8")

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))

FOOT = "app/Sources/MCPRouterUI/Shell/SidebarFoot.swift"
READOUT = "app/Sources/MCPRouterUI/Shell/Readout.swift"
LOOPBACK = "app/Sources/MCPRouterKit/Shell/LoopbackReadout.swift"
SETTINGS = "app/Sources/MCPRouterKit/Shell/SettingsPresentation.swift"

# A literal host:port in shell source. This is the arm with teeth; see the header.
LITERAL = re.compile(r"127\.0\.0\.1\s*:\s*\d+|\"127\.0\.0\.1:")
SEARCHED = ("app/Sources/MCPRouterUI/Shell", "app/Sources/MCPRouterKit/Shell")

# The files that DISPLAY a loopback address. A literal in one of these is the honesty rule broken
# outward, which is what DEF-043's brief warned about; a literal anywhere else is a different
# question, answered below.
DISPLAY_FILES = (FOOT, READOUT, LOOPBACK, SETTINGS)

# Literals outside the display path, each declared with why it is not a readout.
#
# THIS LIST EARNED ITS EXISTENCE ON THIS ARM'S FIRST RUN, and the run is worth recording because
# the arm was wrong rather than the code. It swept both shell trees for any literal host:port and
# reported `ShellClientFactory.shippingEndpoint`. That is not a displayed value: it is the URL a
# shipped build DIALS, consumed only by `Choice.live`, the two client constructors and the Release
# guard, and it reaches no `Text`. Checked by reading every reference to the symbol before the
# scope was narrowed. The honesty rule governs what a user is TOLD, not what the app connects to,
# and a client with no default endpoint would not be more honest, it would not start.
#
# So the sweep stays wide and the verdict is split. A literal in a display file fails. A literal
# outside one fails too, unless its symbol is declared here — which keeps a NEW dial literal from
# passing silently just because it is not in a view.
ALLOWED_OUTSIDE_DISPLAY = {
    ("app/Sources/MCPRouterUI/Shell/ShellClientFactory.swift", "shippingEndpoint"):
        "the endpoint a shipped build dials, and the fallback for a Debug build pointed at a host "
        "this factory will not honour. Consumed by Choice.live, LiveControlAPIClient, "
        "ControlEventStream and the Release guard; it reaches no view, so nothing displays it.",
}


def read(rel):
    path = os.path.join(ROOT, rel)
    if not os.path.exists(path):
        return None
    return io.open(path, encoding="utf-8").read()


class Findings:
    def __init__(self):
        self.passed, self.failed = [], []

    def ok(self, check, detail):
        self.passed.append((check, detail))

    def bad(self, check, detail):
        self.failed.append((check, detail))


def literal_hits():
    """Every literal host:port under the two shell trees, with its line, comments included.

    Comments are NOT stripped, deliberately. The one in `SidebarFoot.swift` that quotes the mock's
    old literal is prose about the defect, so this arm would fire on it — which is why it is
    allowed by an explicit exception below rather than by a blanket comment strip. A blanket strip
    would also hide a literal somebody parked in a `//` line and later uncommented.
    """
    hits = []
    for rel_dir in SEARCHED:
        base = os.path.join(ROOT, rel_dir)
        if not os.path.isdir(base):
            continue
        for dirpath, _dirs, files in os.walk(base):
            for name in sorted(files):
                if not name.endswith(".swift"):
                    continue
                path = os.path.join(dirpath, name)
                rel = os.path.relpath(path, ROOT).replace("\\", "/")
                for number, line in enumerate(io.open(path, encoding="utf-8").read().splitlines(), 1):
                    if LITERAL.search(line):
                        stripped = line.strip()
                        prose = stripped.startswith("//") or stripped.startswith("///") or stripped.startswith("*")
                        hits.append((rel, number, stripped[:110], prose))
    return hits


def main():
    findings = Findings()

    sources = {}
    for rel in (FOOT, READOUT, LOOPBACK, SETTINGS):
        text = read(rel)
        if text is None:
            print("NO VERDICT: %s is absent, so this arm measured nothing. That is not a pass and "
                  "not a failure of the shell." % rel)
            return 2
        sources[rel] = text

    # 1. The foot line exists and renders the address it was given.
    if "struct SidebarFoot" in sources[FOOT] and re.search(
            r"case let \.address\(address\):", sources[FOOT]) and "Text(address)" in sources[FOOT]:
        findings.ok("foot.drawn",
                    "SidebarFoot renders Text(address) on its `.address` case")
    else:
        findings.bad("foot.drawn",
                     "%s no longer declares a SidebarFoot that renders the address it is given; "
                     "DEF-043's first half is back" % FOOT)

    # 2. The address is composed, not spelled, and by the SAME composer the Settings row uses.
    composed = "LoopbackAddress.hostPort(" in sources[LOOPBACK]
    shared = "LoopbackAddress.controlEndpoint(" in sources[SETTINGS]
    if composed and shared:
        findings.ok("foot.composed",
                    "the foot reading comes from LoopbackAddress.hostPort and the Settings "
                    "endpoint row from LoopbackAddress.controlEndpoint, so the two cannot drift")
    else:
        findings.bad(
            "foot.composed",
            "the foot %s and the Settings endpoint row %s compose through LoopbackAddress. The "
            "design requires both to read the observed port from one place; two spellings is two "
            "answers to where the app is pointed"
            % ("does" if composed else "does NOT", "does" if shared else "does NOT"))

    # 3. THE HONESTY ARM. A literal host:port in a file that DISPLAYS one is the rule broken
    #    outward; one outside the display path must still be declared, or a new dial literal
    #    would pass simply for not being in a view.
    hits = literal_hits()
    live = [h for h in hits if not h[3]]
    prose = [h for h in hits if h[3]]

    displayed = [h for h in live if h[0] in DISPLAY_FILES]
    outside = [h for h in live if h[0] not in DISPLAY_FILES]
    undeclared = [h for h in outside
                  if not any(k[0] == h[0] and k[1] in h[2] for k in ALLOWED_OUTSIDE_DISPLAY)]

    if displayed:
        findings.bad(
            "foot.noLiteralPort",
            "%d literal host:port(s) in a file that DISPLAYS an address: %s. The prototype drew "
            "`127.0.0.1:8879` while the fixture router answered on 8971, and a user who moved the "
            "port would be told to reach for the wrong one"
            % (len(displayed), "; ".join("%s:%d %s" % (r, n, t) for r, n, t, _ in displayed)))
    elif undeclared:
        findings.bad(
            "foot.noLiteralPort",
            "%d literal host:port(s) outside the display path and outside the declared set: %s. "
            "Not automatically a defect — a dialled endpoint is not a displayed one — but it has "
            "to be adjudicated and declared rather than passing for not being in a view"
            % (len(undeclared), "; ".join("%s:%d %s" % (r, n, t) for r, n, t, _ in undeclared)))
    else:
        findings.ok(
            "foot.noLiteralPort",
            "no literal host:port in any of the %d display file(s); %d outside them, each declared "
            "as a dialled rather than a displayed value; %d in prose, which is the record of what "
            "the mock used to draw"
            % (len(DISPLAY_FILES), len(outside), len(prose)))

    # 4. The readout card's label, the half DEF-043 measured at 0 of 9 dumps.
    if 'childProcessesLabel = "Child processes"' in sources[READOUT] \
            and "Text(ReadoutCopy.childProcessesLabel)" in sources[READOUT]:
        findings.ok("readout.label",
                    "ReadoutCopy.childProcessesLabel is \"Child processes\" and Readout draws it")
    else:
        findings.bad(
            "readout.label",
            "%s no longer both declares the label \"Child processes\" and draws it. DEF-043 "
            "measured that string in 0 of 9 accessibility dumps; this is the check that would "
            "notice it going again" % READOUT)

    print("DEF-043 / M27 — the Mac sidebar foot, read from source")
    print("  oracle:  source-analysis. Nothing here was rendered, photographed or run.")
    print("  product: macOS. The Windows shell was never promised this; see the header.")
    print()
    print("  passed  %d" % len(findings.passed))
    print("  FAILED  %d" % len(findings.failed))
    for check, detail in findings.passed:
        print("    ok    %-22s %s" % (check, detail))
    for check, detail in findings.failed:
        print("    FAIL  %-22s %s" % (check, detail))
    print()
    print("  STILL OWED, and not bought by this green: on-glass coverage of both elements, on a")
    print("  Mac, through the campaign's own capture lane. M27 asked for it. A source read cannot")
    print("  tell a drawn element from a declared one.")

    return 1 if findings.failed else 0


if __name__ == "__main__":
    sys.exit(main())
