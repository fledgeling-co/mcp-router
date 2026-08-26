#!/usr/bin/env python3
"""Derive the affordance inventory of one mock surface state, mechanically.

The breadth ledger has to be reconciled against something the auditor did not write, or it
reproduces P4 exactly: a hand-written census whose rows can be deleted, which leaves the numerator
alone, shrinks the denominator, raises the reported coverage and exits 0. `planning/evidence/
P4-acceptance.md` records four separate row deletions doing precisely that.

So the inventory is *derived from the mock* every run. A row cannot be deleted from it, only from
the mock — which is a visible change to the design of record rather than to a spreadsheet.

What counts as an affordance is a declared list, not a judgement call made per element: the M23
brief names "every header element, button, card, section, badge, chip, search field, meaningful
icon, list row and call to action". Each rule below maps to one of those words.

**Every element in the frame lands in exactly one class, and "matched no rule" is one of them.**
That is M32's subject and it is a repair rather than a restatement. This file used to say the
exclusion was "reported as a count, so it is visible rather than silent", and the count it reported
was `unclassifiedElements` — which skipped `span`, `div`, `svg`, `b`, `i`, `dt`, `dd`, `dl`,
`aside`, `use`, `br` and `small` before counting, and which nothing in `mock_fidelity.py` ever read.
Measured on this tree at 03c34c3: the Insights board's `v-ideal` frame drew four `<div class="stat">`
cells carrying twelve strings — `Resident, all children`, `214 MB`, `measured, not modelled` and
nine more — and reported `unclassifiedElements: 1`. So M20's finding is exact: a wrong
`Resident 214 MB` could never enter the census as `present`, `divergent` OR `absent`, and the field
that was supposed to make that visible said 1 while nothing read even that.

The four classes partition the frame, and the partition is asserted here rather than assumed:

  affordance     matched a rule; it is an inventory row.
  covered        matched no rule, but sits inside an element that did — its text is carried into
                 that affordance's label, so it was inventoried through its ancestor. A `.c` cell
                 inside a `.trow` is this: the row's label IS its subtree's text.
  uninventoried  matched no rule, has no affordance ancestor, and draws a string of its own.
                 **Nothing inventories this text.** It is what a derivation rule set that silently
                 declines to derive looks like from the outside, and `mock_fidelity.py`'s `census`
                 layer reports every one of them.
  container      matched no rule, no affordance ancestor, and draws nothing of its own.

`covered` and `container` are the two honest silences and they are counted, not dropped. A change
to `RULES` moves elements between the classes and the totals still sum, which is what stops a rule
being narrowed to shrink the reported residue.

Usage:  mock-affordances.py <mock.html> <section-id> <frame>
Writes the inventory as JSON on stdout.

`frame` names the element inside the section that holds one drawn state. A bare word is a CLASS,
which is what every board and the Settings window use (`v-ideal`, `v-empty`); a leading `#` is an
ID. The id form exists because a SHEET has no `.v-*` frame at all — `#sh-readme` carries its whole
state in one element — and without it the census exits 3 at "has no `.v-ideal` block" and the
surface cannot be measured. The affordance ids it emits are prefixed with the selector minus its
`#`, so an existing pairing file keyed on `v-ideal/...` is unchanged.
"""
from __future__ import annotations

import json
import re
import sys
import unicodedata
from html.parser import HTMLParser

# kind -> (predicate on (tag, classes, attrs), label source)
# Order matters: the first rule that matches owns the element.
RULES = [
    ("heading", lambda tag, cls, attrs: tag in ("h1", "h2", "h3")),
    # "list row" is the brief's own word; `.trow` is the boards' spelling and `<li>` a document's.
    ("row", lambda tag, cls, attrs: "trow" in cls or tag == "li"),
    ("jack", lambda tag, cls, attrs: "jack" in cls),
    ("button", lambda tag, cls, attrs: tag == "button"),
    ("search-field", lambda tag, cls, attrs: tag == "input" and attrs.get("type") in ("search", "text")),
    ("section-header", lambda tag, cls, attrs: "section-h" in cls),
    # A column header is a `.c` cell inside the `.thead` row. It needs the ancestor because the
    # same `.c` class is what every body cell uses; matching on the class alone would inventory
    # every cell of every row as a column header.
    ("column-header",
     lambda tag, cls, attrs: tag == "th"
     or ("c" in cls and "thead" in attrs.get("_ancestors", ()))),
    ("banner", lambda tag, cls, attrs: "band" in cls),
    # `badge` is one of the brief's own words and had no rule until a surface drew one. The mock
    # spells the two-part shields `<span class="shield">`.
    ("badge", lambda tag, cls, attrs: "shield" in cls),
    ("card", lambda tag, cls, attrs: "card" in cls or "tablecard" in cls or "signalpath" in cls),
    ("field", lambda tag, cls, attrs: "kv" in cls),
    # Three kinds that already existed and only knew one spelling each. A Markdown document writes
    # them as elements rather than as classes, so the same affordance was invisible to the census
    # depending on which surface drew it — `.callout` counted and `<blockquote>` did not.
    ("callout", lambda tag, cls, attrs: "callout" in cls or tag == "blockquote"),
    ("codeblock", lambda tag, cls, attrs: "codeblock" in cls or tag == "pre"),
    ("progress", lambda tag, cls, attrs: "progress" in cls),
    ("skeleton-row", lambda tag, cls, attrs: "skel-row" in cls),
    ("indicator", lambda tag, cls, attrs: "dot" in cls),
    ("icon", lambda tag, cls, attrs: tag == "use" and attrs.get("href", "").startswith("#i-")),
    ("sentence", lambda tag, cls, attrs: tag == "p"),
]


def slug(text: str) -> str:
    s = re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")
    return s[:48] or "unlabelled"


# Every void element in HTML5. `wbr`, `track` and `base` were missing, and a void tag this set
# does not know is pushed onto the open-element stack and never popped — so every later sibling
# inherits an affordance ancestor from it and lands `covered` instead of `uninventoried`
# (`gemini-3.7-flash-high`, finding 3.3; its `<input>` example is already covered, the class is not).
VOID = {"br", "img", "input", "hr", "meta", "link", "source", "area", "col", "embed", "param",
        "wbr", "track", "base"}

# Elements whose text is code or metadata rather than something drawn on the screen. Without this
# a `<style>` block is an element with no rule, no affordance ancestor and a great deal of visible
# text, so it lands in the residue and asks somebody to waive a stylesheet (finding 3.5).
NON_DRAWING = {"script", "style", "template", "noscript", "title"}


class Slicer(HTMLParser):
    """Finds the byte range of the element whose start tag satisfies `match`.

    Written rather than regexed because the mock nests the same tag several levels deep and a
    non-greedy regex closes on the first inner `</div>`, which silently truncates the inventory —
    the first version of this script did exactly that and reported 30 affordances for a state with
    more than a hundred.
    """

    def __init__(self, match):
        super().__init__(convert_charrefs=True)
        self.match = match
        self.depth = 0
        self.start_depth = None
        self.start_offset = None
        self.end_offset = None

    def handle_startendtag(self, tag, attrs):
        pass  # self-closing: opens and closes, so it changes no depth

    def handle_starttag(self, tag, attrs):
        if tag in VOID:
            return
        if self.start_depth is None and self.match(tag, dict(attrs)):
            self.start_depth = self.depth
            line, col = self.getpos()
            self.start_offset = (line, col)
        self.depth += 1

    def handle_endtag(self, tag):
        if tag in VOID:
            return
        self.depth -= 1
        if self.start_depth is not None and self.end_offset is None and self.depth == self.start_depth:
            self.end_offset = self.getpos()


def slice_element(html: str, match) -> str | None:
    found = slice_element_at(html, match)
    return None if found is None else found[0]


def slice_element_at(html: str, match) -> tuple[str, int] | None:
    """The fragment, and the 1-based line its first byte sits on inside `html`.

    The line travels with the fragment so an element the census cannot derive can be reported at a
    place a reader opens, rather than at an offset into a slice that exists only inside this
    process. `design/mcp-router-console.html:3410` `<div class="sl">Resident, all children</div>`
    at 03c34c3 is the line M20's finding names, and it is where the census now points.
    """
    slicer = Slicer(match)
    slicer.feed(html)
    if slicer.start_offset is None or slicer.end_offset is None:
        return None
    lines = html.split("\n")

    def index_of(pos):
        line, col = pos
        return sum(len(l) + 1 for l in lines[: line - 1]) + col

    return html[index_of(slicer.start_offset): index_of(slicer.end_offset)], slicer.start_offset[0]


class SurfaceParser(HTMLParser):
    """Records every element inside an already-sliced fragment, and classifies all of them.

    Two structures, because they answer two different questions and conflating them is what made
    the residue invisible. `found` is the inventory — the elements a rule matched. `elements` is
    every element the frame contains, each carrying the class it landed in, so the four counts sum
    to the number of elements rather than to the number somebody remembered to count.

    `open_elements` is the full open-element stack; `stack` is the subset of it that are
    affordances. The label-building loop reads `stack` exactly as it always has, so an affordance's
    label is unchanged — what is new is that the text is ALSO recorded against the one element that
    literally contains it, which is what distinguishes a string carried into an affordance's label
    from a string nothing inventories.
    """

    def __init__(self, line_offset: int = 0):
        super().__init__(convert_charrefs=True)
        self.depth = 0
        self.stack: list[dict] = []
        self.found: list[dict] = []
        self.elements: list[dict] = []
        self.open_elements: list[dict] = []
        self.ancestors: list[tuple[int, list[str]]] = []
        #: Line of the fragment's first byte inside the whole mock, so a reported element can be
        #: opened at `design/<mock>.html:<line>` rather than at an offset into a slice nobody has.
        self.line_offset = line_offset
        #: Visible text parsed while no element was open. It belongs to no element, so it belongs
        #: to no class, and a partition with text outside it is not a partition (finding 3.4).
        self.orphan_text = 0
        #: How deep inside a `<script>`/`<style>` we are. Their content is code, not drawn copy.
        self.non_drawing = 0

    def handle_startendtag(self, tag, attrs):
        self._open(tag, dict(attrs), void=True)

    def handle_starttag(self, tag, attrs):
        self._open(tag, dict(attrs), void=tag in VOID)

    def _open(self, tag, a, void):
        cls = (a.get("class") or "").split()
        inherited = {c for _, classes in self.ancestors for c in classes}
        a = dict(a, _ancestors=tuple(sorted(inherited)))
        kind = next((k for k, pred in RULES if pred(tag, cls, a)), None)

        # Recorded for EVERY element, matched or not. `hasAffordanceAncestor` is read off the open
        # stack rather than recomputed later, because "is this element's text carried into some
        # affordance's label" is a question about who was open when it was parsed.
        element = {
            "kind": kind,
            "tag": tag,
            "classes": cls,
            "line": self.line_offset + self.getpos()[0] - 1,
            "ownText": "",
            "hasAffordanceAncestor": any(e["kind"] for e in self.open_elements),
            "depth": self.depth,
        }
        self.elements.append(element)

        if kind:
            record = {
                "kind": kind,
                "tag": tag,
                "classes": cls,
                "attrs": {
                    k: v for k, v in a.items()
                    if k in ("href", "data-act", "data-server", "aria-label", "role", "aria-disabled")
                },
                "text": "",
                "depth": self.depth,
            }
            self.found.append(record)
            if not void:
                self.stack.append(record)
        if not void:
            if tag in NON_DRAWING:
                self.non_drawing += 1
            self.open_elements.append(element)
            self.ancestors.append((self.depth, cls))
            self.depth += 1

    def handle_endtag(self, tag):
        if tag in VOID:
            return
        if tag in NON_DRAWING and self.non_drawing:
            self.non_drawing -= 1
        self.depth -= 1
        while self.ancestors and self.ancestors[-1][0] >= self.depth:
            self.ancestors.pop()
        while self.stack and self.stack[-1]["depth"] >= self.depth:
            self.stack.pop()
        while self.open_elements and self.open_elements[-1]["depth"] >= self.depth:
            self.open_elements.pop()

    def handle_data(self, data):
        text = " ".join(data.split())
        if not text:
            return
        if self.non_drawing:
            return  # the body of a <script> or <style> is not copy anybody reads off the screen
        # The innermost open element is the one that literally draws this string. Every affordance
        # still open takes it into its label, which is the pre-existing behaviour and unchanged.
        if self.open_elements:
            owner = self.open_elements[-1]
            owner["ownText"] = (owner["ownText"] + " " + text).strip()
        elif visible(text):
            self.orphan_text += 1
        for record in self.stack:
            record["text"] = (record["text"] + " " + text).strip()

    def classify(self) -> list[dict]:
        """One class per element, assigned here so the four are read off one expression."""
        for element in self.elements:
            if element["kind"]:
                element["class"] = "affordance"
            elif element["hasAffordanceAncestor"]:
                element["class"] = "covered"
            elif visible(element["ownText"]):
                element["class"] = "uninventoried"
            else:
                element["class"] = "container"
        return self.elements


# The same question `mock_fidelity.py`'s `readable` asks, asked of the mock side: is there anything
# here a person could see. Whitespace-only text is not a drawn string, and neither is a run of
# codepoints that put no mark on the screen — so an element carrying one is a container rather than
# an uninventoried affordance, and does not become a finding nobody can act on.
# `Co` — private use — is deliberately ABSENT here and present in `mock_fidelity.py`'s `readable`,
# and the asymmetry is the point rather than a drift. There, filtering a private-use codepoint costs
# a finding, which is the safe direction. Here it costs a PASS: an icon-font glyph is a drawn thing
# with no rule and no affordance ancestor, and filtering it would classify the element `container`
# and drop it out of the residue silently (`gemini-3.7-flash-high`, finding 2.2).
INVISIBLE_CATEGORIES = {"Cc", "Cf", "Cs", "Cn", "Zs", "Zl", "Zp", "Mn", "Me", "Mc"}
BLANK_CODEPOINTS = {"\u115f", "\u1160", "\u3164", "\uffa0", "\u2800"}


def visible(value: str | None) -> str:
    return "".join(
        ch for ch in (value or "")
        if not ch.isspace()
        and ch not in BLANK_CODEPOINTS
        and unicodedata.category(ch) not in INVISIBLE_CATEGORIES
    )


def main() -> int:
    if len(sys.argv) != 4:
        sys.stderr.write(__doc__ + "\n")
        return 2
    path, section_id, frame = sys.argv[1], sys.argv[2], sys.argv[3]
    with open(path, encoding="utf-8") as handle:
        html = handle.read()

    located = slice_element_at(html, lambda tag, a: a.get("id") == section_id)
    if located is None:
        sys.stderr.write(f"error: the mock has no element with id '{section_id}'\n")
        return 3
    section, section_line = located
    if frame == f"#{section_id}":
        # The frame IS the section — a sheet carries its whole state in one element. Taken
        # directly rather than re-sliced, because `slice_element` returns the fragment WITHOUT its
        # own closing tag, so feeding it back in leaves the outer element never closed and the
        # slicer returns None. That reads as "the mock has no such element", which would be false.
        fragment, fragment_line, described = section, section_line, f"element with id '{section_id}'"
    else:
        if frame.startswith("#"):
            frame_id = frame[1:]
            match = lambda tag, a: a.get("id") == frame_id                   # noqa: E731
            described = f"element with id '{frame_id}'"
        else:
            match = lambda tag, a: frame in (a.get("class") or "").split()   # noqa: E731
            described = f"'.{frame}' block"
        located = slice_element_at(section, match)
        if located is None:
            sys.stderr.write(f"error: #{section_id} has no {described}\n")
            return 3
        # The inner slice's line is relative to `section`, whose own first byte is at
        # `section_line`, so the two compose. Off by one without the `- 1`, because both are
        # 1-based and the fragment's first line IS the section's `section_line`-th.
        fragment, inner_line = located
        fragment_line = section_line + inner_line - 1
    if fragment is None:
        sys.stderr.write(f"error: #{section_id} has no {described}\n")
        return 3
    prefix = frame.lstrip("#")

    parser = SurfaceParser(line_offset=fragment_line)
    parser.feed(fragment)
    elements = parser.classify()

    if not parser.found:
        sys.stderr.write(
            f"error: no affordances found in #{section_id} {described}. An empty inventory and a\n"
            f"       surface with nothing on it are the same JSON, so this is a failure rather than\n"
            f"       a clean read.\n"
        )
        return 3

    seen: dict[str, int] = {}
    inventory = []
    for record in parser.found:
        label = record["text"] or record["attrs"].get("aria-label") or record["attrs"].get("data-server") or ""
        base = f"{prefix}/{record['kind']}/{slug(label)}"
        seen[base] = seen.get(base, 0) + 1
        ident = base if seen[base] == 1 else f"{base}#{seen[base]}"
        inventory.append({
            "id": ident,
            "kind": record["kind"],
            "label": label,
            "tag": record["tag"],
            "classes": record["classes"],
            "attrs": record["attrs"],
        })

    # The residue, with an id built the same way an affordance id is so a waiver in the pairing
    # file survives the mock being reformatted. `where` is for a person; `id` is for the gate.
    uninventoried = []
    seen_residue: dict[str, int] = {}
    for element in elements:
        if element["class"] != "uninventoried":
            continue
        base = f"{prefix}/uninventoried/{slug(element['ownText'])}"
        seen_residue[base] = seen_residue.get(base, 0) + 1
        ident = base if seen_residue[base] == 1 else f"{base}#{seen_residue[base]}"
        uninventoried.append({
            "id": ident,
            "where": f"{path}:{element['line']}",
            "tag": element["tag"],
            "classes": element["classes"],
            "text": element["ownText"],
        })

    census = {"elements": len(elements), "affordance": 0, "covered": 0, "container": 0,
              "uninventoried": 0}
    for element in elements:
        census[element["class"]] += 1

    # Two conditions under which `uninventoried` is not a measurement, reported rather than
    # detected downstream by their effect.
    #
    # `rootAffordance` is the sharper one (`gemini-3.7-flash-high`, finding 3.2). The slicer returns
    # a fragment WITHOUT its closing tag, so the frame's own root element stays open for the whole
    # parse — which is right, everything IS inside it. But if that root matches a rule, every
    # element in the frame has an affordance ancestor, every one of them lands `covered`, and the
    # residue is identically zero for a structural reason rather than a measured one. A frame that
    # can only ever report a clean residue is a check that cannot fail, so it says so instead.
    #
    # `orphanText` is text parsed with no element open. It belongs to no element and therefore to
    # no class, and a partition with drawn text outside it is not a partition (finding 3.4).
    census["rootAffordance"] = elements[0]["kind"] if elements and elements[0]["kind"] else None
    census["orphanText"] = parser.orphan_text

    # Asserted where it is produced, not only where it is read. The four classes are assigned by one
    # if/elif chain, so they cannot overlap — what this catches is an element that was parsed into
    # `elements` and never classified, and a future fifth class added to `classify` without being
    # added here. A census that does not partition its own population is the defect this whole file
    # is about, arriving one level in (`mock_fidelity.py` re-derives it independently and refuses
    # too, because a producer vouching for itself is not a measurement).
    parts = census["affordance"] + census["covered"] + census["container"] + census["uninventoried"]
    if parts != census["elements"] or census["affordance"] != len(inventory):
        sys.stderr.write(
            f"error: the census does not partition the frame — {census['elements']} element(s) "
            f"split into {parts} across four classes, and {census['affordance']} of them were "
            f"called affordances against {len(inventory)} inventory row(s). Every element has to "
            f"land in exactly one class or the residue is unsized.\n"
        )
        return 3
    if census["uninventoried"] != len(uninventoried):
        sys.stderr.write(
            f"error: {census['uninventoried']} element(s) were classified uninventoried and "
            f"{len(uninventoried)} were listed, so the count and the list are not the same set.\n"
        )
        return 3

    json.dump({
        "mock": path,
        "section": section_id,
        "state": prefix,
        "count": len(inventory),
        "census": census,
        "uninventoried": uninventoried,
        "affordances": inventory,
    }, sys.stdout, indent=2, sort_keys=True)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
