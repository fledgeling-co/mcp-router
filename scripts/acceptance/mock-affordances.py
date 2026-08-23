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
icon, list row and call to action". Each rule below maps to one of those words, and an element
matching none of them is not inventoried — which the summary reports as a count, so the exclusion
is visible rather than silent.

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


VOID = {"br", "img", "input", "hr", "meta", "link", "source", "area", "col", "embed", "param"}


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
    slicer = Slicer(match)
    slicer.feed(html)
    if slicer.start_offset is None or slicer.end_offset is None:
        return None
    lines = html.split("\n")

    def index_of(pos):
        line, col = pos
        return sum(len(l) + 1 for l in lines[: line - 1]) + col

    return html[index_of(slicer.start_offset): index_of(slicer.end_offset)]


class SurfaceParser(HTMLParser):
    """Records every affordance inside an already-sliced fragment."""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.depth = 0
        self.stack: list[dict] = []
        self.found: list[dict] = []
        self.unclassified = 0
        self.ancestors: list[tuple[int, list[str]]] = []

    def handle_startendtag(self, tag, attrs):
        self._open(tag, dict(attrs), void=True)

    def handle_starttag(self, tag, attrs):
        self._open(tag, dict(attrs), void=tag in VOID)

    def _open(self, tag, a, void):
        cls = (a.get("class") or "").split()
        inherited = {c for _, classes in self.ancestors for c in classes}
        a = dict(a, _ancestors=tuple(sorted(inherited)))
        kind = next((k for k, pred in RULES if pred(tag, cls, a)), None)
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
        elif tag not in ("span", "div", "svg", "b", "i", "dt", "dd", "dl", "aside", "use", "br", "small"):
            self.unclassified += 1
        if not void:
            self.ancestors.append((self.depth, cls))
            self.depth += 1

    def handle_endtag(self, tag):
        if tag in VOID:
            return
        self.depth -= 1
        while self.ancestors and self.ancestors[-1][0] >= self.depth:
            self.ancestors.pop()
        while self.stack and self.stack[-1]["depth"] >= self.depth:
            self.stack.pop()

    def handle_data(self, data):
        text = " ".join(data.split())
        if not text:
            return
        for record in self.stack:
            record["text"] = (record["text"] + " " + text).strip()


def main() -> int:
    if len(sys.argv) != 4:
        sys.stderr.write(__doc__ + "\n")
        return 2
    path, section_id, frame = sys.argv[1], sys.argv[2], sys.argv[3]
    with open(path, encoding="utf-8") as handle:
        html = handle.read()

    section = slice_element(html, lambda tag, a: a.get("id") == section_id)
    if section is None:
        sys.stderr.write(f"error: the mock has no element with id '{section_id}'\n")
        return 3
    if frame == f"#{section_id}":
        # The frame IS the section — a sheet carries its whole state in one element. Taken
        # directly rather than re-sliced, because `slice_element` returns the fragment WITHOUT its
        # own closing tag, so feeding it back in leaves the outer element never closed and the
        # slicer returns None. That reads as "the mock has no such element", which would be false.
        fragment, described = section, f"element with id '{section_id}'"
    else:
        if frame.startswith("#"):
            frame_id = frame[1:]
            match = lambda tag, a: a.get("id") == frame_id                   # noqa: E731
            described = f"element with id '{frame_id}'"
        else:
            match = lambda tag, a: frame in (a.get("class") or "").split()   # noqa: E731
            described = f"'.{frame}' block"
        fragment = slice_element(section, match)
    if fragment is None:
        sys.stderr.write(f"error: #{section_id} has no {described}\n")
        return 3
    prefix = frame.lstrip("#")

    parser = SurfaceParser()
    parser.feed(fragment)

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

    json.dump({
        "mock": path,
        "section": section_id,
        "state": prefix,
        "count": len(inventory),
        "unclassifiedElements": parser.unclassified,
        "affordances": inventory,
    }, sys.stdout, indent=2, sort_keys=True)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
