#!/usr/bin/env python3
"""The instruments this repository can run as checks, derived from the tree rather than remembered.

R19's resolution paragraph made a claim about instrument coverage four times and was wrong four
times, each time about a DIFFERENT instrument, and each time the refuting instrument was one no
record had ever named:

    pass 1  `a node-side delete would have failed BOTH`     — refuted by `IndexFailureRecordTests`
    pass 2  `parity-cli.sh is NOT what catches that one`     — refuted by `parity-cli.sh` itself
    pass 3  `what IndexFailureRecordTests UNIQUELY holds`    — refuted by `parity-overlap.sh`
    pass 4  `make test catches none of these and cannot`     — refuted by `WatchAdoptionTests`

The fourth verifier wrote the diagnosis rather than a fifth correction: *"only X catches this" and
"X catches none of this" are the same claim shape, and both are unfalsifiable without enumerating
the instrument set, which nobody has done.* Four passes each discovered one member by accident. A
fifth asked for prose would have found a fifth — and while pass 4 was being graded, `main` brought
`parity-divergence.sh` in underneath the paragraph, so the set grows between passes from the trunk
as well as from a verifier.

So this file is the enumeration, and the gate that keeps it from silently growing again. It answers
the four questions the paragraph quantifies over:

    which instruments exist · which reach node · which reach Swift · which contain which

## What an instrument is here

A tracked file this repository can run as a check, in four kinds:

    swift-suite   a file under `app/Tests/<target>/` declaring `@Suite`, `@Test` or `XCTestCase`
    lane          a runnable file under `scripts/acceptance/`
    gate          a runnable check under `scripts/lint/`, `scripts/`, `app/Scripts/` or `planning/`
    make-target   a Makefile target whose recipe runs any of the above, or `swift test` directly

The population is `git ls-files`, never the working directory — the same rule
`reader-accounting.py` states and for the same measured reason: a gate that walks the working tree
reports on whoever last ran it rather than on the repository.

## Reach, and why it is a quotation rather than a judgement

`reaches` is derived from each instrument's OWN source text and every row carries the literal token
that decided it, in `evidence`. A reader who disagrees with a classification can see what was
matched without rerunning anything. That is deliberate: the claim class this file exists to retire
is one nobody could check without re-deriving the set by hand.

    node    the row's source invokes the TypeScript router — `dist/index.js`, `MCP_ROUTER_DIST`,
            `node <path>`, `npm run`, or a sibling `.mjs`
    swift   it invokes the Swift side — `@testable import`, `swift test`, `swift build`, `swiftc`,
            `xcodebuild`, or a built router binary
    both    both sets matched, which is what a differential lane looks like
    static  neither: it reads text, files or the git index and executes no router

`static` is a positive finding, not a gap. Every Python gate under `planning/` is static, and that
is why none of them can appear in an arm matrix.

## Containment, and the one edge that matters

`contained_by` is derived from recipes and dispatch lists, never declared:

  * a Makefile recipe that runs `swift test` with NO `--filter`, in `$(APP_DIR)`, contains every
    `swift-suite` in the package. That single edge is what pass 4 got wrong: `make test` is an
    unfiltered `swift test`, so it is a strict superset of `IndexFailureRecordTests` and cannot be
    green on an arm that suite reddens.
  * a recipe with `--filter <Name>` contains only the suites whose declared type matches.
  * `parity-gate.sh`'s `LANES=` default expands to `parity-<lane>.sh`, one row each.
  * any instrument whose source names another instrument's tracked path contains it.

## What this gate does NOT reach, stated rather than implied

  * It does not run anything. A row saying an instrument reaches Swift says its source invokes
    Swift, not that it is red on any particular arm. Arm results belong in the record that armed
    them, and this census is what makes "the arms were run against N of the M instruments that
    reach this side" a sentence with two checkable numbers in it.
  * A suite's reach is read from its imports. A Swift test that shells out to `node` is classified
    `both`, and one that drives a subprocess through a variable this reader cannot resolve is
    classified from what it can see. Unresolved is counted and named, never assumed.
  * Containment through a variable is not followed. `$(SCRIPT)` in a recipe is dropped with a
    reason and appears in the run line.

Exit 0 when the derived census matches the committed one; 1 when they differ, naming every row that
moved; 2 when the gate measured nothing, which is never a pass; 3 when `--control` finds an arm
that did not fire.
"""
from __future__ import annotations  # `X | None` is evaluated at def time on 3.9; the gates run under /usr/bin/python3

import argparse
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from input_accounting import Tally  # noqa: E402

# The verdict below is UTF-8, and the console's codepage does not get a vote in it: on a
# non-UTF-8 terminal an unencodable rule character would raise UnicodeEncodeError and this
# gate would exit on its terminal rather than on its findings.
for _stream in (sys.stdout, sys.stderr):
    if hasattr(_stream, "reconfigure"):
        _stream.reconfigure(encoding="utf-8")

ROOT = Path(__file__).resolve().parent.parent
CENSUS = Path(__file__).resolve().parent / "instrument-census.tsv"

HEADER = ("id", "kind", "path", "reaches", "evidence", "contained_by")

RUNNABLE_SUFFIXES = (".sh", ".py", ".mjs", ".js", ".swift")

# Where an instrument can live. `planning/` holds the record gates, `app/Scripts/` the mutation
# harness, `scripts/` the lanes and the lint chain.
GATE_DIRS = ("scripts/lint/", "scripts/warden/", "scripts/", "app/Scripts/", "planning/")
LANE_DIR = "scripts/acceptance/"
SUITE_DIR = "app/Tests/"

SUITE_DECL = re.compile(r"@Suite\b|@Test\b|:\s*XCTestCase\b")
SUITE_TYPE = re.compile(r"^(?:public\s+|final\s+|private\s+)*(?:struct|class|enum)\s+([A-Za-z_][A-Za-z0-9_]*)", re.M)

# Reach vocabulary. Each entry is (pattern, token printed as evidence). The token is what lands in
# the TSV, so a disagreement is settled by looking rather than by re-deriving.
# Reach is an INVOCATION SHAPE, never a mention. `runnable-path-gate.py` explains in prose that
# `dist/index.js` is the artefact that actually runs, and a rule keyed on that string alone read the
# lint chain as reaching the node router. Three Swift suites hold the same path as fixture data.
NODE_REACH = [
    (re.compile(r"\bnode\s+[\"'$./]"), "node <path>"),
    (re.compile(r"\bnpm\s+run\b"), "npm run"),
    (re.compile(r"\$\{?MCP_ROUTER_DIST\}?"), "$MCP_ROUTER_DIST"),
    (re.compile(r"command:\s*\"node\""), 'command: "node"'),
    # `subprocess.run(["node", …])` — the argv-list form, where the binary is its own element.
    (re.compile(r"[\"']node[\"']\s*,"), 'argv ["node", …]'),
]
SWIFT_REACH = [
    (re.compile(r"@testable\s+import"), "@testable import"),
    (re.compile(r"\bswift\s+test\b"), "swift test"),
    (re.compile(r"\bswift\s+build\b"), "swift build"),
    (re.compile(r"\bswiftc\b"), "swiftc"),
    (re.compile(r"[\"']swiftc?[\"']\s*,"), 'argv ["swift", …]'),
    (re.compile(r"\bxcodebuild\b"), "xcodebuild"),
    (re.compile(r"\$\{?SWIFT_BIN\}?|\.build/(?:debug|release)/[A-Za-z]"), "swift router binary"),
]

MAKE_TARGET = re.compile(r"^([a-zA-Z][a-zA-Z0-9_-]*):")
SWIFT_TEST_CALL = re.compile(r"swift\s+test\b(?P<rest>[^\n;]*)")
FILTER = re.compile(r"--filter\s+\"?([A-Za-z_][A-Za-z0-9_]*)")
PATH_REF = re.compile(r"(?:\./)?((?:scripts|planning|app/Scripts)/[A-Za-z0-9_./-]+\.(?:sh|py|mjs|js|swift))")
# Containment is an INVOCATION, never a mention. `parity-manifest-check.sh`'s header tells you to
# check `parity-gate.sh` in the same change; reading that as "the check runs the gate" inverts the
# edge, and an inverted containment edge is exactly the class of claim this census exists to retire.
# So a reference counts only where an interpreter, a dot-source or a direct execution precedes it.
# An assignment is not an invocation either: `parity-manifest-check.sh` sets
# `GATE_SH="$REPO_ROOT/scripts/acceptance/parity-gate.sh"` and then only `sed`s and `grep`s it, so a
# rule keyed on `$REPO_ROOT/` alone read the check as running the gate that runs the check.
INVOKED = re.compile(
    r"(?:(?:bash|zsh|sh|python3?|node|swift|exec|source)\s+|^\s*\.\s+|\./)"
    r"[\"']?(?:\$\{?REPO_ROOT\}?/|\$\{?ROOT\}?/|\./)?"
    r"((?:scripts|planning|app/Scripts)/[A-Za-z0-9_./-]+\.(?:sh|py|mjs|js|swift))")
LANES_DEFAULT = re.compile(r'LANES="\$\{PARITY_LANES:-([^}]*)\}"')


def tracked(root: Path) -> list[str]:
    out = subprocess.run(["git", "ls-files"], cwd=root, capture_output=True, text=True, check=True, encoding="utf-8")
    return [line for line in out.stdout.splitlines() if line]


def read(root: Path, rel: str) -> str:
    try:
        return (root / rel).read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""


ECHOING = re.compile(r"^\s*(?:echo|printf|print|note|warn|say)\b|^\s*print\s*\(")
DOCSTRING = re.compile(r'"""')


PY_CALL = re.compile(r"(?:subprocess\.(?:run|call|check_call|check_output|Popen)|os\.system|os\.exec\w*|Popen)\s*\(")


def python_invocations(text: str) -> str:
    """The argument text of every subprocess call in a Python file, and nothing else.

    A Python gate carries its fixtures as string literals, so `#!/usr/bin/env bash\nnode ...` sits
    in the source of a file that runs no node at all — this very gate's control plants exactly that,
    and the first cut read the lint chain as reaching the node router through it. In Python the
    invocation shape is a `subprocess` call, so that is the only text classified.
    """
    out: list[str] = []
    for match in PY_CALL.finditer(text):
        depth, index = 0, match.end() - 1
        while index < len(text):
            if text[index] == "(":
                depth += 1
            elif text[index] == ")":
                depth -= 1
                if depth == 0:
                    break
            index += 1
        out.append(text[match.end():index])
    return "\n".join(out)


def executable_text(text: str, suffix: str) -> str:
    """The part of a file that could run something, with prose and diagnostics removed.

    This repository documents its instruments inside them, at length, and it prints repair
    instructions when a check cannot proceed. `worktree-preflight.sh` says `npm run build` four
    times — three in header comments and once inside an `echo` — and runs it never. Classifying on
    raw text read the whole lint chain as reaching the node router through that file.
    """
    if suffix == ".py":
        return python_invocations(text)
    out: list[str] = []
    in_doc = False
    in_block = False
    for line in text.splitlines():
        if suffix == ".py":
            marks = len(DOCSTRING.findall(line))
            if in_doc:
                in_doc = marks % 2 == 0
                continue
            if marks:
                in_doc = marks % 2 == 1
                continue
        if suffix in (".swift", ".js", ".mjs"):
            if "/*" in line:
                in_block = "*/" not in line
                continue
            if in_block:
                in_block = "*/" not in line
                continue
            line = re.sub(r"//.*$", "", line)
        if suffix in (".sh", ".py"):
            line = re.sub(r"(?<!\$)(?<![\w\"'])#.*$", "", line)
        if ECHOING.match(line):
            continue
        out.append(line)
    return "\n".join(out)


def classify_reach(text: str) -> tuple[str, str]:
    """`(reaches, evidence)` from one instrument's own source, quoting what matched."""
    node = [token for pattern, token in NODE_REACH if pattern.search(text)]
    swift = [token for pattern, token in SWIFT_REACH if pattern.search(text)]
    if node and swift:
        return "both", f"{node[0]} + {swift[0]}"
    if node:
        return "node", node[0]
    if swift:
        return "swift", swift[0]
    return "static", "no router invocation matched"


def suite_types(text: str) -> list[str]:
    return SUITE_TYPE.findall(text)


def collect(root: Path) -> tuple[dict[str, dict], Tally]:
    """Every instrument in the tree, keyed by id, with a tally of everything the reader refused."""
    tally = Tally("instrument-census", "git ls-files")
    rows: dict[str, dict] = {}

    for rel in tracked(root):
        if rel.startswith(SUITE_DIR) and rel.endswith(".swift"):
            text = read(root, rel)
            if not SUITE_DECL.search(text):
                tally.drop(rel, "under app/Tests/ and declares no @Suite, @Test or XCTestCase")
                continue
            # A suite's reach is `swift` BY CONSTRUCTION — `swift test` compiles and runs it. What
            # this reader cannot settle is whether a suite additionally launches the node router:
            # three suites hold `/repo/dist/index.js` as fixture STRING DATA, one holds it in a doc
            # comment, and the first cut read all four as reaching node. So the mention is carried in
            # the row as unresolved rather than promoted to a reach or dropped out of sight.
            node_mention, node_token = next(
                ((True, token) for pattern, token in NODE_REACH
                 if pattern.search(executable_text(text, ".swift"))), (False, ""))
            evidence = "compiled and run by `swift test`"
            if node_mention:
                evidence += f"; names {node_token}, execution unresolved"
            rows[rel] = {"kind": "swift-suite", "path": rel, "reaches": "swift",
                         "evidence": evidence, "contained_by": set(), "types": suite_types(text)}
            tally.keep(rel)
            continue

        if rel.startswith(LANE_DIR):
            if not rel.endswith(RUNNABLE_SUFFIXES):
                tally.drop(rel, "under scripts/acceptance/ and is not a runnable file type")
                continue
            text = read(root, rel)
            reaches, evidence = classify_reach(executable_text(text, Path(rel).suffix))
            rows[rel] = {"kind": "lane", "path": rel, "reaches": reaches,
                         "evidence": evidence, "contained_by": set(), "types": []}
            tally.keep(rel)
            continue

        if rel.endswith(RUNNABLE_SUFFIXES) and any(rel.startswith(d) for d in GATE_DIRS):
            text = read(root, rel)
            reaches, evidence = classify_reach(executable_text(text, Path(rel).suffix))
            rows[rel] = {"kind": "gate", "path": rel, "reaches": reaches,
                         "evidence": evidence, "contained_by": set(), "types": []}
            tally.keep(rel)
            continue

        tally.drop(rel, "not a runnable check under a scanned directory")

    add_make_targets(root, rows, tally)
    add_parity_lanes(root, rows)
    add_source_references(root, rows, tally)
    close_reach(rows)
    return rows, tally


def add_make_targets(root: Path, rows: dict[str, dict], tally: Tally) -> None:
    """Makefile targets, and the containment their recipes establish.

    The edge this exists for: a recipe running `swift test` with no `--filter` contains every
    swift-suite in the package. Reading that from the recipe rather than from memory is what makes
    "`make test` is green on an arm `IndexFailureRecordTests` reddens" impossible to write.
    """
    makefile = read(root, "Makefile")
    if not makefile:
        return
    current: str | None = None
    recipes: dict[str, list[str]] = {}
    for line in makefile.splitlines():
        match = MAKE_TARGET.match(line)
        if match and not line.startswith("\t"):
            current = match.group(1)
            # Prerequisites are containment too: `test: enum-layout-stamp` runs it first.
            recipes.setdefault(current, []).append(line)
        elif line.startswith("\t") and current:
            recipes[current].append(line)
        else:
            # A variable assignment, a comment, a blank line or a `.PHONY` — Makefile text that
            # belongs to no recipe. Named rather than skipped, because a target this reader failed
            # to open would land here silently and take its whole recipe with it.
            tally.drop(line, "a Makefile line outside any recipe")
            if line and not line.startswith((" ", "\t", "#")) and not match:
                current = None

    for target, body in recipes.items():
        recipe = "\n".join(body)
        contained: set[str] = set()
        for ref in PATH_REF.findall(recipe):
            if ref in rows:
                contained.add(ref)
        swift_calls = list(SWIFT_TEST_CALL.finditer(recipe))
        for call in swift_calls:
            names = FILTER.findall(call.group("rest"))
            for rel, row in rows.items():
                if row["kind"] != "swift-suite":
                    continue
                if not names:
                    contained.add(rel)          # unfiltered: the whole package
                elif any(name in row["types"] for name in names):
                    contained.add(rel)
        if "$(" in recipe and not PATH_REF.search(recipe) and not swift_calls:
            tally.drop(f"make:{target}", "recipe reaches its script through a variable this reader does not resolve")
        if not contained:
            tally.drop(f"make:{target}", "a Makefile target whose recipe runs no instrument this census names")
            continue
        reaches, evidence = classify_reach(executable_text(recipe, ".sh"))
        rows[f"make:{target}"] = {"kind": "make-target", "path": "Makefile", "reaches": reaches,
                                  "evidence": evidence, "contained_by": set(), "types": []}
        for rel in contained:
            rows[rel]["contained_by"].add(f"make:{target}")


def add_parity_lanes(root: Path, rows: dict[str, dict]) -> None:
    """`parity-gate.sh`'s default `LANES=` list, expanded to the scripts it dispatches."""
    gate = f"{LANE_DIR}parity-gate.sh"
    if gate not in rows:
        return
    text = read(root, gate)
    match = LANES_DEFAULT.search(text)
    if not match:
        return
    for lane in match.group(1).split():
        rel = f"{LANE_DIR}parity-{lane}.sh"
        if rel in rows:
            rows[rel]["contained_by"].add(gate)


def add_source_references(root: Path, rows: dict[str, dict], tally: Tally) -> None:
    """An instrument that INVOKES another instrument's tracked path contains it.

    A path that merely appears in the source is a mention, and it is dropped with a reason rather
    than turned into an edge — the first cut of this reader read `parity-manifest-check.sh`'s advice
    to *check `parity-gate.sh` in the same change* as the check containing the gate, which is the
    edge backwards.
    """
    for rel, row in list(rows.items()):
        if row["kind"] == "make-target":
            continue
        text = read(root, rel)
        invoked = {ref for ref in INVOKED.findall(text) if ref in rows and ref != rel}
        for ref in invoked:
            rows[ref]["contained_by"].add(rel)
        for ref in set(PATH_REF.findall(text)):
            if ref in rows and ref != rel and ref not in invoked:
                tally.drop(f"{rel} -> {ref}", "names another instrument without invoking it, so it is a mention rather than containment")


def close_reach(rows: dict[str, dict]) -> None:
    """A container reaches whatever it runs, so reach is closed over containment.

    `make lint`'s own recipe invokes no router and its first cut therefore read `static`, while one
    of the gates it runs is a `swift test` harness. A container understating its reach is the same
    shape as the claim this census retires, one level up.
    """
    children: dict[str, set[str]] = {key: set() for key in rows}
    for key, row in rows.items():
        for parent in row["contained_by"]:
            children.setdefault(parent, set()).add(key)

    def resolve(key: str, seen: frozenset) -> tuple[set[str], str]:
        row = rows[key]
        own = set() if row["reaches"] == "static" else set(row["reaches"].split("+"))
        if row["reaches"] == "both":
            own = {"node", "swift"}
        reach, evidence = set(own), row["evidence"]
        for child in sorted(children.get(key, ())):
            if child in seen:
                continue
            sub, _ = resolve(child, seen | {key})
            if sub - reach:
                if not own:
                    evidence = f"via {child} ({rows[child]['evidence']})"
                reach |= sub
        return reach, evidence

    for key in list(rows):
        reach, evidence = resolve(key, frozenset())
        if not reach:
            continue
        rows[key]["reaches"] = "both" if reach == {"node", "swift"} else sorted(reach)[0]
        rows[key]["evidence"] = evidence


def render(rows: dict[str, dict]) -> list[str]:
    lines = [
        "# planning/instrument-census.tsv — every instrument this repository can run as a check.",
        "#",
        "# DERIVED. Written by `planning/instrument-census.py --write`; never edited by hand. The gate",
        "# runs in `make lint` and reds when the tree and this file disagree, which is the point: R19's",
        "# resolution paragraph made four claims quantified over this set while the set was growing",
        "# under it — three times from a verifier's arm and once from `main` bringing a new lane in.",
        "#",
        "# reaches   node · swift · both · static, derived from each row's OWN source, with the literal",
        "#           token that decided it in `evidence`.",
        "# contained_by  who runs it. `make:test` is an unfiltered `swift test`, so it contains every",
        "#           swift-suite, and cannot be green on an arm any of them reddens.",
        "#",
        "\t".join(HEADER),
    ]
    for key in sorted(rows):
        row = rows[key]
        lines.append("\t".join([
            key, row["kind"], row["path"], row["reaches"], row["evidence"],
            ",".join(sorted(row["contained_by"])) or "-",
        ]))
    return lines


def committed() -> list[str]:
    if not CENSUS.exists():
        return []
    return CENSUS.read_text(encoding="utf-8").splitlines()


def summarise(rows: dict[str, dict]) -> None:
    kinds: dict[str, int] = {}
    reaches: dict[str, int] = {}
    for row in rows.values():
        kinds[row["kind"]] = kinds.get(row["kind"], 0) + 1
        reaches[row["reaches"]] = reaches.get(row["reaches"], 0) + 1
    print("  kinds:   " + " · ".join(f"{k} {v}" for k, v in sorted(kinds.items())))
    print("  reaches: " + " · ".join(f"{k} {v}" for k, v in sorted(reaches.items())))


def run(write: bool) -> int:
    rows, tally = collect(ROOT)
    print(f"instrument-census: {tally.line()}")
    if tally.measured_nothing() or not rows:
        print("error: the census named no instrument. An empty census reports every claim about")
        print("       instrument coverage as consistent, which is the failure it exists to catch.")
        return 2
    for reader, name in (("swift-suite", "swift suites"), ("lane", "acceptance lanes"),
                         ("gate", "gates"), ("make-target", "make targets")):
        if not any(row["kind"] == reader for row in rows.values()):
            print(f"error: the {name} reader matched nothing, so its column is unmeasured rather than empty.")
            return 2
    summarise(rows)

    derived = render(rows)
    if write:
        CENSUS.write_text("\n".join(derived) + "\n", encoding="utf-8")
        print(f"  wrote {CENSUS.relative_to(ROOT).as_posix()} — {len(rows)} instruments")
        return 0

    have = committed()
    if have == derived:
        print(f"  census matches the tree — {len(rows)} instruments, exit 0")
        return 0

    have_rows = {line.split("\t")[0]: line for line in have if line and not line.startswith("#") and "\t" in line}
    new_rows = {line.split("\t")[0]: line for line in derived if line and not line.startswith("#") and "\t" in line}
    added = sorted(set(new_rows) - set(have_rows))
    removed = sorted(set(have_rows) - set(new_rows))
    changed = sorted(k for k in set(new_rows) & set(have_rows) if new_rows[k] != have_rows[k])
    print("error: the instrument set has moved and the census has not.")
    for key in added:
        print(f"  + {key}")
    for key in removed:
        print(f"  - {key}")
    for key in changed:
        print(f"  ~ {key}")
        print(f"      was {have_rows[key]}")
        print(f"      now {new_rows[key]}")
    if not (added or removed or changed):
        print("  the rows agree and the header does not — regenerate to pick up the header text.")
    print("  Any record that quantifies over the instruments — 'only X catches this', 'X catches")
    print("  none of these' — is stale until this file moves. Run:")
    print("      python3 planning/instrument-census.py --write")
    return 1


# -------------------------------------------------------------------------------------------------
# The control. Every arm plants something into a scratch repository and asserts this reader reports
# it, because a census that silently classified everything `static` would print a clean run.

def control() -> int:
    arms: list[tuple[str, bool, str]] = []

    def arm(name: str, ok: bool, saw: str) -> None:
        arms.append((name, ok, saw))

    with tempfile.TemporaryDirectory(prefix="instrument-census-control-") as tmp:
        scratch = Path(tmp)
        (scratch / "app/Tests/RouterCoreTests").mkdir(parents=True)
        (scratch / "scripts/acceptance").mkdir(parents=True)
        (scratch / "planning").mkdir(parents=True)
        (scratch / "app/Tests/RouterCoreTests/PlantedSuite.swift").write_text(
            '@testable import RouterCore\n@Suite("planted")\nstruct PlantedSuiteTests {}\n', encoding="utf-8")
        (scratch / "scripts/acceptance/parity-planted.sh").write_text(
            '#!/usr/bin/env bash\nnode "$REPO_ROOT/dist/index.js" watch\n', encoding="utf-8")
        (scratch / "scripts/acceptance/parity-gate.sh").write_text(
            '#!/usr/bin/env bash\nLANES="${PARITY_LANES:-planted}"\n', encoding="utf-8")
        (scratch / "planning/planted-gate.py").write_text("print('reads text only')\n", encoding="utf-8")
        # A gate that only WRITES ABOUT the node artefact. It must stay `static`.
        (scratch / "planning/planted-prose-gate.py").write_text(
            '"""dist/index.js is the thing that actually runs, and it is not tracked."""\n', encoding="utf-8")
        # A lane whose only node references are a header comment and a repair instruction it prints.
        (scratch / "scripts/acceptance/parity-advises.sh").write_text(
            '#!/usr/bin/env bash\n# run `npm run build` first.\n'
            'echo "no dist — run: node dist/index.js"\ntrue\n', encoding="utf-8")
        # A lane that MENTIONS another instrument without running it. The edge must not appear.
        (scratch / "scripts/acceptance/parity-mentions.sh").write_text(
            '#!/usr/bin/env bash\n# move the pin in scripts/acceptance/parity-planted.sh in the same change.\ntrue\n', encoding="utf-8")
        # A lane that INVOKES one. The edge must appear, and the swift reach must close upward.
        (scratch / "scripts/acceptance/parity-invokes.sh").write_text(
            '#!/usr/bin/env bash\nbash "$REPO_ROOT/scripts/acceptance/parity-swifty.sh"\n', encoding="utf-8")
        (scratch / "scripts/acceptance/parity-swifty.sh").write_text(
            '#!/usr/bin/env bash\nswift test --filter Nothing\n', encoding="utf-8")
        (scratch / "Makefile").write_text(
            "test:\n\tcd app; swift test\n\nnarrow:\n\tswift test --filter PlantedSuiteTests\n"
            "\nquiet:\n\t./scripts/acceptance/parity-swifty.sh\n", encoding="utf-8")
        subprocess.run(["git", "init", "-q"], cwd=scratch, check=True)
        subprocess.run(["git", "add", "-A"], cwd=scratch, check=True)

        rows, tally = collect(scratch)

        suite = rows.get("app/Tests/RouterCoreTests/PlantedSuite.swift")
        arm("a planted swift suite is discovered and reaches swift",
            bool(suite) and suite["reaches"] == "swift",
            suite["reaches"] if suite else "not discovered")
        arm("an unfiltered `swift test` recipe contains it",
            bool(suite) and "make:test" in suite["contained_by"],
            ",".join(sorted(suite["contained_by"])) if suite else "-")
        arm("a `--filter` recipe contains it too, because the filter names its type",
            bool(suite) and "make:narrow" in suite["contained_by"],
            ",".join(sorted(suite["contained_by"])) if suite else "-")

        lane = rows.get("scripts/acceptance/parity-planted.sh")
        arm("a planted lane invoking dist/index.js reaches node",
            bool(lane) and lane["reaches"] == "node",
            lane["reaches"] if lane else "not discovered")
        arm("`parity-gate.sh`'s LANES list contains it",
            bool(lane) and "scripts/acceptance/parity-gate.sh" in lane["contained_by"],
            ",".join(sorted(lane["contained_by"])) if lane else "-")

        gate = rows.get("planning/planted-gate.py")
        arm("a gate that executes no router is `static`, which is a finding rather than a gap",
            bool(gate) and gate["reaches"] == "static",
            gate["reaches"] if gate else "not discovered")

        mentions = rows.get("scripts/acceptance/parity-mentions.sh")
        invokes = rows.get("scripts/acceptance/parity-invokes.sh")
        swifty = rows.get("scripts/acceptance/parity-swifty.sh")
        arm("a lane that only NAMES another instrument does not contain it",
            bool(swifty) and "scripts/acceptance/parity-mentions.sh" not in swifty["contained_by"],
            ",".join(sorted(swifty["contained_by"])) if swifty else "not discovered")
        arm("the mention is dropped with a reason rather than dropped silently",
            any("mention rather than containment" in reason for reason in tally.reasons()),
            "; ".join(sorted(tally.reasons())))
        arm("a lane that INVOKES another instrument contains it",
            bool(swifty) and "scripts/acceptance/parity-invokes.sh" in swifty["contained_by"],
            ",".join(sorted(swifty["contained_by"])) if swifty else "not discovered")
        arm("reach closes over containment: a recipe that runs a `swift test` gate reaches swift",
            bool(rows.get("make:quiet")) and rows["make:quiet"]["reaches"] == "swift",
            rows["make:quiet"]["reaches"] if rows.get("make:quiet") else "not discovered")
        arm("and it says which child carried the reach",
            bool(invokes) and invokes["reaches"] == "swift" and invokes["evidence"].startswith("via "),
            invokes["evidence"] if invokes else "not discovered")

        # A Python gate carrying a node invocation as FIXTURE DATA, and one that really calls it.
        (scratch / "planning/planted-fixture-gate.py").write_text(
            'BODY = "#!/usr/bin/env bash\\nnode $ROOT/dist/index.js watch\\n"\nprint(BODY)\n', encoding="utf-8")
        (scratch / "planning/planted-runner-gate.py").write_text(
            'import subprocess\nsubprocess.run(["node", "dist/index.js", "index"], check=True)\n', encoding="utf-8")
        subprocess.run(["git", "add", "-A"], cwd=scratch, check=True)
        rows, tally = collect(scratch)

        prose = rows.get("planning/planted-prose-gate.py")
        arm("a gate that only writes ABOUT dist/index.js does not reach node",
            bool(prose) and prose["reaches"] == "static",
            prose["reaches"] if prose else "not discovered")

        fixture = rows.get("planning/planted-fixture-gate.py")
        runner = rows.get("planning/planted-runner-gate.py")
        arm("a python gate holding a node invocation as a STRING LITERAL stays static",
            bool(fixture) and fixture["reaches"] == "static",
            fixture["reaches"] if fixture else "not discovered")
        arm("a python gate that subprocess-runs node reaches node",
            bool(runner) and runner["reaches"] == "node",
            runner["reaches"] if runner else "not discovered")

        advises = rows.get("scripts/acceptance/parity-advises.sh")
        arm("a lane that only COMMENTS and ECHOES a node invocation does not reach node",
            bool(advises) and advises["reaches"] == "static",
            advises["reaches"] if advises else "not discovered")

        arm("the reader accounts for what it refused",
            tally.total > len(tally.kept) and bool(tally.reasons()),
            tally.line())

        # Drift: the derived census against a committed one that is one row short.
        derived = render(rows)
        short = [line for line in derived if "PlantedSuite" not in line]
        arm("a census missing a row is not equal to the derived one",
            short != derived, f"{len(short)} lines against {len(derived)}")

    print("instrument-census control:")
    bad = 0
    for name, ok, saw in arms:
        print(f"  {'ok  ' if ok else 'FAIL'} {name}")
        if not ok:
            print(f"        saw: {saw}")
            bad += 1
    print(f"  {len(arms) - bad} of {len(arms)} arms fired")
    return 0 if bad == 0 else 3


def subject(pattern: str) -> int:
    """The instruments whose executable text names a subject, grouped by reach.

    The census bounds the set; this bounds the part of it a given change could possibly move. A
    record that says *the arms were run against 4 of the N instruments that reach this side* has two
    numbers in it a reader can re-derive, which is what four passes of *only X* and *X catches none*
    never had.
    """
    try:
        probe = re.compile(pattern)
    except re.error as error:
        print(f"error: {pattern!r} is not a regular expression — {error}")
        return 2
    rows, _ = collect(ROOT)
    hits: dict[str, list[str]] = {}
    for key, row in sorted(rows.items()):
        if row["kind"] == "make-target":
            continue
        text = executable_text(read(ROOT, row["path"]), Path(row["path"]).suffix)
        if probe.search(text):
            hits.setdefault(row["reaches"], []).append(key)
    total = sum(len(names) for names in hits.values())
    print(f"instrument-census --subject {pattern!r}: {total} of {len(rows)} instruments name it")
    if total == 0:
        print("error: no instrument names the subject, so the population is unmeasured rather than empty.")
        return 2
    for reach in sorted(hits):
        print(f"  {reach} ({len(hits[reach])}):")
        for name in hits[reach]:
            print(f"    {name}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true", help="regenerate the census from the tree")
    parser.add_argument("--control", action="store_true", help="run the arms and report, changing nothing")
    parser.add_argument("--subject", metavar="REGEX",
                        help="list the instruments whose executable text names this subject")
    args = parser.parse_args()
    if args.control:
        return control()
    if args.subject:
        return subject(args.subject)
    return run(args.write)


if __name__ == "__main__":
    sys.exit(main())
