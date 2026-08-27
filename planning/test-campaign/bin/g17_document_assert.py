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
