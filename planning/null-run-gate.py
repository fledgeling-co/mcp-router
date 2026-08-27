#!/usr/bin/env python3
"""Run this repository's hermetic assertions against input that must turn them red.

The other half of G4. `reader-accounting.py` asks whether a reader can say what it dropped; this
asks whether an assertion can fail at all. An assertion that passes on an empty fixture, an
inverted state or poisoned input is **provably vacuous** — that is a property of the assertion
itself, measured by running it, rather than an inference about what its name suggests it reads. It
carries no false-finding class on correct code, which is what made it buildable here after the
Google lane refused name → quantity mapping outright.

Two kinds of arm, and the difference matters:

  poison  plant the exact defect the assertion is named for, and require red. A violation
          detector over an EMPTY tree correctly passes, so emptiness proves nothing about it.
  null    hand the assertion nothing, and require it to refuse rather than report clean. A
          census, a denominator or a coverage claim over zero input must be a usage error;
          `make test`'s zero-test guard and the reconciler's `examined == 0` exits are this
          check written by hand, twice.

Everything runs in a scratch tree under `mktemp`. No file in this repository is written, and the
instruments are copied to the scratch tree rather than pointed at it, because each one resolves its
own root from `__file__` or `$0`.

What this does NOT reach, stated rather than implied:

  * The population is the hermetic instruments — the two Python gates in `planning/` and the two
    shell lints with no selftest of their own. `no-harness-config-writes.sh` already has one
    (`no-harness-config-writes-selftest.sh`, ten plants including a deliberate miss) and is not
    re-armed here. The other 62 shell files under `scripts/` need a booted simulator, a built
    router or a node build, and arming those is `parity-lane-selftest.sh`'s and
    `mock-fidelity-selftest.sh`'s job, not this file's.
  * An assertion can bite here and still read the wrong quantity. Instances 2, 3, 7 and the
    `egress` one in `G4-assertions-that-do-not-read-their-own-quantity.md` all go red under a big
    enough perturbation of SOMETHING, and stay green under a perturbation of the thing in their
    name. This gate proves an assertion is not vacuous; it does not prove it is aimed correctly.
  * Check E is not armed. It reads `git branch --merged main`, and a scratch tree is not a
    repository, so the one arm that would exercise it would be measuring the git failure path
    instead. Named here rather than quietly absent.

Exit 0 when every arm bit; 1 when one did not; 2 when the gate could not run one.
"""
from __future__ import annotations  # `X | None` is evaluated at def time on 3.9; the gates run under /usr/bin/python3


import re
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# ---------------------------------------------------------------------------------------------
# The clean fixture pair. It must reconcile at exit 0, or a poison turning it red proves nothing:
# an arm on a fixture that was already failing measures the fixture, not the assertion.
CLEAN_ORCH = """# Fixture orchestrator

| id | subject | status |
| --- | --- | --- |
| F1 | the first item | **Merged** `abc1234` |

| id | note | parent | detail |
| --- | --- | --- | --- |
| D-f1-a | a deferred child | F1 | what it defers |
"""

CLEAN_LEDGER = """# Fixture ledger

| id | subject | brief | plan | spec | status |
| --- | --- | --- | --- | --- | --- |
| F1 | the first item | f1.md | - | - | **Done** — merged to `main` at `abc1234` |
"""

# A reader that decomposes raw input, discards part of it, and records nothing. Planted to prove
# `reader-accounting.py` refuses a NEW silent drop rather than only cataloguing the old ones.
LEAKY_READER = '''"""A reader that drops rows and never says so."""
from pathlib import Path


def rows(path):
    kept = []
    for line in Path(path).read_text().splitlines():
        if not line.startswith("| "):
            continue
        kept.append(line)
    return kept
'''

CLEAN_SWIFT = """enum Wire {
    static func encode(_ value: Int) -> String { String(value) }
    // swift-wire-exempt: a local accumulator that never reaches the wire
    static var scratch: [String: Int] = [:]
}
"""

# The same file with no exemption line. `no-wire-codable.sh` cannot survive a tree that records
# zero exemptions — see the WIRE-zero-exemptions arm.
UNEXEMPTED_SWIFT = """enum Wire {
    static func encode(_ value: Int) -> String { String(value) }
}
"""


@dataclass
class Arm:
    ident: str
    target: str
    kind: str            # poison | null
    why: str             # what this arm proves the assertion can still see
    build: object        # (scratch root) -> None
    exit_code: object    # int, or a predicate over the exit code
    repo: bool = False   # git-init the scratch tree and track what the builders wrote
    expect: str = ""     # a substring the output must carry
    forbid: str = ""     # a substring the output must NOT carry
    run: str = ""        # path to execute, when it differs from `target`


def reconciler_tree(root: Path) -> None:
    (root / "planning" / "features-to-triage").mkdir(parents=True)
    for name in ("ledger-reconcile.py", "input_accounting.py"):
        shutil.copy(ROOT / "planning" / name, root / "planning" / name)
    (root / "ORCHESTRATOR.md").write_text(CLEAN_ORCH, encoding="utf-8")
    (root / "planning" / "features-to-triage" / "LEDGER.md").write_text(
        CLEAN_LEDGER, encoding="utf-8")


def accounting_tree(root: Path) -> None:
    (root / "planning").mkdir(parents=True)
    (root / "scripts").mkdir(parents=True)
    for name in ("reader-accounting.py", "input_accounting.py"):
        shutil.copy(ROOT / "planning" / name, root / "planning" / name)
    # Only the declarations for the two files the scratch tree actually holds. Copying the whole
    # registry would leave fifteen rows naming readers that are not there, and every arm would then
    # be measuring the stale-row check instead of the one it is named for.
    keep = [line for line in (ROOT / "planning" / "reader-accounting.tsv")
            .read_text(encoding="utf-8").splitlines()
            if line.startswith("planning/reader-accounting.py::")]
    (root / "planning" / "reader-accounting.tsv").write_text(
        f"# scratch registry\n# rows: {len(keep)}\n" + "\n".join(keep) + "\n", encoding="utf-8")


def script_dirs(script: str) -> tuple[str, ...]:
    """The directories a lint script names, read out of the script rather than restated beside it.

    M15 widened `GEOMETRY_DIRS` in `no-raw-design-values.sh` from three to four and the literal
    here stayed at three. Every RAW arm then built a tree the rule exited early on — it printed
    `the geometry checks did not run`, never reached the plant, stayed green, and the arm
    correctly reported that it could not discriminate. `make lint` was red on the merged tree for
    that and nothing else.

    That is this item's own thirteenth instance one level up: a hardcoded list of what to create
    is a denominator that stops tracking its numerator the first time somebody adds a directory.
    So take every `"$ROOT/…"` the script itself names, in order, de-duplicated. Over-inclusion is
    free — a scratch directory nothing scans costs one empty mkdir — while under-inclusion is the
    failure above, so a whole-file sweep is deliberately the loose direction.

    The one shape it would read wrong is a `"$ROOT/…"` naming a file, which would be created as a
    directory. The script names none today, and one appearing would make the arm go loud rather
    than quiet: the read fails, `set -euo pipefail` kills the script, and the arm reports that it
    could not discriminate instead of reporting a pass.
    """
    text = (ROOT / "scripts" / "lint" / script).read_text(encoding="utf-8")
    found = tuple(dict.fromkeys(re.findall(r'"\$ROOT/([A-Za-z0-9_./+-]+)"', text)))
    if not found:
        raise LookupError(f'{script} names no "$ROOT/…" directory — the derivation stopped '
                          "matching, and a fixture built from nothing measures nothing")
    return found


def lint_tree(script: str, dirs: tuple[str, ...] | None = None, content: str = "") -> object:
    """A scratch tree for a shell lint. `dirs=None` derives them from the script — see above."""
    def build(root: Path) -> None:
        (root / "scripts" / "lint").mkdir(parents=True)
        shutil.copy(ROOT / "scripts" / "lint" / script, root / "scripts" / "lint" / script)
        for d in (script_dirs(script) if dirs is None else dirs):
            (root / d).mkdir(parents=True, exist_ok=True)
            (root / d / "Clean.swift").write_text(content or CLEAN_SWIFT, encoding="utf-8")
    return build


def chain(*builders):
    def build(root: Path) -> None:
        for b in builders:
            b(root)
    return build


def append(rel: str, text: str):
    return lambda root: (root / rel).write_text(
        (root / rel).read_text(encoding="utf-8") + text, encoding="utf-8")


def write(rel: str, text: str):
    def build(root: Path) -> None:
        (root / rel).parent.mkdir(parents=True, exist_ok=True)
        (root / rel).write_text(text, encoding="utf-8")
    return build


def sub(rel: str, old: str, new: str):
    def build(root: Path) -> None:
        text = (root / rel).read_text(encoding="utf-8")
        if old not in text:
            raise LookupError(f"{rel}: the arm's anchor {old[:40]!r} is not in the fixture")
        (root / rel).write_text(text.replace(old, new, 1), encoding="utf-8")
    return build


def empty_accounting_tree(root: Path) -> None:
    """The gate outside the tree it scans, so `planning/` and `scripts/` can genuinely be empty.

    Copying it INTO the scratch `planning/` would leave it scanning itself, and the arm would then
    prove only that the gate can find one file. It lives in `tools/` here, which is not scanned.
    """
    (root / "tools").mkdir(parents=True)
    (root / "planning").mkdir(parents=True)
    (root / "scripts").mkdir(parents=True)
    for name in ("reader-accounting.py", "input_accounting.py"):
        shutil.copy(ROOT / "planning" / name, root / "tools" / name)


def empty_raw_tree(root: Path) -> None:
    (root / "scripts" / "lint").mkdir(parents=True)
    shutil.copy(ROOT / RAW, root / RAW)
    for d in script_dirs("no-raw-design-values.sh"):
        (root / d).mkdir(parents=True, exist_ok=True)


PIN_CLASS = "planning/pin-class-gate.py"

#: The reference text a `pin-class-gate.py` arm plants a verbatim copy out of.
PIN_SRC = "export const BANNER = `a reference string long enough to matter here, forty plus`;\n"
PIN_PREAMBLE = "const config = require(join(distDir, 'config.js'));\n"
PIN_COMPLIANT = """// pin-class: src-export — config.parseServer
write('fixture-one', {
  description: 'x',
  cases: rows.map((r) => ({ id: r.id, out: config.parseServer(r.name, r.raw) }))
});
"""


def pin_class_tree(extra_js: str = "", extra_vectors: tuple[str, ...] = ()):
    """A miniature vector corpus: one compliant region, plus one region per carried name.

    The carries are generated FROM the gate's own `CARRY` constant rather than spelled out, so an
    arm cannot drift from the set it is standing in for. Without them the baseline would be red on
    `CARRY names ... and no region produces it`, which is the check that stops a carry outliving
    the vector it excuses.
    """
    import importlib.util

    spec = importlib.util.spec_from_file_location("pin_class_gate", ROOT / PIN_CLASS)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    carried = sorted(module.CARRY)

    def build(root: Path) -> None:
        (root / "planning").mkdir(parents=True, exist_ok=True)
        shutil.copy(ROOT / PIN_CLASS, root / PIN_CLASS)
        (root / "src").mkdir(parents=True, exist_ok=True)
        (root / "src" / "reference.ts").write_text(PIN_SRC, encoding="utf-8")
        (root / "scripts" / "parity").mkdir(parents=True, exist_ok=True)
        body = [PIN_PREAMBLE, PIN_COMPLIANT]
        for name in carried:
            body.append(
                f"// pin-class: src-export — config.notThere\n"
                f"// pin-carry: P9 — a stand-in for the real carry of the same name\n"
                f"write('{name}', {{ cases: rows.map((r) => Number(r.raw)) }});\n")
        body.append(extra_js)
        (root / "scripts" / "parity" / "fixture.mjs").write_text("".join(body), encoding="utf-8")
        vectors = root / "app" / "Tests" / "RouterCoreTests" / "Vectors"
        vectors.mkdir(parents=True, exist_ok=True)
        for name in ["fixture-one", *carried, *extra_vectors]:
            (vectors / f"{name}.json").write_text("{}\n", encoding="utf-8")
    return build


def pin_class_empty(root: Path) -> None:
    """The gate and a reference, and no generator at all — it must refuse, not report clean."""
    (root / "planning").mkdir(parents=True, exist_ok=True)
    shutil.copy(ROOT / PIN_CLASS, root / PIN_CLASS)
    (root / "src").mkdir(parents=True, exist_ok=True)
    (root / "src" / "reference.ts").write_text(PIN_SRC, encoding="utf-8")
    (root / "scripts").mkdir(parents=True, exist_ok=True)


LEDGER_MD = "planning/features-to-triage/LEDGER.md"
RECONCILE = "planning/ledger-reconcile.py"
ACCOUNTING = "planning/reader-accounting.py"
WIRE = "scripts/lint/no-wire-codable.sh"
RAW = "scripts/lint/no-raw-design-values.sh"

# `no-wire-codable.sh` is not derived from: it spells its directories as bare names under its own
# `ROOT=` and tolerates a missing one (`[ -d ] && present+=`), erroring only when none exist. A
# stale literal there cannot produce the early exit above, so the arms keep naming the two they
# mean to plant in. `no-raw-design-values.sh` requires every listed directory, which is what made
# its list load-bearing — the RAW arms take theirs from `script_dirs`.
WIRE_DIRS = ("app/Sources/RouterCore/Control", "app/Sources/RouterCore/Registry")

ARMS: list[Arm] = [
    # ---- the baseline. Every poison below is only evidence because this one is green -------
    Arm("BASE-reconciler", RECONCILE, "poison",
        "the clean fixture reconciles, so a red under a poison is the poison",
        reconciler_tree, 0, expect="reconciled — no findings"),

    Arm("A", RECONCILE, "poison", "a row in ORCHESTRATOR's table that LEDGER never names",
        chain(reconciler_tree, append("ORCHESTRATOR.md", "| R2 | a second item | **To Do** |\n")),
        1, expect="A. in ORCHESTRATOR's table"),
    Arm("B", RECONCILE, "poison", "a row in LEDGER's table that ORCHESTRATOR never names",
        chain(reconciler_tree,
              append(LEDGER_MD, "| R3 | a third item | r3.md | - | - | **To Do** |\n")),
        1, expect="B. in LEDGER's table"),
    Arm("C", RECONCILE, "poison", "an id named only in LEDGER's prose while ORCHESTRATOR has a row",
        chain(reconciler_tree,
              append("ORCHESTRATOR.md", "| R2 | a second item | **To Do** |\n"),
              append(LEDGER_MD, "\nR2 is handled elsewhere.\n")),
        1, expect="C. named only in LEDGER's prose"),
    Arm("D", RECONCILE, "poison", "an allocation note calling a live id free",
        chain(reconciler_tree,
              append("ORCHESTRATOR.md", "| F3 | a third item | **Merged** `def5678` |\n"),
              append(LEDGER_MD, "\nF2-F4 are unused.\n")),
        1, expect="D. an allocation note's range"),
    Arm("F", RECONCILE, "poison", "one id on two rows describing two different items",
        chain(reconciler_tree,
              append("ORCHESTRATOR.md", "| F1 | zzzz qqqq wwww | **Merged** `abc1234` |\n")),
        1, expect="F. one id carrying two different items"),
    Arm("G", RECONCILE, "poison", "a LEDGER row ORCHESTRATOR mentions in prose but never rows",
        chain(reconciler_tree,
              append(LEDGER_MD, "| R5 | a fifth item | r5.md | - | - | **To Do** |\n"),
              append("ORCHESTRATOR.md", "\nR5 was folded into F1.\n")),
        1, expect="G. in LEDGER's table but ORCHESTRATOR has no row"),
    Arm("H", RECONCILE, "poison", "two ORCHESTRATOR rows for one id disagreeing on status",
        chain(reconciler_tree,
              sub("ORCHESTRATOR.md", "| F1 | the first item | **Merged** `abc1234` |\n",
                  "| F1 | the first item | **Merged** `abc1234` |\n"
                  "| F1 | the first item | **To Do** |\n")),
        1, expect="H. two ORCHESTRATOR rows for one id"),
    Arm("I", RECONCILE, "poison", "the two files disagreeing about whether an item shipped",
        chain(reconciler_tree, sub(LEDGER_MD, "**Done** — merged to `main` at `abc1234`",
                                   "**Ready for AI**")),
        1, expect="I. LEDGER and ORCHESTRATOR disagree"),
    Arm("J", RECONCILE, "poison", "a row parsing to more cells than its header",
        chain(reconciler_tree,
              append("ORCHESTRATOR.md", "| D-f1-b | a note with a | pipe in it | F1 | detail |\n")),
        1, expect="J. a table row parses to more cells"),
    Arm("K", RECONCILE, "poison", "a register id occurring twice with different bodies",
        chain(reconciler_tree,
              append("ORCHESTRATOR.md", "| D-f1-a | a different note | F1 | other detail |\n")),
        1, expect="K. a deferred-register id occurs more than once"),
    Arm("L", RECONCILE, "poison", "an unresolved merge-conflict marker in a tracker file",
        chain(reconciler_tree, append("ORCHESTRATOR.md", "<<<<<<< HEAD\n=======\n>>>>>>> main\n")),
        1, expect="L. a tracker file carries an unresolved merge-conflict marker"),

    # ---- null. The checks must refuse rather than report clean over nothing -----------------
    Arm("NULL-reconciler-empty", RECONCILE, "null",
        "both tracker files empty — every check has nothing to read",
        chain(reconciler_tree, write("ORCHESTRATOR.md", ""), write(LEDGER_MD, "")),
        2, expect="usage error", forbid="reconciled — no findings"),
    Arm("NULL-reconciler-no-status", RECONCILE, "null",
        "tables with no Status column — H and I have nothing to compare",
        chain(reconciler_tree,
              sub("ORCHESTRATOR.md", "| id | subject | status |", "| id | subject | note |")),
        2, expect="usage error", forbid="reconciled — no findings"),

    # ---- the accounting gate, armed against itself -------------------------------------------
    Arm("BASE-accounting", ACCOUNTING, "poison",
        "the scratch tree is accounted, so a red under a plant is the plant",
        accounting_tree, 0, expect="accounted —", repo=True),
    Arm("ACC-silent-reader", ACCOUNTING, "poison",
        "a newly planted reader that discards raw input and records nothing",
        chain(accounting_tree, write("scripts/leaky.py", LEAKY_READER)),
        1, expect="discard raw input and record nothing", repo=True),
    Arm("ACC-pin", ACCOUNTING, "poison",
        "a declaration deleted without moving the pinned row count",
        chain(accounting_tree,
              lambda root: (root / "planning" / "reader-accounting.tsv").write_text(
                  "\n".join(line for line in (root / "planning" / "reader-accounting.tsv")
                            .read_text(encoding="utf-8").splitlines()
                            if "::read_registry" not in line) + "\n", encoding="utf-8")),
        1, expect="against a pinned", repo=True),
    Arm("ACC-stale", ACCOUNTING, "poison",
        "a declaration naming a reader that no longer exists",
        chain(accounting_tree,
              lambda root: (root / "planning" / "reader-accounting.tsv").write_text(
                  (root / "planning" / "reader-accounting.tsv").read_text(encoding="utf-8")
                  .replace("# rows: 4", "# rows: 5")
                  + "planning/gone.py::vanished\tdeclared\tthis reader was deleted\n",
                  encoding="utf-8")),
        1, expect="declaration outlived its reader", repo=True),
    Arm("NULL-accounting-empty", ACCOUNTING, "null",
        "a tree with no Python readers at all",
        empty_accounting_tree, 2, expect="usage error", forbid="accounted —",
        run="tools/reader-accounting.py", repo=True),

    # ---- the two shell lints with no selftest of their own ------------------------------------
    Arm("BASE-wire", WIRE, "poison", "the scratch tree is clean, so a red under a plant is the plant",
        lint_tree("no-wire-codable.sh", WIRE_DIRS), 0, expect="no-wire-codable: clean"),
    Arm("WIRE-codable", WIRE, "poison", "a Codable conformance on a wire path",
        chain(lint_tree("no-wire-codable.sh", WIRE_DIRS),
              write("app/Sources/RouterCore/Control/Bad.swift",
                    "struct Payload: Codable {\n    let name: String\n}\n")),
        1, expect="Codable conformance"),
    Arm("WIRE-dictionary", WIRE, "poison", "an unexempted Swift Dictionary on a wire path",
        chain(lint_tree("no-wire-codable.sh", WIRE_DIRS),
              write("app/Sources/RouterCore/Control/Bad.swift",
                    "enum Bag {\n    static var store: [String: Int] = [:]\n}\n")),
        1, expect="Swift Dictionary loses member order"),
    # Asserts a DEFECT, on the same principle as P10 in no-harness-config-writes-selftest.sh: a
    # limit written down as an assertion is visible from a run rather than only from a paragraph,
    # and closing it turns this arm red on purpose. `no-wire-codable.sh` ends with
    # `exemptions=$(grep … | wc -l)` under `set -euo pipefail`, so a tree recording zero exemptions
    # makes grep exit 1, the assignment inherit it and the script die — after printing `clean`.
    # Exit 1 is its violation code, so a clean scan reports a violation. Found 2026-08-22 by this
    # gate's first run; the real tree carries exemptions today, which is why nothing has hit it.
    Arm("WIRE-zero-exemptions", WIRE, "poison",
        "a clean tree recording no exemption at all — asserts the known defect, not a pass",
        lint_tree("no-wire-codable.sh", WIRE_DIRS, UNEXEMPTED_SWIFT),
        1, expect="no-wire-codable: clean"),

    Arm("NULL-wire", WIRE, "null", "none of the scanned directories exist",
        lint_tree("no-wire-codable.sh", ()), 2,
        expect="scanned nothing", forbid="no-wire-codable: clean"),

    Arm("BASE-raw", RAW, "poison", "the scratch tree is clean, so a red under a plant is the plant",
        lint_tree("no-raw-design-values.sh"), 0, expect="no-raw-design-values: clean"),
    Arm("RAW-import", RAW, "poison", "MCPRouterKit importing a UI framework",
        chain(lint_tree("no-raw-design-values.sh"),
              write("app/Sources/MCPRouterKit/Bad.swift", "import SwiftUI\n")),
        1, expect="must import no UI framework"),
    Arm("RAW-bridge", RAW, "poison", "a shell growing its own colour bridge again",
        chain(lint_tree("no-raw-design-values.sh"),
              write("app/MCPRouter/Bad.swift",
                    "extension ColorToken {\n    var swiftUIColor: Int { 0 }\n}\n")),
        1, expect="private colour bridge in a shell"),
    Arm("NULL-raw", RAW, "null", "the scanned directories hold no Swift files",
        empty_raw_tree, 1, expect="the gate did not run",
        forbid="no-raw-design-values: clean"),

    # ---- the pin-class gate (P11) --------------------------------------------------------------
    Arm("BASE-pin-class", PIN_CLASS, "poison",
        "the fixture corpus is compliant, so a red under a plant is the plant",
        pin_class_tree(), 0, expect="every vector declares a pin class", repo=True),
    Arm("PIN-unannotated", PIN_CLASS, "poison",
        "a new vector written by a call no pin-class annotation covers",
        pin_class_tree("write('fixture-two', { cases: [] });\n", ("fixture-two",)),
        1, expect="is written by nothing that declares a pin class", repo=True),
    Arm("PIN-retyped", PIN_CLASS, "poison",
        "a src-export region that computes its expectation instead of importing it",
        pin_class_tree("// pin-class: src-export — config.parseServer\n"
                       "write('fixture-three', { cases: rows.map((r) => Math.min(Number(r.raw)"
                       " || 30, 60)) });\n", ("fixture-three",)),
        1, expect="computes its own expectation", repo=True),
    Arm("PIN-declared-carry", PIN_CLASS, "poison",
        "a region excusing itself with a pin-carry line for a name this gate does not carry",
        pin_class_tree("// pin-class: src-export — config.parseServer\n"
                       "// pin-carry: P9 — invented on the spot\n"
                       "write('fixture-four', { cases: rows.map((r) => Number(r.raw)) });\n",
                       ("fixture-four",)),
        1, expect="a carry cannot be declared into existence", repo=True),
    Arm("PIN-builtin-vocabulary", PIN_CLASS, "poison",
        "a platform-builtin region declaring a builtin the reference also implements",
        pin_class_tree("// pin-class: platform-builtin — String#localeCompare\n"
                       "write('fixture-five', { cases: rows.map((r) => r.a.localeCompare(r.b)) });\n",
                       ("fixture-five",)),
        1, expect="not in the closed builtin vocabulary", repo=True),
    Arm("PIN-verbatim", PIN_CLASS, "poison",
        "a region carrying a template literal lifted verbatim out of src/",
        pin_class_tree("// pin-class: src-export — config.parseServer\n"
                       "write('fixture-six', { cases: rows.map((r) => config.parseServer("
                       "`a reference string long enough to matter here, forty plus`)) });\n",
                       ("fixture-six",)),
        1, expect="appears verbatim in src/", repo=True),
    Arm("NULL-pin-class", PIN_CLASS, "null",
        "a tree with no generator and no vectors — the census is empty",
        pin_class_empty, 2, expect="measured nothing",
        forbid="every vector declares a pin class", repo=True),
]

# Assertions in this repository that this gate does NOT arm, with the reason. Counted and printed,
# because a population stated as "the hermetic ones" and never enumerated is the denominator
# failure this item exists to stop.
NOT_ARMED = [
    ("ledger-reconcile.py check E", "reads `git branch --merged main`; the reconciler's scratch "
                                    "trees are not repositories, so the arm would measure the git "
                                    "failure path. The accounting arms are given one because "
                                    "`git ls-files` IS their instrument's enumeration"),
    ("scripts/lint/no-harness-config-writes.sh", "already armed by its own selftest — ten plants "
                                                 "including a deliberate miss (P10)"),
    ("62 further shell files under scripts/", "need a booted simulator, a built Swift router or a "
                                              "node build; parity-lane-selftest.sh and "
                                              "mock-fidelity-selftest.sh own those"),
    ("the Swift suite (1684 tests)", "armed by scripts/red-green.py's mutation lane, not here"),
]


def make_repo(root: Path) -> str:
    """Track everything the builders wrote. Returns "" on success, or why it could not.

    `reader-accounting.py` enumerates through `git ls-files`, so a scratch tree that is not a
    repository would exercise its cannot-enumerate path and every accounting arm would be
    measuring that instead of the check it is named for. Only the arms that declare `repo=True`
    get one: the reconciler's check E reads `git branch --merged main`, and handing it a
    repository with no `main` would arm the git failure path rather than the check, which is the
    reason NOT_ARMED gives for leaving it out.

    Paths are collected before `git init` so the index never grows `.git`'s own contents, and are
    named explicitly rather than swept, so an arm's fixture is exactly what its builders wrote.
    The walk is partitioned rather than filtered: git has no index entry for a directory, so the
    two lists are what a scratch tree is made of rather than a kept half and a discarded one, and
    an empty directory going untracked is the property `NULL-accounting-empty` stands on.
    """
    files: list[str] = []
    dirs: list[str] = []
    for entry in sorted(root.rglob("*")):
        (files if entry.is_file() else dirs).append(str(entry.relative_to(root)))
    try:
        subprocess.run(["git", "init", "-q"], cwd=root, check=True, capture_output=True,
                       timeout=60)
        if files:
            subprocess.run(["git", "add", "--"] + files, cwd=root, check=True,
                           capture_output=True, timeout=60)
    except (OSError, subprocess.SubprocessError) as exc:
        return (f"the scratch repository could not be built over {len(files)} file(s) in "
                f"{len(dirs)} directories: {exc}")
    return ""


def fire(arm: Arm) -> tuple[str, str]:
    """Run one arm in a scratch tree. Returns (verdict, detail); verdict is bit | held | blocked."""
    with tempfile.TemporaryDirectory(prefix="g4-null-run-") as tmp:
        root = Path(tmp)
        try:
            arm.build(root)
        except (OSError, LookupError) as exc:
            return "blocked", f"the scratch tree could not be built: {exc}"
        if arm.repo:
            verdict = make_repo(root)
            if verdict:
                return "blocked", verdict
        script = root / (arm.run or arm.target)
        if not script.is_file():
            return "blocked", f"{arm.run or arm.target} is not in the scratch tree"
        runner = [sys.executable] if script.suffix == ".py" else ["/bin/bash"]
        try:
            proc = subprocess.run(runner + [str(script)], cwd=root, capture_output=True,
                                  text=True, timeout=180)
        except (OSError, subprocess.SubprocessError) as exc:
            return "blocked", f"could not run {script.name}: {exc}"
        out = proc.stdout + proc.stderr
        wrong = []
        if proc.returncode != arm.exit_code:
            wrong.append(f"exit {proc.returncode}, expected {arm.exit_code}")
        if arm.expect and arm.expect not in out:
            wrong.append(f"output does not carry {arm.expect!r}")
        if arm.forbid and arm.forbid in out:
            wrong.append(f"output still carries {arm.forbid!r}")
        if wrong:
            tail = "\n".join(f"      {line}" for line in out.strip().splitlines()[-6:])
            return "held", "; ".join(wrong) + (f"\n{tail}" if tail else "")
        return "bit", f"exit {proc.returncode}"


def main() -> int:
    only = [a for a in sys.argv[1:] if not a.startswith("-")]
    arms = [a for a in ARMS if not only or a.ident in only]
    if not arms:
        print(f"usage error: no arm matches {only}. A gate that ran nothing is not a gate that "
              "passed.", file=sys.stderr)
        return 2

    print("null-run — every assertion below is run against input that must change its verdict")
    print()
    verdicts: dict[str, list[tuple[Arm, str]]] = {"bit": [], "held": [], "blocked": []}
    for arm in arms:
        verdict, detail = fire(arm)
        verdicts[verdict].append((arm, detail))
        mark = {"bit": "  bit ", "held": " HELD ", "blocked": " BLOCK"}[verdict]
        print(f"{mark} {arm.ident:22s} {arm.kind:6s} {arm.target.split('/')[-1]:24s} {arm.why}")
        if verdict != "bit":
            print(f"         {detail}")

    print()
    print(f"  armed        {len(arms):3d} assertions, {len(verdicts['bit'])} changed verdict "
          f"under a poisoned or null input")
    print(f"  held green   {len(verdicts['held']):3d} — an assertion that cannot be made to fail "
          f"is vacuous, whatever its name says")
    print(f"  blocked      {len(verdicts['blocked']):3d} — the arm could not run, which is not a "
          f"pass either")
    print(f"  not armed    {len(NOT_ARMED):3d} populations, named below rather than left out")
    for what, why in NOT_ARMED:
        print(f"    {what} — {why}")
    print()

    if verdicts["held"] or verdicts["blocked"]:
        for arm, detail in verdicts["held"]:
            print(f"  {arm.ident}: stayed green under {arm.kind} input. {arm.why}")
        for arm, detail in verdicts["blocked"]:
            print(f"  {arm.ident}: could not run. {detail}")
        return 1 if verdicts["held"] else 2

    print("armed — every assertion in the population changed verdict under input built to break "
          "it.")
    print("A bite proves an assertion is not vacuous. It does not prove it reads the quantity in "
          "its name:")
    print("instances 2, 3, 7 and the egress one in G4's table all bite here and are still "
          "misaimed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
