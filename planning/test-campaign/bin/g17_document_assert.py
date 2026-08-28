"""G17's assertions over the capability-document flow's artifacts.

The bash harness beside this file (`g17-document-flow.sh`) constructs the packages, runs a router,
and renders the frames. This reads what landed and says whether it is what the flow claims.

**Why it is a separate file.** Every check here has an id, and arming works by mutating one input,
re-rendering, and running this again with `--expect-fail <id>`. A control that cannot be named
cannot be watched going red, and an assertion buried inside a heredoc in the harness has no name.

Two rungs are used and they are not interchangeable:

  * **structural** — a node exists in the dump with the text the panel drew. This is what says
    *which* refusal landed, because a refusal's sentence is its identity.
  * **raster** — pixels inside the node's own frame, read off the PNG the harness rendered. This is
    the only rung that can say an image *drew* rather than that a view was laid out. `MarkdownBlockView`
    draws a figure and a refusal placeholder inside the same measured `card`, so before G17 the two
    were the same record; the `figure` / `figure-refusal` nodes split them, and the pixels are what
    keep that split honest if the nodes ever start lying.

Exit codes follow the house rule: 0 clean, 1 an assertion failed, 2 it could not run.
"""

import hashlib
import json
import os
import re
import sys

# The figure the constructed package carries is a flat teal band. It is read back with a tolerance
# rather than by equality: the harness writes sRGB and the hosting view's backing store is rendered
# in the display's own space, so the authored (47, 156, 156) reads back near (81, 154, 155). A test
# pinned to the exact triple would fail on a different display and say nothing about whether the
# image drew.
def is_figure_colour(rgb):
    r, g, b = rgb[0], rgb[1], rgb[2]
    return g > r + 30 and b > r + 30 and abs(g - b) < 25 and g > 90


# The fraction of a card's own frame the band is expected to cover. The band is 8:1 at the body's
# full width, so it covers a little over half the card; the floor is set well under that so a
# resampling change is not a failure, and well over the zero a placeholder produces.
FIGURE_FLOOR = 0.25


# How much of the sheet body has to differ between two tabs. A tab that did not repaint reads
# 0.0; the three documents here are a few short paragraphs on a tall dark panel, so most of the
# body is unchanged ground either way and the floor is set where a paragraph's worth of glyphs
# lands rather than where a full-bleed redraw would.
BODY_FLOOR = 0.01


class Artifacts(object):
    """The dumps, the pictures and the wire responses one run produced."""

    def __init__(self, root):
        self.root = root
        self._dumps = {}
        self._images = {}

    def wire(self, name):
        path = os.path.join(self.root, name + ".json")
        if not os.path.exists(path):
            raise Blocked("no wire response at " + path)
        with open(path, "r") as handle:
            return json.load(handle)

    def dump(self, name):
        if name not in self._dumps:
            path = os.path.join(self.root, name + ".dump.json")
            if not os.path.exists(path):
                raise Blocked("no dump at " + path)
            with open(path, "r") as handle:
                self._dumps[name] = json.load(handle)
        return self._dumps[name]

    def nodes(self, name):
        out = []

        def walk(node):
            out.append(node)
            for child in node.get("children") or []:
                walk(child)

        walk(self.dump(name)["root"])
        return out

    def text_of(self, name, role):
        return [n.get("text") or "" for n in self.nodes(name) if n.get("role") == role]

    def blob(self, name):
        return " ".join((n.get("text") or "") for n in self.nodes(name))

    def blob_under(self, name, role):
        """The drawn text of ONE subtree, which for the tab steps is the only honest scope.

        The titlebar names the package in every frame and the tab bar names all three tabs in
        every frame, so a whole-frame search for a word the read me alone carries finds
        `capability` inside `g17-capability` and reports the changelog frame as drawing the read
        me. That is a detector defect rather than a finding, and it is exactly the shape this
        harness already recorded once: a predicate satisfied by something other than its subject.
        """
        root = self.node(name, role)
        if root is None:
            return None
        out = []

        def walk(node):
            out.append(node.get("text") or "")
            for child in node.get("children") or []:
                walk(child)

        walk(root)
        return " ".join(out)

    def node(self, name, role, contains=None):
        for candidate in self.nodes(name):
            if candidate.get("role") != role:
                continue
            if contains is None or contains in (candidate.get("text") or ""):
                return candidate
        return None

    def png_path(self, name):
        return os.path.join(self.root, name + ".png")

    def image(self, name):
        if name not in self._images:
            try:
                from PIL import Image
            except ImportError as error:
                raise Blocked("Pillow is not importable, so no raster rung can run: %s" % error)
            path = self.png_path(name)
            if not os.path.exists(path):
                raise Blocked("no picture at " + path)
            self._images[name] = Image.open(path).convert("RGB")
        return self._images[name]

    def sha(self, name):
        digest = hashlib.sha256()
        with open(self.png_path(name), "rb") as handle:
            digest.update(handle.read())
        return digest.hexdigest()

    def figure_fraction(self, name, node):
        """How much of one node's own frame is drawn in the figure's colour.

        The frame is in the dump's points and the picture is in pixels; the scale is derived from
        the two rather than assumed to be 2, so a run on a non-retina display measures the same
        thing rather than reading a quarter of the card.
        """
        image = self.image(name)
        width, height = image.size
        scale = float(width) / float(self.dump(name)["size"]["width"])
        frame = node["frame"]
        left = max(0, int(frame["x"] * scale))
        top = max(0, int(frame["y"] * scale))
        right = min(width, int((frame["x"] + frame["width"]) * scale))
        bottom = min(height, int((frame["y"] + frame["height"]) * scale))
        if right <= left or bottom <= top:
            return 0.0, 0
        crop = image.crop((left, top, right, bottom))
        total = crop.size[0] * crop.size[1]
        hits = 0
        for count, colour in crop.getcolors(maxcolors=1 << 20) or []:
            if is_figure_colour(colour):
                hits += count
        return float(hits) / float(total), total


    def body_difference(self, base_name, base_node, frame_name, frame_node):
        """The fraction of one frame's body region whose pixels differ from another's.

        Both crops are taken from each frame's OWN dump, and the scale from each frame's own
        picture, so a node that moved is compared where it actually is rather than where the
        other frame put it. Channel tolerance rather than equality, for `figure_fraction`'s
        reason: two renders of the same ground are not bit-identical after colour management.
        """
        def crop(name, node):
            image = self.image(name)
            width, height = image.size
            scale = float(width) / float(self.dump(name)["size"]["width"])
            f = node["frame"]
            box = (max(0, int(f["x"] * scale)), max(0, int(f["y"] * scale)),
                   min(width, int((f["x"] + f["width"]) * scale)),
                   min(height, int((f["y"] + f["height"]) * scale)))
            return image.crop(box)

        left, right = crop(base_name, base_node), crop(frame_name, frame_node)
        size = (min(left.size[0], right.size[0]), min(left.size[1], right.size[1]))
        if size[0] <= 0 or size[1] <= 0:
            return 0.0, 0
        left, right = left.crop((0, 0) + size), right.crop((0, 0) + size)
        total, differing = size[0] * size[1], 0
        for a, b in zip(left.getdata(), right.getdata()):
            if abs(a[0] - b[0]) > 8 or abs(a[1] - b[1]) > 8 or abs(a[2] - b[2]) > 8:
                differing += 1
        return float(differing) / float(total), total


class Blocked(Exception):
    """A rung could not run. Never reported as agreement."""


class Report(object):
    def __init__(self):
        self.rows = []

    def check(self, ident, passed, message):
        self.rows.append({"id": ident, "pass": bool(passed), "message": message})
        print(("  ok   " if passed else "  FAIL ") + ident + " — " + message)
        return passed

    def failed(self):
        return [row["id"] for row in self.rows if not row["pass"]]


def run(root, report):
    art = Artifacts(root)

    # ---------------------------------------------------------------- FLOW-006.01, on the wire
    served = art.wire("wire-served")
    report.check(
        "G17-W1",
        sorted(served.get("documents", {})) == ["capabilities", "changelog", "readMe"],
        "the route serves all three of the constructed package's documents: %s"
        % sorted(served.get("documents", {})),
    )
    images = served.get("images") or []
    refused = sorted((r.get("reason") or "") for r in (served.get("refusedImages") or []))
    report.check(
        "G17-W2",
        len(images) == 1 and images[0].get("media") == "image/png" and refused == ["escapesPackage"],
        "one figure arrives as image/png and the escaping reference is refused: images=%d refused=%s"
        % (len(images), refused),
    )
    body = json.dumps(served)
    report.check(
        "G17-W3",
        "/m30-look" not in body and os.environ.get("G17_PACKAGE_ROOT", "\0") not in body,
        "the response carries bytes and no filesystem path the app could open",
    )
    nopkg = art.wire("wire-nopackage")
    report.check(
        "G17-W4",
        nopkg.get("reason") == "noPackageDirectory",
        "a server declaring no directory refuses noPackageDirectory — the state all 21 upstreams "
        "on this machine are in: %s" % nopkg.get("reason"),
    )
    toolarge = art.wire("wire-toolarge")
    # `documentTooLarge`, not `tooLarge`. Both routers spell it that way and the app maps that
    # spelling (`ControlAPICapabilityDocumentSource.error(from:capability:)`); `tooLarge` is the
    # *image* refusal, one level in. A check written against the Swift enum's case name rather than
    # against the wire would have passed on a router that never refused anything.
    report.check(
        "G17-W5",
        toolarge.get("reason") == "documentTooLarge"
        and toolarge.get("limit") == 524288
        and toolarge.get("file") == "README.md",
        "a read me over the 512 KB document cap refuses documentTooLarge, naming the file and the "
        "cap: reason=%s file=%s limit=%s"
        % (toolarge.get("reason"), toolarge.get("file"), toolarge.get("limit")),
    )

    # ---------------------------------------------------------------- FLOW-006.02, the read me
    report.check(
        "G17-P1",
        "g17-capability" in art.text_of("readme.served", "titlebar")
        and "trawl" not in art.blob("readme.served"),
        "the frame's titlebar names the served package and M19's fixture capability 'trawl' "
        "appears nowhere: %s" % art.text_of("readme.served", "titlebar"),
    )
    report.check(
        "G17-P2",
        "g17-capability" in art.text_of("readme.served", "heading")
        and any("constructed by" in t for t in art.text_of("readme.served", "sentence")),
        "the package's own H1 and prose are drawn from the bytes the router served",
    )
    report.check(
        "G17-P3",
        art.text_of("readme.served", "tab") == ["Read me", "Changelog", "Capabilities"],
        "all three tab controls are drawn: %s" % art.text_of("readme.served", "tab"),
    )

    # The card the figure is drawn in, located by the alternate text the read me authored. There is
    # deliberately no measured node on the drawn `Image` itself: a node would say a view exists and
    # this needs to say that bytes arrived and were painted, which only the raster can.
    figure = art.node("readme.served", "card", contains="the package's own figure")
    if figure is None:
        report.check("G17-P4", False, "no figure card — the read me's own image block is not drawn")
    else:
        fraction, pixels = art.figure_fraction("readme.served", figure)
        report.check(
            "G17-P4",
            fraction >= FIGURE_FLOOR,
            "the in-package figure DREW: %.1f%% of its %d-pixel card is the band's colour "
            "(floor %.0f%%) — bytes the router sent, decoded and painted, not a placeholder"
            % (fraction * 100.0, pixels, FIGURE_FLOOR * 100.0),
        )

    escaping = art.node("readme.served", "figure-refusal")
    if escaping is None:
        report.check("G17-P5", False, "no `figure-refusal` node — the escaping reference drew nothing")
    else:
        fraction, _ = art.figure_fraction("readme.served", escaping)
        report.check(
            "G17-P5",
            "points outside the package" in (escaping.get("text") or "") and fraction < 0.01,
            "the escaping reference drew its own refusal and no picture (%.2f%% figure colour): %r"
            % (fraction * 100.0, escaping.get("text")),
        )

    # ---------------------------------------------------------------- FLOW-006.03 / .04, the tabs
    report.check(
        "G17-P6",
        any("Changelog" in t for t in art.text_of("changelog.served", "heading")),
        "the changelog tab draws the changelog's own heading: %s"
        % art.text_of("changelog.served", "heading"),
    )
    report.check(
        "G17-P7",
        any("Capabilities" in t for t in art.text_of("capabilities.served", "heading")),
        "the capabilities tab draws the capability list's own heading: %s"
        % art.text_of("capabilities.served", "heading"),
    )

    # ---------------------------------------------------------------- the tabs, tied to the wire
    #
    # G17-P6 and G17-P7 above ask whether a heading with the tab's own name is in the dump. That
    # is true of a panel that draws a heading, and it was the whole of what FLOW-006.03 and .04
    # stood on — which is why their cases sat at `structural-visual` and said in their notes that
    # they moved no count.
    #
    # These two ask the other question: is what the panel drew the document THE ROUTER SERVED?
    # The discriminating vocabulary is COMPUTED from `wire-served.json` rather than written here —
    # the words of six letters or more that one served document carries and the other two do not —
    # so the check cannot be satisfied by a string this file happens to know. Every one of them has
    # to appear in the frame that claims to draw that document, and none of the read me's own
    # must. A panel serving the read me under all three tabs fails on both halves at once.
    served_docs = served.get("documents", {})

    def only_in(key):
        mine = set(re.findall(r"[a-z']{6,}", (served_docs.get(key) or "").lower()))
        for other, text in served_docs.items():
            if other != key:
                mine -= set(re.findall(r"[a-z']{6,}", (text or "").lower()))
        return sorted(mine)

    for ident, frame, key in (("G17-P6W", "changelog.served", "changelog"),
                              ("G17-P7W", "capabilities.served", "capabilities")):
        mine, readme_only = only_in(key), only_in("readMe")
        body = art.blob_under(frame, "detail")
        if body is None:
            report.check(ident, False,
                         "no `detail` node on %s, so there is no document body to read" % frame)
            continue
        drawn = body.lower()
        missing = [w for w in mine if w not in drawn]
        strays = [w for w in readme_only if w in drawn]
        # The denominator, checked before the result. A wire response whose three documents
        # shared every word would give both lists empty and both searches a clean answer, and a
        # clean answer from an empty search is the reading this whole harness exists against.
        if not mine or not readme_only:
            report.check(
                ident, False,
                "the served documents carry no distinguishing vocabulary (%d unique to %s, %d "
                "unique to the read me), so this check measured nothing"
                % (len(mine), key, len(readme_only)),
            )
            continue
        report.check(
            ident,
            not missing and not strays,
            "the %s tab drew the %s THE ROUTER SERVED: all %d word(s) the wire response carries "
            "only in that document are in the panel's own body and none of the %d the read me "
            "carries only in its own is%s"
            % (key, key, len(mine), len(readme_only),
               "" if not (missing or strays)
               else " — missing %s, strayed %s" % (missing[:6], strays[:6])),
        )

    # The same two steps in pixels, because the dump says what a rendering WOULD use and the
    # picture says what was painted. `MeasureDump` renders each frame off the hosting view's own
    # backing store, so a tab that did not repaint produces a body identical to the read me's —
    # which is precisely what control G17-P8 plants. Scoped to the sheet body's own frame, taken
    # from each dump rather than assumed, so the titlebar and the tab bar (which SHOULD be nearly
    # identical across the three) cannot supply the difference.
    for ident, frame, key in (("G17-P6R", "changelog.served", "changelog"),
                              ("G17-P7R", "capabilities.served", "capabilities")):
        body = art.node(frame, "detail")
        base = art.node("readme.served", "detail")
        if body is None or base is None:
            report.check(ident, False,
                         "no `detail` node on %s or on the read me, so no body region to compare"
                         % frame)
            continue
        fraction, pixels = art.body_difference("readme.served", base, frame, body)
        report.check(
            ident,
            fraction >= BODY_FLOOR and pixels > 0,
            "the %s tab REPAINTED the body: %.1f%% of its %d-pixel body region differs from the "
            "read me's (floor %.0f%%) — a tab that changed no pixels would read 0"
            % (key, fraction * 100.0, pixels, BODY_FLOOR * 100.0),
        )
    bodies = [art.blob(n) for n in ("readme.served", "changelog.served", "capabilities.served")]
    same_package = [
        "g17-capability" in art.text_of(n, "titlebar")
        for n in ("readme.served", "changelog.served", "capabilities.served")
    ]
    report.check(
        "G17-P8",
        len(set(bodies)) == 3 and all(same_package),
        "the three tabs draw three different documents out of one package: distinct bodies=%d, "
        "all three name g17-capability=%s" % (len(set(bodies)), all(same_package)),
    )

    # ---------------------------------------------------------------- the refusals
    nopkg_title = art.text_of("refusal.nopackage", "state-title")
    report.check(
        "G17-R1",
        any("has no package to read" in t for t in nopkg_title)
        and art.node("refusal.nopackage", "figure") is None,
        "the nothing-served refusal draws its own state and no figure: %s" % nopkg_title,
    )
    large_title = art.text_of("refusal.toolarge", "state-title")
    large_blob = art.blob("refusal.toolarge")
    report.check(
        "G17-R2",
        any("too large to show here" in t for t in large_title) and "512 KB" in large_blob,
        "the too-large refusal names the file and the cap it broke: %s" % large_title,
    )
    words = [
        " ".join(nopkg_title),
        " ".join(large_title),
        (escaping.get("text") if escaping else "") or "",
    ]
    report.check(
        "G17-R3",
        len(set(words)) == 3 and all(words),
        "the three refusals are pairwise distinguishable in the words they draw: %d distinct"
        % len(set(words)),
    )

    # ---------------------------------------------------------------- lineage
    #
    # The check the campaign has because a wall of 20 captures once showed three unrelated
    # documents while every gate passed. A filename is written by whoever ran the capture, so it is
    # not evidence of anything. Each row of the harness's manifest is tied back to the DUMP taken
    # in the same render: the package the row claims was served has to be the package the panel's
    # titlebar actually names, and the sha256 the row carries has to be the file on disk.
    manifest_path = os.path.join(root, "captures.json")
    if not os.path.exists(manifest_path):
        raise Blocked("no capture manifest at " + manifest_path)
    with open(manifest_path, "r") as handle:
        manifest = json.load(handle)

    shas = {}
    problems = []
    unidentifiable = []
    for row in manifest:
        name = row["frame"]
        shas[name] = art.sha(name)
        if row.get("sha256") != shas[name]:
            problems.append("%s: manifest sha does not match the file on disk" % name)
        if not row.get("subject") or not row.get("step"):
            problems.append("%s: names no campaign surface or no flow step" % name)
        marker = row.get("marker")
        if not marker:
            # The frame cannot corroborate its own row. Recorded rather than waived: see DEF-060.
            unidentifiable.append(name)
            continue
        drawn = " ".join(art.text_of(name, row.get("markerRole") or "titlebar"))
        if marker not in drawn:
            problems.append(
                "%s: the row says the panel would name %r in its %s and it drew %r"
                % (name, marker, row.get("markerRole"), drawn)
            )
    if len(set(shas.values())) != len(manifest):
        problems.append("two rows share one sha256 — the same picture filed under two subjects")

    report.check(
        "G17-L1",
        not problems,
        "each of the %d pictures names the surface and the step it is of, carries the sha256 of the "
        "file on disk, and — for the %d that draw their own subject — is corroborated by what the "
        "frame itself drew%s"
        % (len(manifest), len(manifest) - len(unidentifiable),
           "" if not problems else " — " + "; ".join(problems)),
    )

    # **Not folded into the check above.** One of these frames cannot say what it is a picture of,
    # and a lineage pass that reported five-of-five corroborated would be the exact failure the
    # rule exists to prevent. The panel's too-large refusal names the file and the cap and never the
    # capability, so its picture is tied to its subject by its manifest row alone. DEF-060.
    report.check(
        "G17-L2",
        unidentifiable == ["refusal.toolarge"],
        "%d of %d frames cannot corroborate their own manifest row and are named here rather than "
        "counted as corroborated: %s (DEF-060)"
        % (len(unidentifiable), len(manifest), unidentifiable or "none"),
    )
    return {"sha256": shas, "manifest": manifest, "unidentifiable": unidentifiable}


def main(argv):
    if len(argv) < 2:
        print("usage: g17_document_assert.py <artifact-dir> [--expect-fail CHECK-ID]", file=sys.stderr)
        return 2
    root = argv[1]
    expect_fail = None
    if "--expect-fail" in argv:
        expect_fail = argv[argv.index("--expect-fail") + 1]

    report = Report()
    try:
        extra = run(root, report)
    except Blocked as error:
        print("BLOCKED: %s" % error, file=sys.stderr)
        return 2

    with open(os.path.join(root, "verdicts.json"), "w") as handle:
        json.dump({"checks": report.rows, "captures": extra}, handle, indent=1, sort_keys=True)

    failed = report.failed()
    if expect_fail is not None:
        # Arming. The named control must be the one that bit, and it must actually have bitten.
        if expect_fail in failed:
            print("ARMED: %s went red under the planted fault" % expect_fail)
            return 0
        print(
            "ARM FAILED: %s stayed green under the planted fault (red: %s)" % (expect_fail, failed),
            file=sys.stderr,
        )
        return 1
    if failed:
        print("g17-document-assert: %d of %d checks failed: %s"
              % (len(failed), len(report.rows), failed), file=sys.stderr)
        return 1
    print("g17-document-assert: %d checks, all green" % len(report.rows))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
