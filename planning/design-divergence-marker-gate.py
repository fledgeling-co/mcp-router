#!/usr/bin/env python3
"""Refuse a design-of-record surface that draws a superseded feature without saying so (DEF-042).

## The defect

`design/mocks/prototype.html` draws a model-graded evaluation: graded pills, run counts, a "last
run" column and an install-velocity figure. Neither shipping app has any of it, and the build is
the correct half - ORCHESTRATOR.md's rule is that no number is displayed that the router does not
observe, and the router observes none of these. So the divergence is a defect IN THE DESIGN.

DEF-042 sat at `open - owner-decision` because the fix had two shapes: re-cut the mock, or annotate
it as superseded. It was settled on 2026-09-02 the second way. Re-cutting would delete the record
of what was designed, and the eval board is explicitly not withdrawn as an idea - it is a feature
programme waiting on a definition of what a "case" is for a skill. Marking keeps the drawing and
the truth about it, at the point where a reader of the design meets it.

## Why an annotation needs a gate and a re-cut would not

A deletion stays deleted. An annotation is a claim about a file that other people edit, and it
fails in two directions, both silent:

  * somebody adds another graded drawing - a new board, a new sheet, a new phone surface - and it
    carries no marker. The design has quietly grown a fresh divergence.
  * somebody removes a graded drawing and leaves the marker behind. A reader is now told a surface
    diverges when it does not, which is the same class of wrong answer pointing the other way.

So this gate is two-way: a construct that draws the vocabulary must carry the marker, AND a
construct that carries the marker must draw the vocabulary. A marker that cannot go stale is one
nobody will notice has.

## What counts as a site, and the thing that made a naive census wrong

The census is over `class="ev` in the rendering source. That alone OVER-COUNTS: `PHONE.detail`
uses the same pill class for a kind label and an install count, neither of which is a graded
figure. So a site is counted only when its line also carries the graded vocabulary - an `eval`
word, or a binding of the `ev` field. The distinction was measured rather than assumed: of the
fourteen `class="ev` occurrences in the file, two are plain chips.

DEF-042 itself named four boards, from an eight-pair framing comparison. The census finds NINE
constructs. The Mac Inbox board and two sheets draw it, and so do four phone surfaces - and
nothing under `app/MCPRouterIOS` or `app/Sources/MCPRouterUI/Phone` carries the vocabulary either,
so the phone diverges the same way the Mac does. The defect was narrower than the drawing, which
is exactly what a census finds and a comparison of eight pairs does not.

## The marker must not become a control

`bin/design-controls.py` and `bin/vocab-differential.py` read the design for actuable elements to
build each surface's denominator. A marker drawn as a button would add one in-design control to
nine surfaces and every one of them would then read as a build-side omission. So this gate asserts
the marker's own markup carries no button, `[role=button]`, input, select or summary. The same
reasoning is why the marker names no removed control: the differential greps this file for control
names, and prose explaining a removed control puts it straight back into the in-design set. That
lesson is the Checks pane's, recorded in its own comment in the mock, and it is inherited here
rather than rediscovered.

## Control, run on every invocation

Two synthetic constructs are graded before the real file is read: one that draws the vocabulary
and carries no marker MUST be reported, and one that draws it and carries the marker MUST be
silent. If either arm misbehaves the gate exits 2 and prints no census, because a count from an
instrument that cannot see the defect is not evidence.

Exit codes: 0 every drawing is marked and every marker draws - 1 one of the two directions fails -
2 the control failed or the design could not be read.
"""
from __future__ import annotations

import io
import os
import re
import sys

for _stream in (sys.stdout, sys.stderr):
    if hasattr(_stream, "reconfigure"):
        _stream.reconfigure(encoding="utf-8")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DESIGN = os.path.join(ROOT, "design", "mocks", "prototype.html")

MARKER = 'data-sup="DEF-042"'
MARKER_USE = "${SUP}"

# A pill site. The class alone is not enough - see the header.
PILL = re.compile(r'class="ev[ "]')
# The graded vocabulary, on the same line as the pill.
GRADED = re.compile(r"\bevals?\b|\bevaluated\b|\.ev\b|\bev===")

# A top-level construct in the mock's one script block.
TOP = re.compile(r"^(?:(PANES|PHONE|SHEETS)\.(\w+)\s*=|function\s+(\w+)\s*\(|const\s+([A-Za-z_$][\w$]*)\s*=)")

# What the marker must not be, or it lands in a surface's control denominator.
ACTUABLE = re.compile(r"<button|role=[\"']button|<input|<select|<summary", re.I)


def strip_block_comments(text):
    """Comments explain the divergence and must not be counted as drawing it.

    Without this the header comment written beside the marker - which uses the words this gate
    greps for - would register as a drawing site in whatever construct preceded it, and the gate
    would demand a marker for a paragraph.
    """
    return re.sub(r"/\*.*?\*/", lambda m: "\n" * m.group(0).count("\n"), text, flags=re.S)


def census(text):
    """(constructs that draw, constructs that mark, plain-chip count) over one source text."""
    draws, marks, plain = {}, {}, 0
    current = "(file top)"
    for number, line in enumerate(strip_block_comments(text).splitlines(), 1):
        hit = TOP.match(line)
        if hit:
            current = (hit.group(1) + "." + hit.group(2)) if hit.group(1) else (hit.group(3) or hit.group(4))
        if PILL.search(line):
            if GRADED.search(line):
                draws.setdefault(current, []).append(number)
            else:
                plain += 1
        # Only the USE counts, never the definition. The definition line carries the literal
        # marker attribute and would otherwise attribute a mark to the construct that declares
        # it - which is exactly the false STALE finding this gate's first run produced, on
        # `const SUP=` itself. Counting the use also enforces one shared marker: an inline copy
        # pasted into a board would not register, and the board would read as unmarked.
        if MARKER_USE in line:
            marks.setdefault(current, []).append(number)
    return draws, marks, plain


CONTROL_BAD = """PANES.planted=()=>{
  return `<div class="hd"><h3>Planted</h3></div>
    <span class="ev none">not evaluated</span>`;
};
"""
CONTROL_GOOD = """PANES.planted=()=>{
  return `<div class="hd"><h3>Planted</h3></div>
    ${SUP}
    <span class="ev none">not evaluated</span>`;
};
"""


def control():
    bad_draws, bad_marks, _ = census(CONTROL_BAD)
    if "PANES.planted" not in bad_draws:
        return "the census did not see a planted graded drawing"
    if "PANES.planted" in bad_marks:
        return "the census reported a marker on a construct that carries none"
    good_draws, good_marks, _ = census(CONTROL_GOOD)
    if "PANES.planted" not in good_draws or "PANES.planted" not in good_marks:
        return "the census did not see a planted drawing and its marker together"
    _, _, plain = census('  <span class="ev">${r.inst.toLocaleString()} installs</span>')
    if plain != 1:
        return "a plain pill with no graded vocabulary was not separated from a graded one"
    return None


def main():
    bad = control()
    if bad:
        print("control FAILED: %s" % bad)
        print("no census printed - an instrument that cannot see the defect is not evidence")
        return 2
    print("control HELD (a planted unmarked drawing is reported, a marked one is silent, and a "
          "plain pill is not a graded one)")

    if not os.path.exists(DESIGN):
        print("NOT A PASS - no design of record at %s, so nothing was censused"
              % os.path.relpath(DESIGN, ROOT).replace("\\", "/"))
        return 2

    text = io.open(DESIGN, encoding="utf-8").read()

    declared = text.count(MARKER)
    if declared != 1:
        print("NOT A PASS - the marker attribute %s occurs %d time(s) in the design, and this "
              "gate requires exactly one DEFINITION that every surface reuses." % (MARKER, declared))
        print("            Zero means the annotation was removed or its spelling moved. More than")
        print("            one means a copy was pasted inline, and a marker with two spellings is")
        print("            a marker that can be changed in one place and stay wrong in the other.")
        print("            Either way nothing below was censused.")
        return 2

    definition = text[text.index(MARKER) - 400: text.index(MARKER) + 600]
    if ACTUABLE.search(definition):
        print("FAIL - the marker's own markup carries an actuable element. `bin/design-controls.py`")
        print("       would read it as an in-design control on every surface that carries it, and")
        print("       each of those surfaces would then read as a build-side omission.")
        return 1
    print("marker is not actuable: no button, [role=button], input, select or summary in its markup")

    draws, marks, plain = census(text)
    print("censused %d graded drawing(s) across %d construct(s); %d plain pill(s) using the same "
          "class were not counted" % (sum(len(v) for v in draws.values()), len(draws), plain))

    unmarked = sorted(set(draws) - set(marks))
    stale = sorted(set(marks) - set(draws))

    for name in sorted(draws):
        if name in marks:
            print("  marked    %-16s %d drawing(s) at line(s) %s"
                  % (name, len(draws[name]), ", ".join(str(n) for n in draws[name])))

    if unmarked:
        print()
        print("UNMARKED - draws the graded vocabulary and says nothing about it:")
        for name in unmarked:
            print("  %-16s line(s) %s" % (name, ", ".join(str(n) for n in draws[name])))
        print()
        print("A reader meeting this drawing is told the product has a feature it does not have.")
        print("Add the marker beside it, or re-cut the drawing out. DEF-042 carries the reasoning.")

    if stale:
        print()
        print("STALE - carries the marker and draws nothing it could be about:")
        for name in stale:
            print("  %-16s marker at line(s) %s" % (name, ", ".join(str(n) for n in marks[name])))
        print()
        print("A marker on a surface that no longer diverges is the same wrong answer pointing the")
        print("other way. Remove it in the change that removed the drawing.")

    if unmarked or stale:
        print()
        print("exit: 1")
        return 1

    print()
    print("every construct that draws the graded vocabulary carries the marker, and every marker "
          "has a drawing to be about")
    print()
    print("WHAT THIS GREEN DOES NOT COVER")
    print("  * It reads the SOURCE, not a render. A drawing reachable only in a state this file")
    print("    builds conditionally is counted here and would not be counted by a boot-render")
    print("    harvest - which is the right direction, but it means the marker's PLACEMENT within")
    print("    a construct is not checked. A marker at the foot of a long board is a marker a")
    print("    reader may not meet.")
    print("  * It says nothing about the marker's WORDS. A marker that named a removed control")
    print("    would put that control back into `vocab-differential.py`'s in-design set, and only")
    print("    a reader can see that.")
    print("  * It is scoped to the graded-evaluation vocabulary of DEF-042. Any other feature the")
    print("    design draws and the product refuses is invisible here.")
    print("exit: 0")
    return 0


if __name__ == "__main__":
    sys.exit(main())
