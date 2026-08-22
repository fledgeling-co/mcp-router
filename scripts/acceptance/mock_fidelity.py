#!/usr/bin/env python3
"""The layer engine behind `mock-fidelity-gate.sh` — M23's conversion gate.

Three exit states, from the M23 brief:

    0   clean and complete — every required layer ran and found nothing
    1   findings — at least one difference
    3   inconclusive — a layer the verdict depended on could not run

The third one is the reason this is not two nested `diff`s. A property the measurement cannot
compute reads as agreement on both sides and a differ emits nothing, so every layer here declares a
**preflight**: what artifact it needs, and the floor below which that artifact is evidence of
nothing. A missing file, an empty file, a parse failure and a below-floor artifact are all exit 3,
with the tool's own words quoted rather than paraphrased.

Reading order for anyone extending this: `LAYERS` is the whole contract, one function per layer.
"""
from __future__ import annotations

import contextlib
import json
import os
import subprocess
import sys
import traceback
import unicodedata
from dataclasses import dataclass, field

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))

# The one layer this gate may ship with `required: false`, and the only one.
#
# `required: false` is otherwise a silence switch: a runner who needs a green gate marks `structure`
# optional, cites the manifest, and the verdict becomes "the layers that were left on". So the
# allowlist lives in the gate rather than in the manifest the gate reads, and a manifest that marks
# anything else optional is itself inconclusive.
ALLOWED_OPTIONAL = {"font-weight-face"}

# Which build (role, kind) may answer which mock affordance kind.
#
# `PRESENT` is earned by measuring, and the measurement behind "these two are the same control" is
# this table: the role and structural kind the running view reported, against the kind the mock's
# census derived. Without it the status came from the label alone, so a mock `card` answered by a
# `skeleton` read `present` on the strength of neither side carrying a string — agreement between
# two absences, which is the brief's "two controls doing the same job are not a match" exactly.
#
# Every pairing is listed, including the ones where the two words happen to agree. An earlier draft
# let a build role that SPELLED the mock kind vouch for itself, and the out-of-family review
# (grok-4.6, finding 2) was right that this is a name collision rather than a measurement: it skips
# the structural kind the table exists to constrain, and a build that renames `skeleton` to `card`
# earns its own pass with no table edit. Extending the list is a deliberate, reviewable act — the
# same reason `ALLOWED_OPTIONAL` lives in the gate rather than in the manifest the gate reads.
#
# What is deliberately absent is as load-bearing as what is present. `button` does not list
# `state-action-disabled`: the mock draws `Start the router` as `btn primary lg` with no disabled
# attribute, so a build that answers it with a disabled control has changed the control, and that
# is a finding for M17 to own rather than a spelling this gate waves through. Nor does `card` list
# `skeleton`.
#
# It covers the six mock kinds the one filled ledger pairs. The other eleven the census can derive
# have no entry, so the first surface to pair one reads it as a finding until the pairing is
# vouched — `D-m23-h` in ORCHESTRATOR.md's deferred register.
# M19 ADDED EIGHT PAIRINGS AND REMOVED NONE, which is the case `D-m23-h` names: a pairing this table
# has never seen reads `unclassified` until somebody adds it deliberately, and every addition
# therefore weakens this gate by one classification. Three of the eight are keys the table did not
# hold — `badge`, `callout`, `codeblock` — and five sit under keys it already had. All eight, as
# mock-kind <- (build-role, structural-kind): badge<-(badge, hstack), button<-(tab, leaf),
# callout<-(callout, hstack), codeblock<-(codeblock, scroll), heading<-(heading, text),
# icon<-(verified-mark, leaf), row<-(list-item, hstack), sentence<-(sentence, text). Measured by
# ast.literal_eval of this dict at 87e16dc and here, flattened to pairs: 11 before, 19 after.
#
# They are a document's own vocabulary — a heading answered by a heading, a `<li>` by a list item, a
# `<pre>` by a scrolling code block, a `<blockquote>` by a quote, a `<span class="shield">` by the
# badge the app re-draws from it, and the sheet's tabs by the buttons that do the same job. Each is
# a mock kind and a build role that genuinely do the same job, and none of them lets a build role
# vouch for itself by spelling the mock's kind — `heading`/`heading` is listed because the ROLE and
# the structural KIND together are what the table constrains, and a `heading` that reported itself
# an `hstack` still reads unclassified.
#
# This said "the first surface to pair five of the eleven" until M19's gap-fix. Five is the number
# of EXISTING KEYS that gained a pairing, which is a real quantity attached to the wrong noun, and
# the enumeration under it named `<th>` by a column header — a pairing that was already here and is
# not one of M19's additions.
VOUCHED_CONTROLS: dict[str, set[tuple[str, str]]] = {
    "heading": {("board-title", "text"), ("state-title", "text"), ("heading", "text")},
    "sentence": {("board-subtitle", "text"), ("state-detail", "text"), ("sentence", "text")},
    "button": {("primary-action", "leaf"), ("state-action", "leaf"), ("tab", "leaf")},
    "card": {("table", "vstack")},
    "icon": {("state-illustration", "leaf"), ("verified-mark", "leaf")},
    "row": {("table-row", "hstack"), ("list-item", "hstack")},
    "column-header": {("column-header", "text")},
    "skeleton-row": {("skeleton-row", "hstack")},
    "badge": {("badge", "hstack")},
    "codeblock": {("codeblock", "scroll")},
    "callout": {("callout", "hstack")},
}

# The same table read backwards: which mock kinds a build role may be answering. It is what lets the
# breadth layer ask whether the mock's census reaches a build node's granularity at all, rather than
# inferring it from whether some sibling happened to get paired.
MOCK_KINDS_FOR_ROLE: dict[str, set[str]] = {}
for _kind, _pairs in VOUCHED_CONTROLS.items():
    for _role, _ in _pairs:
        MOCK_KINDS_FOR_ROLE.setdefault(_role, set()).add(_kind)


def vouched_pairing(affordance_kind: str, node: dict) -> bool:
    """Has this gate ever established that this build control answers this mock kind?

    One definition, because it was two. `layer_breadth` asked this question and `layer_copy` did
    not, so the same pairing read `unclassified — a pairing this gate has never vouched for` in the
    breadth table and produced a stated, measured label difference in the copy layer three lines
    below it, on the same run (`D-m23-s`). Whichever layer is right, they cannot both be, and the
    only way two readers of one structure stay in agreement is for the test to exist once.
    """
    return (node["role"], node["kind"]) in VOUCHED_CONTROLS.get(affordance_kind, set())


@dataclass
class Layer:
    name: str
    findings: list[str] = field(default_factory=list)
    #: Reported on every run, and not a finding. A pending token row is the case this exists for:
    #: the row is a recorded, cited difference that another item owns, so making it a finding would
    #: pin the gate at exit 1 for a reason the surface under audit cannot fix — and dropping it
    #: would hide it. Printed either way, so the substitution stays visible rather than forgotten.
    carried: list[str] = field(default_factory=list)
    inconclusive: str | None = None
    ran: bool = False
    observations: int = 0
    note: str = ""


#: What `mock-fidelity-gate.sh` reads to decide whether to claim a ledger was written. An mtime is
#: not an ownership token — a stale ledger with a future timestamp, or a concurrent run writing the
#: same path, both satisfy `-nt` (`gpt-5.6-sol`) — so the claim comes from the process that did the
#: writing. It goes out through `emit`, so a console that cannot encode the report still delivers it
#: on stderr. If both streams are gone the script under-claims, which is the safe direction.
REPORT_MARKER = "mock-fidelity: report written to "


class Inconclusive(Exception):
    """Raised by a layer that could not run. The message is quoted into the report verbatim."""


@dataclass
class Run:
    """What the boundary around the whole run needs to know to write the run's own obituary.

    `gate()` fills these in as it learns them, so a failure at any point can still name the surface
    and replace the ledger. `report_written` is the one that stops the cure being worse than the
    disease: once a real table is on disk, a later failure must not overwrite it with "this run did
    not produce a table", because by then the run DID produce one.
    """
    report_path: str | None = None
    surface: str = "unknown"
    report_written: bool = False


def emit(text: str) -> bool:
    """Print, and say whether stdout took it.

    Every `print` in this file writes to a destination this process does not own. It can be a
    console that cannot encode what is being printed — `PYTHONIOENCODING=ascii` chokes on the `·`
    in the very first layer line — or a pipe whose reader has gone. Both raise, and the reporting
    of a failure is the one place that must not fail, so this falls back to stderr and reports
    which stream took the text.
    """
    try:
        print(text)
        sys.stdout.flush()
        return True
    except Exception:
        try:
            sys.stderr.write(text + "\n")
            sys.stderr.flush()
        except Exception:
            pass
        return False


def hush_streams() -> None:
    """Point stdout and stderr at /dev/null so the interpreter's shutdown flush has somewhere to go.

    CPython flushes `sys.stdout` after `main()` has returned, which is outside every boundary in
    this file. A `print` to a pipe whose reader exited does not raise at the print — the text sits
    in the buffer under the 64 KB pipe limit — so the failure surfaces at that shutdown flush, the
    interpreter prints `Exception ignored ... BrokenPipeError`, and the process exits **120**. That
    is not one of this gate's three exits, and `mock-fidelity-gate.sh` passes it straight through
    as though it were a verdict. Redirecting the descriptor is the documented way out: the buffered
    bytes go to /dev/null and the exit code this file computed is the one the caller sees.

    Both streams. This file writes its two usage messages and `emit`'s fallback to stderr, and
    `2> >(:)` takes a two-line script to 120 in three runs of three — so does `> >(:) 2>&1`, which
    is the ordinary spelling of the `| head` route. Covering stdout alone would be this property
    fixed at the site the finding named, one more time (`gemini-3.7-flash-high`, `grok-4.6`).
    """
    try:
        devnull = os.open(os.devnull, os.O_WRONLY)
        for stream in (sys.stdout, sys.stderr):
            try:
                os.dup2(devnull, stream.fileno())
            except Exception:
                continue
        os.close(devnull)
    except Exception:
        pass


@contextlib.contextmanager
def measuring(what: str):
    """Everything raised inside becomes `Inconclusive`, with the traceback quoted.

    The gate's doctrine is that a layer which measured nothing must read as inconclusive rather
    than as findings, and the first version of that fix converted the three failures somebody had
    thought of — a subprocess that hung, one that would not launch, a marker that would not parse.
    Every other way out of a layer still escaped `main` as an uncaught exception, which exits 1,
    the code that means differences were found, *before* the report is written. So the stale
    committed ledger stayed on disk under an exit that reads as a measured verdict — the same
    failure the earlier fix was written to end, arriving through a door nobody had listed.

    Listing more doors does not close it, because the list is not the thing: a `KeyError` on a
    hand-authored manifest, a `TypeError` on a floor somebody quoted as a string, an
    `IndexError` on a malformed argument and a `UnicodeDecodeError` on a pairing file are all the
    same event, which is that the verdict does not exist. So the boundary is the class. Anything
    that is not a finding and not a clean run is exit 3.

    `Inconclusive` passes through unchanged so a layer's own carefully worded reason is not buried
    under a traceback. `KeyboardInterrupt` and `SystemExit` derive from `BaseException` and are
    deliberately not caught: an operator pressing ^C is not an unmeasurable surface.
    """
    try:
        yield
    except Inconclusive:
        raise
    except Exception as error:
        raise Inconclusive(
            f"{what}: {type(error).__name__}: {error}\n"
            f"            Nothing this covers was measured. The gate raised, rather than "
            f"returning a verdict:\n"
            + "\n".join("            " + line for line in traceback.format_exc().rstrip().splitlines())
        ) from error


def run(cmd: list[str], cwd: str = ROOT, timeout: int = 900) -> subprocess.CompletedProcess:
    """Shell out, and fail to `Inconclusive` rather than out of the process.

    A layer that shells out has two ways to measure nothing, and neither of them is a finding: the
    tool can hang until the alarm goes off, and it can fail to launch at all. Both used to escape
    `main` as an uncaught exception, which exits 1 — the code that means "differences were found" —
    before `write_report` runs, so the stale ledger already on disk sat beside an exit that read as
    a measured verdict. That is the gate's own doctrine violated inside the gate.
    """
    try:
        return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired as error:
        raise Inconclusive(
            f"{os.path.basename(cmd[0])} did not finish inside {timeout}s, so whatever it was asked "
            f"to measure was never measured: {' '.join(cmd)}"
        ) from error
    except UnicodeDecodeError as error:
        raise Inconclusive(
            f"{os.path.basename(cmd[0])} wrote bytes that are not text, so its output was never "
            f"read: {error}"
        ) from error
    except OSError as error:
        raise Inconclusive(f"could not run {' '.join(cmd)}: {error}") from error


# --------------------------------------------------------------------------- artifacts

def load_json(path: str, what: str) -> dict:
    if not os.path.exists(path):
        raise Inconclusive(f"{what}: no artifact at {path} — the layer read nothing")
    if os.path.getsize(path) == 0:
        raise Inconclusive(f"{what}: {path} is zero bytes — an empty artifact is not a clean one")
    try:
        with open(path, encoding="utf-8") as handle:
            return json.load(handle)
    except json.JSONDecodeError as error:
        raise Inconclusive(f"{what}: {path} did not parse: {error}") from error


# Categories whose codepoints put no mark on the screen: control, format, surrogate, private-use,
# unassigned, the three separator classes, and the three combining-mark classes. The marks are here
# for a narrower reason than the rest: a combining mark draws on the base character in front of it,
# so removing them cannot hide content — `readable("e\u0301")` still keeps the `e` — while a string
# that is nothing BUT marks, U+034F COMBINING GRAPHEME JOINER being the usual one, has no base to
# draw on and puts nothing on the screen.
INVISIBLE_CATEGORIES = {"Cc", "Cf", "Cs", "Co", "Cn", "Zs", "Zl", "Zp", "Mn", "Me", "Mc"}

# Codepoints that put no mark on the screen from inside a *visible* category, so the category test
# above cannot reach them. The four Hangul fillers are `Lo` — letters — and exist to occupy a
# syllable position without drawing anything; U+2800 is a braille cell with no raised dots. There is
# no property in the database that says "renders blank", so this is a list rather than a class, and
# what is not on it is `D-m23-p`.
BLANK_CODEPOINTS = {"\u115f", "\u1160", "\u3164", "\uffa0", "\u2800"}


def readable(value: str | None) -> str:
    """What is left of a string once everything that renders as nothing is removed.

    `" ".join(text.split())` collapses the whitespace `str.split()` knows about, and that set is
    not the set of codepoints a person cannot see. `\xa0` is dropped; U+200B ZERO WIDTH SPACE,
    U+FEFF, U+00AD SOFT HYPHEN, U+2060 WORD JOINER and the directional marks all survive it, and
    all six are invisible. So `if mock_text and app_text` — truthiness — called a label of one
    zero-width space content, compared it against a build string of one zero-width space, found
    them equal and wrote `present`. That is the literal form of the "agreement between two
    absences" the four-outcome rule was written to end, one codepoint class over.

    Used for the question "is there anything here to compare", never for the comparison itself: two
    strings that differ only in an invisible codepoint are still different, and the equality test
    keeps reading the normalised text so it says so.

    Its limit, stated because a check that overclaims is the defect this pass exists to close. The
    category test is a class and catches every future addition to it; `BLANK_CODEPOINTS` is a list
    and catches only what is written on it, so a blank codepoint in a visible category that nobody
    has put there yet still reads as content. `D-m23-p` carries that residue. The two errors are not
    symmetric, which is why the list errs long: removing too much makes a real pairing read
    `unclassified`, a finding that names what was not measured, while removing too little makes two
    invisible strings read `present`, which is the false clean. That asymmetry is also the answer to
    `Co`: a private-use codepoint can carry a visible glyph in a bundled font, and filtering it
    anyway costs a finding rather than a false pass (`D-m23-u`).
    """
    return "".join(
        ch for ch in (value or "")
        if not ch.isspace()
        and ch not in BLANK_CODEPOINTS
        and unicodedata.category(ch) not in INVISIBLE_CATEGORIES
    )


def flatten(node: dict, path: list[str] | None = None) -> list[tuple[str, dict]]:
    path = (path or []) + [node["id"]]
    out = [("/".join(path), node)]
    for child in node.get("children", []):
        out.extend(flatten(child, path))
    return out


def index_nodes(root: dict, what: str) -> dict[str, dict]:
    """Nodes by path, refusing a tree in which a path names more than one node.

    `dict(flatten(root))` keeps the LAST node of any repeated path and says nothing about the
    others, so two siblings sharing an id make one of them invisible to every layer that indexes by
    path. That is `D-m23-m`, and it is this pass's property from the node side rather than the
    affordance side: the claimant test establishes that one control answers one affordance, and it
    rests on a pairing's node path naming one control. Where a path names two, `vouched_pairing`
    vouches for whichever node the dict kept, which is a measurement of something nobody chose.

    Raised from `derive_pairings`, which runs inside `Context.load`, so it fires before any layer.
    """
    flat = flatten(root)
    index = dict(flat)
    if len(index) != len(flat):
        seen: dict[str, int] = {}
        for path, _ in flat:
            seen[path] = seen.get(path, 0) + 1
        collisions = sorted(path for path, count in seen.items() if count > 1)
        raise Inconclusive(
            f"{what}: {len(flat) - len(index)} node(s) share a path with a sibling, so a pairing "
            f"naming one of those paths does not name a control: {', '.join(collisions[:5])}"
            + (" …" if len(collisions) > 5 else "")
        )
    return index


# --------------------------------------------------------------------------- layers

def layer_tokens(ctx) -> Layer:
    """The mock's two token blocks against the shipped Swift palette."""
    layer = Layer("tokens")
    result = run(["swift", "test", "--filter", "MockToken"], cwd=os.path.join(ROOT, "app"))
    output = result.stdout + result.stderr

    marker = next((l for l in output.splitlines() if l.startswith("MOCK-FIDELITY-TOKENS:")), None)
    if marker is None:
        raise Inconclusive(
            "tokens: the suite printed no MOCK-FIDELITY-TOKENS marker, so the register was never "
            "compared. A check that prints nothing cannot be told from one that did not run.\n"
            + "\n".join(output.splitlines()[-15:])
        )
    # The marker is a line of `name=value` fields, and a line that is not is a layer that read
    # nothing. It happens for a reason nobody planned: with MCP_ROUTER_WRITE_TOKEN_REGISTER=1 in the
    # environment the suite prints `MOCK-FIDELITY-TOKENS: register rewritten at <path>` and returns
    # before the census. Unguarded, `dict(part.split("=", 1) ...)` raises ValueError, python exits 1,
    # and `write_report` never runs — an unmeasured layer reported as findings, beside a stale
    # ledger. An unparseable marker is a layer that could not run, which is exit 3.
    try:
        fields = dict(part.split("=", 1) for part in marker.split(":", 1)[1].split())
        # Every field is read as the number it claims to be. `matched` used to be taken as a string
        # and printed into the ledger's note unexamined, so `matched=garbage` produced a census line
        # nobody could act on beside a layer reported as clean — the out-of-family review
        # (gpt-5.6-sol, finding 6) named it.
        rows, matched = int(fields["rows"]), int(fields["matched"])
        pending, uncited = int(fields["pending"]), int(fields["uncited"])
    except (ValueError, KeyError) as error:
        raise Inconclusive(
            "tokens: the MOCK-FIDELITY-TOKENS marker does not carry the name=value census fields, "
            f"so the register was never read ({error!r}). The suite printed, verbatim:\n"
            f"{marker}"
        ) from error
    # The census has to partition the number this layer reports as its population, because
    # `observations` is what the `tokenRows` floor and the layer-wide zero-observation guard both
    # read — and `rows` is a number the marker ASSERTS rather than one this gate derives. Until
    # this check existed, `rows=89 matched=0 pending=0` cleared a floor of 89 off a suite that
    # compared nothing, which is the same shape as the `structure` layer counting nodes it
    # enumerated instead of axes it corroborated (`D-m23-o`).
    if matched < 0 or pending < 0 or uncited < 0 or rows < 0:
        raise Inconclusive(
            f"tokens: the census is negative (rows={rows} matched={matched} pending={pending} "
            f"uncited={uncited}), so the register was never counted"
        )
    if matched + pending != rows:
        raise Inconclusive(
            f"tokens: the marker says {rows} rows and accounts for {matched} matched plus "
            f"{pending} pending, which is {matched + pending}. The census does not partition the "
            "population this layer reports, so what it measured is unknown."
        )
    if uncited > pending:
        raise Inconclusive(
            f"tokens: {uncited} rows are reported as pending-without-citation out of {pending} "
            "pending rows, so the two counts are not describing the same set"
        )
    layer.observations = rows
    layer.ran = True
    if layer.observations < ctx.floors["tokenRows"]:
        raise Inconclusive(
            f"tokens: the register carries {layer.observations} rows, below the floor of "
            f"{ctx.floors['tokenRows']}. A shrunken census raises coverage while measuring less — "
            "the failure `planning/evidence/P4-acceptance.md` records four times."
        )

    if result.returncode != 0:
        for line in output.splitlines():
            if "Expectation failed" in line or "recorded an issue" in line:
                layer.findings.append(f"token parity: {line.strip()[:200]}")
        if not layer.findings:
            layer.findings.append(f"token parity suite exited {result.returncode}")

    if uncited:
        layer.findings.append(f"{uncited} pending token rows carry no citation")
    for line in output.splitlines():
        if line.startswith("MOCK-FIDELITY-PENDING:"):
            layer.carried.append("token " + line.split(":", 1)[1].strip())
    layer.note = f"{matched} matched, {pending} pending, of {layer.observations} rows"

    stray = next((l for l in output.splitlines() if l.startswith("MOCK-FIDELITY-MOCK-LITERALS:")), None)
    if stray is None:
        raise Inconclusive("tokens: the mock's own zero-literals property was never measured")
    # The field is required to be NAMED, not merely to sit after the first `=`. Reading whatever
    # followed the `=` accepted `MOCK-FIDELITY-MOCK-LITERALS: unrelated=0` as a clean measurement of
    # a property nothing had measured (gpt-5.6-sol, finding 6).
    try:
        literal_fields = dict(part.split("=", 1) for part in stray.split(":", 1)[1].split())
        count = int(literal_fields["stray"])
    except (ValueError, KeyError) as error:
        raise Inconclusive(
            "tokens: the mock's zero-literals marker carries no `stray=` count, so the property was "
            f"never read ({error!r}). The suite printed, verbatim:\n{stray}"
        ) from error
    if count:
        layer.findings.append(f"the mock writes {count} colour literals outside its token blocks")
    return layer


def layer_literals(ctx) -> Layer:
    """No Swift file outside the palette type writes a colour literal."""
    layer = Layer("literals")
    script = os.path.join(ROOT, "scripts/lint/no-raw-design-values.sh")
    if not os.access(script, os.X_OK):
        raise Inconclusive(f"literals: {script} is missing or not executable")
    result = run(["/bin/bash", script])
    output = result.stdout + result.stderr
    scan = next((l for l in output.splitlines() if l.startswith("no-raw-design-values: scanning")), None)
    if scan is None:
        raise Inconclusive(
            "literals: the lint printed no scan line, so the number of files it read is unknown:\n"
            + output.strip()[-800:]
        )
    layer.ran = True
    try:
        # "no-raw-design-values: scanning 116 files". The count is read rather than assumed,
        # because a lint that scanned nothing and a lint that found nothing print the same exit
        # code — and a scan line this cannot parse is a lint whose population is unknown, which
        # is inconclusive rather than clean. The selftest found this crashing where it should
        # have reported, which is what a scratch stub with a different word order is for.
        layer.observations = int(scan.split("scanning", 1)[1].split()[0])
    except (IndexError, ValueError) as error:
        raise Inconclusive(
            f"literals: could not read the file count out of the lint's scan line, so the number "
            f"of files it read is unknown ({error}): {scan.strip()!r}"
        ) from error
    if layer.observations < ctx.floors["lintFiles"]:
        raise Inconclusive(
            f"literals: the lint scanned {layer.observations} files, below the floor of "
            f"{ctx.floors['lintFiles']}. This layer reads the scan count in the first place because "
            "a lint that scanned nothing and a lint that found nothing print the same exit code — "
            "and until this floor existed it read the number and compared it to nothing, so "
            "`scanning 0 files` reported `clean` and the gate exited 0. A count with no floor under "
            "it is the quantity in the name doing no work in the assertion "
            "(planning/features-to-triage/G4-assertions-that-do-not-read-their-own-quantity.md)."
        )
    layer.note = scan.split(": ", 1)[1]
    if result.returncode != 0:
        for line in output.splitlines():
            if "—" in line and ".swift:" in line:
                layer.findings.append("raw design value: " + line.strip())
        if not layer.findings:
            layer.findings.append(f"no-raw-design-values.sh exited {result.returncode}")
    return layer


def layer_structure(ctx) -> Layer:
    """Containment and axis, corroborated against the geometry rather than taken on trust.

    A `.measured(kind: .hstack)` annotation is metadata the view supplies about itself, and the M23
    brief's whole subject is that self-description is not measurement. So every declared axis is
    checked against where the children actually landed: a node calling itself horizontal whose
    children are stacked vertically is a finding, not a label.
    """
    layer = Layer("structure")
    # Two quantities, because this layer's floor and this layer's verdict are floors on different
    # things and reporting one number for both is the G4 defect
    # (planning/features-to-triage/G4-assertions-that-do-not-read-their-own-quantity.md).
    #
    # `nodes_seen` is the census: how much of the surface the harness instrumented at all, which is
    # what `dumpNodes` is a ratchet on and what "a surface with nothing instrumented diffs clean"
    # means. `layer.observations` is what this layer actually CORROBORATED: declared axes checked
    # against where the children landed and found to carry evidence either way. They were one number
    # until 2026-08-21, and `observations` was the census — so the layer-wide `observations == 0`
    # guard in `main()` read a quantity this layer never compares, and a dump with every `axis` key
    # removed made zero comparisons while printing the same `73 nodes across 4 states · clean` line
    # as a fully instrumented one. `axis` is `nil` wherever the kind does not stack, so a surface
    # that annotates its leaves and skips its containers is not hypothetical.
    nodes_seen = 0
    for state, dump in ctx.dumps.items():
        nodes = flatten(dump["root"])
        nodes_seen += len(nodes)
        for path, node in nodes:
            children = node.get("children", [])
            if len(children) < 2 or node.get("axis") not in ("horizontal", "vertical"):
                continue

            # The axis is read from whether the children SEPARATE along it, not from how far their
            # origins spread. The spread reading — which this replaced — called a centred VStack
            # horizontal whenever its two labels differed in width by more than they differed in
            # height, and reported it on a board where nothing was wrong. A detector whose false
            # positives outnumber its true ones is one people learn to scroll past.
            def disjoint(a, b, axis):
                lo, size = ("x", "width") if axis == "horizontal" else ("y", "height")
                first, second = sorted((a["frame"], b["frame"]), key=lambda f: f[lo])
                return first[lo] + first[size] <= second[lo] + 0.5

            pairs = [
                (children[i], children[j])
                for i in range(len(children)) for j in range(i + 1, len(children))
            ]
            across = sum(disjoint(a, b, "horizontal") for a, b in pairs)
            down = sum(disjoint(a, b, "vertical") for a, b in pairs)
            if across == down:
                continue  # overlapping or single-point children carry no axis evidence either way
            # Counted here rather than at the top of the loop, and this is the whole of the
            # distinction: a declared axis whose children overlap was LOOKED at and not measured,
            # so it is not an observation. Only a comparison that reached a verdict is.
            layer.observations += 1
            observed = "horizontal" if across > down else "vertical"
            if observed != node["axis"]:
                layer.findings.append(
                    f"{state}: {path} declares axis {node['axis']} but of its "
                    f"{len(pairs)} child pairs, {across} separate horizontally and {down} vertically"
                )
    layer.ran = True
    if nodes_seen < ctx.floors["dumpNodes"]:
        raise Inconclusive(
            f"structure: the {len(ctx.dumps)} dumps carry {nodes_seen} nodes, below the floor of "
            f"{ctx.floors['dumpNodes']} — a surface with nothing instrumented diffs clean"
        )
    layer.note = (
        f"{nodes_seen} nodes across {len(ctx.dumps)} states · {layer.observations} declared "
        "axis/axes corroborated against child geometry"
    )
    return layer


def layer_geometry(ctx) -> Layer:
    """Frames: present, non-degenerate, and inside the surface that was asked for."""
    layer = Layer("geometry")
    for state, dump in ctx.dumps.items():
        want = dump["size"]
        root = dump["root"]["frame"]
        if (root["width"], root["height"]) != (want["width"], want["height"]):
            layer.findings.append(
                f"{state}: the surface root measured {root['width']}x{root['height']} but was hosted "
                f"at {want['width']}x{want['height']}"
            )
        for path, node in flatten(dump["root"]):
            layer.observations += 1
            frame = node["frame"]
            if frame["width"] <= 0 or frame["height"] <= 0:
                layer.findings.append(f"{state}: {path} has a zero-area frame {frame}")
    layer.ran = True
    layer.note = f"{layer.observations} frames"
    return layer


def layer_type_metrics(ctx) -> Layer:
    """What a text node's measured line box says about the type role it names.

    This is the part of the font layer that CAN be measured, and it is deliberately narrower than
    the check it replaced. That one asserted a text node's height was a whole multiple of the line
    height its `TypeToken` declares, and reported nine findings on a board with no type defect in
    it: `DESIGN.md`'s line heights are the design's leading, not the box AppKit lays a single line
    of SF Pro out in, and a button's frame is a control height rather than a line box at all. Every
    one of those nine was the instrument, and a layer that cries wolf is a layer nobody reads.

    What survives is two properties that hold whatever the renderer's leading turns out to be:

    1. **Every single-line node naming one role measures the same height.** This is what a lost
       cascade looks like — an ancestor `.font()` winning on some of a role's nodes and not others
       — which is the exact residue the `font-weight-face` layer cannot see.
    2. **The measured heights rise with the ladder.** A node whose role was substituted for a
       neighbouring one on the ladder shows up as an inversion.

    Multi-line nodes are excluded from (1), because their height is a wrap count rather than a line
    box, and the count of them is reported rather than dropped.
    """
    layer = Layer("type-metrics")
    ladder = None
    heights: dict[str, list[tuple[str, float]]] = {}
    multiline = 0
    # The same split `layer_structure` now carries, and for the same reason. `typed_nodes` is how
    # many text nodes named a role at all — the eligibility census. `layer.observations` is how many
    # of them the per-role height check actually ruled on, which is the census minus the multi-line
    # nodes it excludes with a `continue`. Both `gpt-5.6-sol` and `grok-4.6` reached this
    # independently against the diff that listed this layer as already agreeing: 24 nodes reported,
    # 2 excluded, 22 compared. The zero-guard cannot be fooled here the way it could in `structure`,
    # because `floor = min(...)` keeps at least one node per role — but the number the guard and the
    # note both read was still not the number of comparisons.
    typed_nodes = 0

    for state, dump in ctx.dumps.items():
        ladder = dump.get("typeLadder") or ladder
        if not ladder:
            raise Inconclusive(f"type-metrics: {state} carries no type ladder, so nothing to check against")
        for path, node in flatten(dump["root"]):
            role = node.get("tokens", {}).get("type")
            if not role:
                continue
            if role not in ladder:
                layer.findings.append(f"{state}: {path} names type role '{role}', which is not on the ladder")
                continue
            if node["kind"] != "text":
                continue  # a control's frame is a control height, not a line box
            typed_nodes += 1
            heights.setdefault(role, []).append((f"{state}: {path}", node["frame"]["height"]))

    if typed_nodes == 0:
        raise Inconclusive("type-metrics: no instrumented text node named a type role, so nothing was measured")

    single: dict[str, float] = {}
    for role, seen in heights.items():
        floor = min(height for _, height in seen)
        single[role] = floor
        for where, height in seen:
            if height > floor + 0.5:
                if height > floor * 1.5:
                    multiline += 1
                    continue  # a wrap count is not a line box, so this one was not compared
                layer.findings.append(
                    f"{where} names {role} and measured {height}pt, where every other single-line "
                    f"{role} node measured {floor}pt — one of the two lost the cascade"
                )
            # Last in the body, so the `continue` above keeps an excluded node out of the count.
            layer.observations += 1

    ordered = sorted(single, key=lambda role: (ladder[role]["size"], role))
    for smaller, larger in zip(ordered, ordered[1:]):
        if ladder[smaller]["size"] == ladder[larger]["size"]:
            continue
        if single[smaller] > single[larger]:
            layer.findings.append(
                f"{smaller} ({ladder[smaller]['size']}pt on the ladder) measured {single[smaller]}pt "
                f"but {larger} ({ladder[larger]['size']}pt) measured {single[larger]}pt — the "
                "measured heights invert the ladder, which is what a substituted role looks like"
            )

    if len(single) < 2:
        raise Inconclusive(
            f"type-metrics: only {len(single)} type role(s) appear across the instrumented nodes, "
            "so neither the per-role agreement nor the ladder ordering has anything to compare"
        )

    layer.ran = True
    layer.note = (
        f"{layer.observations} per-role comparison(s) over {typed_nodes} text nodes · "
        f"{len(single)} roles · "
        + " ".join(f"{role}={single[role]}pt" for role in ordered)
        + (f" · {multiline} multi-line node(s) excluded from the per-role check" if multiline else "")
    )
    return layer


def layer_copy(ctx) -> Layer:
    """The mock's text nodes against the strings the running views reported.

    Against the **dump**, not the copy enums. Reading an enum tells you what a view declares, which
    is the first self-deception the brief names: it cannot see a string that never rendered, a state
    the data left empty, or a view that was never reached.
    """
    layer = Layer("copy")
    # `ctx.comparable`, not `ctx.pairs`. The population of this layer is the pairings the gate has
    # established are the same control and that exactly one affordance names — the same two tests
    # the breadth layer's status turns on, applied here because they are properties of the pairing
    # rather than of whichever layer happens to be reading it.
    #
    # Reading `ctx.pairs` directly is what let this layer state a measured difference between two
    # labels while the breadth table, on the same run, recorded that it could not establish the two
    # sides were the same control (`D-m23-s`). The number moved and the verdict did not: 20 paired
    # strings became 19, and all 16 findings survive, because the pairing this drops carries no
    # copy difference. A finding removed here would have been a difference between a mock string
    # and a build string that were never shown to belong to the same control.
    for state, comparable in ctx.comparable.items():
        nodes = index_nodes(ctx.dumps[state]["root"], f"dump[{state}]")
        by_id = {a["id"]: a for a in ctx.inventory[state]["affordances"]}
        for affordance_id, node_path in comparable.items():
            affordance = by_id.get(affordance_id)
            node = nodes.get(node_path)
            if affordance is None or node is None:
                continue  # reported by the breadth layer, which owns pairing integrity
            mock_text = " ".join((affordance.get("label") or "").split())
            app_text = " ".join((node.get("text") or "").split())
            # Readable content, not truthiness — the same test the breadth layer makes, for the same
            # reason. Two strings of one zero-width space each are truthy, compare equal, and would
            # be counted here as a paired string that agreed.
            if not readable(mock_text) or not readable(app_text):
                continue
            layer.observations += 1
            if mock_text != app_text:
                layer.findings.append(
                    f"{state}: {affordance_id} reads \"{mock_text[:70]}\" in the mock and "
                    f"\"{app_text[:70]}\" in the build"
                )
    layer.ran = True
    layer.note = f"{layer.observations} paired strings"
    return layer


def layer_breadth(ctx) -> Layer:
    """Present / divergent / absent for every affordance the mock draws, both directions.

    The inventory is derived from the mock on every run, so a row cannot be deleted to make a
    finding disappear — the P4 failure. The pairing file declares only *which* node answers which
    affordance; the status is computed here, which is what makes `present` earned by measuring
    rather than asserted.
    """
    layer = Layer("breadth")
    rows = []
    for state in ctx.states:
        inventory = ctx.inventory[state]["affordances"]
        nodes = index_nodes(ctx.dumps[state]["root"], f"dump[{state}]")
        pairs = ctx.pairs.get(state, {})
        paired_nodes = set()

        # Which affordances name each build node, before any of them is classified.
        #
        # `ctx.pairs[state]` is keyed by affordance, so it will happily let every affordance in the
        # mock name one build control, and nothing checked. Two mock headings pointed at one build
        # control produced TWO `present` rows: the second was a measurement of the first control,
        # credited to a second affordance that was never measured at all. It is the original G1
        # again — a `present` not earned by measuring that control — and it does not fire on today's
        # ledger only because no absent affordance happens to share a label with a vouched node.
        # 80 of this surface's rows are `absent`, and those labels start matching exactly as M16
        # converts the board, so the defect activates when someone is working toward exit 0.
        #
        # Counted first rather than as the loop goes, because order is not evidence: if a pairing is
        # ambiguous then neither claimant was measured, and letting whichever came first keep
        # `present` would pick a winner by inventory position.
        #
        # Both this and the vouched test now live in `Context.derive_pairings`, and this layer reads
        # what that produced rather than computing its own copy. The copy layer reads the same
        # thing, which is the point: a test written into one reader of `ctx.pairs` holds for that
        # reader, and there are two of them.
        claims = ctx.claims[state]
        comparable = ctx.comparable.get(state, {})

        for affordance in inventory:
            layer.observations += 1
            node_path = pairs.get(affordance["id"])
            if node_path is None:
                rows.append((state, affordance["id"], affordance["kind"], "absent",
                             f'mock="{affordance["label"][:60]}"', "build=no paired node",
                             ctx.citations.get(affordance["id"], "")))
                layer.findings.append(f"{state}: {affordance['id']} is absent from the build")
                continue
            node = nodes.get(node_path)
            if node is None:
                rows.append((state, affordance["id"], affordance["kind"], "unclassified",
                             f'mock="{affordance["label"][:60]}"',
                             f"build=pairing names {node_path}, which is not in the dump", ""))
                layer.findings.append(
                    f"{state}: {affordance['id']} is paired to {node_path}, which no dump node matches"
                )
                continue
            paired_nodes.add(node_path)
            mock_text = " ".join((affordance.get("label") or "").split())
            app_text = " ".join((node.get("text") or "").split())

            # The control kind, before the label. The brief asks for a pair to be audited on
            # label, control kind and glyph, and a status computed from the label alone reads a
            # mock `card` answered by a build `skeleton` as agreement because neither carries a
            # string. So `affordance["kind"]` — which used to be written into the ledger and never
            # compared to anything — is checked against the role and kind the view reported.
            #
            # The glyph is the third of those three and stays unread: the harness records no glyph
            # identity for an icon node, so an icon pair has nothing to compare and lands as
            # `unclassified` rather than as agreement. That is the honest outcome, not the audited
            # one.
            vouched = vouched_pairing(affordance["kind"], node)

            # Four outcomes, not two, and only one of them is a claim that a measurement happened.
            #
            # `present` requires this affordance to be the only one naming this control, the pairing
            # to be one the gate has vouched for, and two strings with something readable in them
            # that agree. Everything else is `unclassified`: a comparison the instrument could not
            # make, which is a finding naming what it could not read.
            #
            # `divergent` is reserved for a difference that was actually measured. It used to carry
            # the unvouched case too, which claims a measured difference where the truth is that the
            # gate has never established the two are the same control — the coordinator's own
            # correction, `D-m23-l`. That matters ahead of when it bites: the nine mock kinds
            # `VOUCHED_CONTROLS` does not name (`D-m23-h`) will each land here, and a correct build
            # would have read `divergent`.
            # Counted rather than filtered by id. `[o for o in claimants if o != my_id]` looks
            # like the same test and is not: two inventory entries sharing an id both name this
            # node, the comprehension removes both occurrences, `others` is empty and each row
            # earns `present` off one measurement — the original defect, reached through the
            # duplicate rather than through the pairing. The number of claimants is the quantity
            # the check is named for, so it reads that number.
            claimants = claims.get(node_path, [])
            # Whether the two sides may be compared at all is `ctx.comparable`'s answer, not this
            # layer's — one derived set, so this table and the copy layer's findings cannot
            # contradict each other about the same pairing. `claimants` and `vouched` are read
            # below only to say WHICH of the two tests it failed, because a reader who fixes a
            # collision should not then discover an unvouched pairing waiting behind it
            # (`D-m23-t`).
            if comparable.get(affordance["id"]) != node_path:
                status = "unclassified"
            elif readable(mock_text) and readable(app_text):
                status = "present" if mock_text == app_text else "divergent"
            else:
                status = "unclassified"

            rows.append((state, affordance["id"], affordance["kind"], status,
                         f'mock="{mock_text[:60]}" kind={affordance["kind"]}',
                         f'build={node_path} text="{app_text[:60]}" '
                         f'role={node["role"]} kind={node["kind"]}',
                         ctx.citations.get(affordance["id"], "")))
            if len(claimants) > 1:
                layer.findings.append(
                    f"{state}: {affordance['id']} is paired to {node_path}, which "
                    f"{len(claimants)} affordances name in total ({', '.join(sorted(claimants))}). "
                    "One build control cannot answer several mock affordances, so whichever of them "
                    "it does answer, the rest were never measured"
                )
            elif not vouched:
                layer.findings.append(
                    f"{state}: {affordance['id']} is a mock {affordance['kind']} answered by "
                    f"{node_path}, which reports role '{node['role']}' and kind '{node['kind']}' — "
                    "a pairing this gate has never vouched for, so whether the two are the same "
                    "control was never established"
                )
            elif status == "divergent":
                layer.findings.append(
                    f"{state}: {affordance['id']} label differs — mock \"{mock_text[:50]}\" vs "
                    f"build \"{app_text[:50]}\""
                )
            elif status == "unclassified":
                mock_seen, app_seen = readable(mock_text), readable(app_text)
                if not mock_seen and not app_seen:
                    invisible = "" if not (mock_text or app_text) else (
                        " — both sides carry codepoints that render as nothing")
                    layer.findings.append(
                        f"{state}: {affordance['id']} is paired to {node_path} and neither side "
                        f"carries a readable string, so nothing was compared{invisible}. Agreement "
                        "between two absences is not a measurement"
                    )
                else:
                    side = ("the build node reports nothing readable" if mock_seen
                            else "the mock affordance carries no readable label")
                    layer.findings.append(
                        f"{state}: {affordance['id']} is paired to {node_path} but {side}, so the "
                        "label was never compared"
                    )

        # The reverse direction. Matching the mock means removing what it does not have, not only
        # adding what it lacks, so an instrumented node nothing in the mock accounts for is a
        # finding of its own.
        #
        # With one mechanical exemption, and it is stated here rather than spent as a per-row
        # citation: **a node with a paired node somewhere in its subtree is containment, not an
        # extra element.** The mock's census covers the declared affordance kinds — heading,
        # button, card, row, field and the rest — and never a bare wrapper, so a build container
        # whose whole job is to carry an axis and a frame for children the mock does account for
        # has nothing on the mock side to pair with. Those are counted and listed as
        # `structure-unpaired` so the number is visible. A subtree with nothing paired anywhere
        # inside it is not exempt: it goes red at its root and at every leaf, which is what an
        # invented section looks like.
        #
        # The exemption is a QUOTA rather than a blanket, and that is the whole of the difference.
        # Where the mock's census reaches a granularity — where it names affordances of a kind this
        # build role is allowed to answer — the mock has said how many there are, and a build node
        # of that role which answers none of them is an uncounted invention. The loading state is
        # the case this exists for: the mock draws three skeleton rows, the build draws four, and
        # under a blanket exemption the fourth was classified `covered-by-pair` and produced no
        # finding at all. Extra elements are divergent too.
        #
        # The question is asked of the MOCK's inventory, not of how many siblings happened to get
        # paired. An earlier draft used pairing success as the quota, and the out-of-family review
        # (grok-4.6, finding 3) was right on both counts: it left the original hole reachable
        # whenever none of the same-role children were paired, and its finding text said "the mock
        # accounts for N" about a number that was pairing success rather than census length.
        def subtree_has_pair(path: str) -> bool:
            prefix = path + "/"
            return any(p.startswith(prefix) for p in paired_nodes)

        def nearest_pair(path: str) -> str | None:
            """The paired node this one sits inside, innermost first, or None."""
            owners = [p for p in paired_nodes if path.startswith(p + "/")]
            return max(owners, key=len) if owners else None

        # (paired ancestor, build role) -> every node under it carrying that role, and how many of
        # them answer an affordance. Both numbers are quoted in the finding.
        kin: dict[tuple[str, str], list[str]] = {}
        for path, node in nodes.items():
            owner = nearest_pair(path)
            if owner is not None:
                kin.setdefault((owner, node["role"]), []).append(path)

        # How many affordances of each kind the mock's census names for this state.
        census: dict[str, int] = {}
        for affordance in inventory:
            census[affordance["kind"]] = census.get(affordance["kind"], 0) + 1

        for path, node in nodes.items():
            if path in paired_nodes or node["role"] == "surface":
                continue
            # A descendant of a paired node is accounted for by that pair ONLY where the mock's
            # census never reached that granularity: the mock names the row, and the row's label IS
            # its subtree's text, so reporting the row's own name and state lines as "in the build
            # and not in the mock" states something false about the mock. What is inside such a
            # pair is compared by the copy, geometry and type-metrics layers instead.
            #
            # Where the census DID reach it, the exemption becomes a count, and anything past the
            # count is an uncounted invention rather than containment.
            owner = nearest_pair(path)
            if owner is not None:
                answerable = sorted(MOCK_KINDS_FOR_ROLE.get(node["role"], set()))
                declared = sum(census.get(kind, 0) for kind in answerable)
                if declared == 0:
                    rows.append((state, path, node["role"], "covered-by-pair",
                                 "mock=inside a paired affordance, at a granularity the mock's "
                                 "census does not reach", f"build={path}", ""))
                    continue
                siblings = kin.get((owner, node["role"]), [])
                answered = sum(1 for p in siblings if p in paired_nodes)
                surplus = (
                    f"role '{node['role']}' answers mock kind(s) {', '.join(answerable)}, of which "
                    f"the mock's census for this state names {declared}; {answered} of the "
                    f"{len(siblings)} node(s) of that role under {owner} answer one, and this one "
                    "answers none"
                )
                citation = ctx.extra_allowed.get(state, {}).get(path)
                rows.append((state, path, node["role"], "extra-cited" if citation else "extra",
                             f"mock={surplus}", f"build={path}", citation or ""))
                layer.findings.append(
                    f"{state}: {path} is in the build and not in the mock — {surplus}"
                    + (f" ({citation})" if citation else "")
                )
                continue
            if node.get("children") and subtree_has_pair(path):
                rows.append((state, path, node["role"], "structure-unpaired", "mock=no affordance of a declared kind",
                             f"build={path} ({len(node['children'])} children, at least one paired)", ""))
                continue
            if path in ctx.extra_allowed.get(state, {}):
                rows.append((state, path, node["role"], "extra-cited", "mock=nothing",
                             f"build={path}", ctx.extra_allowed[state][path]))
                layer.findings.append(
                    f"{state}: {path} is in the build and not in the mock "
                    f"({ctx.extra_allowed[state][path]})"
                )
                continue
            rows.append((state, path, node["role"], "extra", "mock=nothing", f"build={path}", ""))
            layer.findings.append(f"{state}: {path} is in the build and not in the mock")

    layer.ran = True
    if layer.observations < ctx.floors["affordances"]:
        raise Inconclusive(
            f"breadth: the derived inventory carries {layer.observations} affordances, below the "
            f"floor of {ctx.floors['affordances']}. A shrunken denominator is how coverage goes up "
            "while measurement goes down (planning/evidence/P4-acceptance.md)."
        )
    ctx.breadth_rows = rows
    counts = {}
    for row in rows:
        counts[row[3]] = counts.get(row[3], 0) + 1
    layer.note = " · ".join(f"{k} {v}" for k, v in sorted(counts.items()))
    return layer


def layer_font_weight_face(ctx) -> Layer:
    """The residue the instrument genuinely cannot read: weight and face."""
    layer = Layer("font-weight-face")
    evidence = None
    for dump in ctx.dumps.values():
        for entry in dump.get("inconclusive", []):
            if entry["layer"] == "resolved-font":
                evidence = entry
    if evidence is None:
        raise Inconclusive(
            "font-weight-face: the dump carries no capability record for the font layer, so whether "
            "it ran is unknown"
        )
    raise Inconclusive(
        "font-weight-face: " + evidence["evidence"]
        + "\n            confirmed instead by: " + (evidence.get("confirmedInsteadBy") or "nothing")
    )


LAYERS = {
    "tokens": layer_tokens,
    "literals": layer_literals,
    "structure": layer_structure,
    "geometry": layer_geometry,
    "type-metrics": layer_type_metrics,
    "copy": layer_copy,
    "breadth": layer_breadth,
    "font-weight-face": layer_font_weight_face,
}

# The order the layers run and print in. Kept beside the table it has to agree with, and checked
# against it in `main()` rather than trusted.
LAYER_ORDER = ["tokens", "literals", "structure", "geometry", "type-metrics", "copy", "breadth",
               "font-weight-face"]


# --------------------------------------------------------------------------- driver

class Context:
    def __init__(self, manifest: dict, dump_dir: str):
        self.manifest = manifest
        self.surface = manifest["surface"]
        self.states = manifest["states"]
        self.floors = manifest["floors"]
        # A floor of zero is not a floor. Every `observations < ctx.floors[...]` test in this file
        # reads the census a layer measured and compares it to a number from the manifest — and
        # `0 < 0` is false, so `"lintFiles": 0` restores exactly the defect the floor was added to
        # close: the lint scans nothing, the layer reads `clean`, the gate exits 0. The comparison
        # cannot catch that, because the comparison is the thing being defeated. So the floor itself
        # is checked once here rather than at each of the four sites. `bool` is excluded explicitly
        # because `isinstance(True, int)` is true in Python and `observations < True` is a floor of
        # one wearing the wrong type.
        for floor_name, floor_value in sorted(self.floors.items()):
            if isinstance(floor_value, bool) or not isinstance(floor_value, int) or floor_value < 1:
                raise Inconclusive(
                    f"manifest: floor '{floor_name}' is {floor_value!r}. A floor is the smallest "
                    "census a layer may measure and still be believed, so it has to be a positive "
                    "whole number. At zero or below, the `observations < floor` test is false for a "
                    "layer that measured nothing, which is the one case the floor exists to catch."
                )
        self.section = manifest["section"]
        self.dump_dir = dump_dir
        self.dumps: dict[str, dict] = {}
        self.inventory: dict[str, dict] = {}
        self.pairs: dict[str, dict[str, str]] = {}
        #: node path -> every affordance id that names it, per state. Built from the INVENTORY
        #: rather than from `pairs`, because two inventory entries sharing one id both resolve
        #: through the one pairing row and a dict keyed by id would lose the second (`D-m23-w`).
        self.claims: dict[str, dict[str, list[str]]] = {}
        #: affordance id -> node path, for the pairings a layer may actually compare. Derived once
        #: in `derive_pairings` and read by every layer that compares two sides of a pairing.
        self.comparable: dict[str, dict[str, str]] = {}
        self.citations: dict[str, str] = {}
        self.extra_allowed: dict[str, dict[str, str]] = {}
        self.breadth_rows: list[tuple] = []

    def frame(self, state: str) -> str:
        """Which element inside the section holds this state, as `mock-affordances.py` selects it.

        `v-<state>` by default, which is every board and the Settings window. A manifest may
        override per state with `stateFrames`, and a value beginning with `#` is an id rather than
        a class. The override exists because a SHEET has no `.v-*` frame: `#sh-readme` carries its
        whole state in one element, so without it the census exits 3 and the surface cannot be
        measured at all. Manifests carrying no `stateFrames` are byte-identical in behaviour.
        """
        return self.manifest.get("stateFrames", {}).get(state, f"v-{state}")

    def load(self) -> None:
        for state in self.states:
            path = os.path.join(self.dump_dir, f"{self.surface}.{state}.json")
            self.dumps[state] = load_json(path, f"dump[{state}]")
            if not self.dumps[state].get("root"):
                raise Inconclusive(f"dump[{state}]: {path} carries no root node")

            result = run([
                sys.executable, os.path.join(ROOT, "scripts/acceptance/mock-affordances.py"),
                os.path.join(ROOT, self.manifest["mock"]), self.section, self.frame(state),
            ])
            if result.returncode != 0:
                raise Inconclusive(f"inventory[{state}]: {result.stderr.strip() or result.stdout.strip()}")
            self.inventory[state] = json.loads(result.stdout)

        pairing = os.path.join(ROOT, self.manifest["pairing"])
        if not os.path.exists(pairing):
            raise Inconclusive(f"pairing: no file at {pairing}")
        seen = 0
        with open(pairing, encoding="utf-8") as handle:
            for raw in handle:
                line = raw.rstrip("\n")
                if not line.strip() or line.lstrip().startswith("#"):
                    continue
                parts = line.split("\t")
                if len(parts) < 3:
                    raise Inconclusive(f"pairing: '{line[:60]}' is not state<TAB>affordance<TAB>node")
                state, affordance, node = parts[0], parts[1], parts[2]
                citation = parts[3] if len(parts) > 3 else ""
                seen += 1
                if state not in self.states:
                    raise Inconclusive(f"pairing: unknown state '{state}'")
                if affordance.startswith("+"):
                    self.extra_allowed.setdefault(state, {})[affordance[1:]] = citation
                    continue
                if node == "-":
                    if citation:
                        self.citations[affordance] = citation
                    continue
                self.pairs.setdefault(state, {})[affordance] = node
                if citation:
                    self.citations[affordance] = citation
        if seen == 0:
            raise Inconclusive(f"pairing: {pairing} declares nothing, so every affordance reads absent")
        self.derive_pairings()

    def derive_pairings(self) -> None:
        """Which pairings a layer is allowed to compare, decided once for every layer that compares.

        `self.pairs` is a declaration — which build node somebody says answers which mock affordance
        — and nothing about it is a measurement. Two tests stand between that declaration and a
        comparison:

        **One claimant.** The dict is keyed by affordance, so any number of affordances may name one
        control. Two that do are two rows credited to one measurement, and neither of them was
        measured: whichever the control answers, the rest were not.

        **A vouched pairing.** `VOUCHED_CONTROLS` is the gate's record that this build role and kind
        may answer this mock kind at all. Without it, "these two are the same control" is an
        assertion the pairing file made about itself.

        Both tests used to live inside `layer_breadth`, which is one of the two layers that reads
        `self.pairs`. `layer_copy` reads the same structure and applied neither, so a pairing breadth
        filed `unclassified` because it could not establish the two were the same control produced,
        in the same run, a copy finding stating a measured difference between their labels. A test
        that lives in a reader holds for that reader; a test that lives in the structure holds for
        every reader there will ever be, including the next layer somebody adds.
        """
        for state in self.states:
            nodes = index_nodes(self.dumps[state]["root"], f"dump[{state}]")
            pairs = self.pairs.get(state, {})

            claims: dict[str, list[str]] = {}
            for affordance in self.inventory[state]["affordances"]:
                claimed = pairs.get(affordance["id"])
                if claimed is not None:
                    claims.setdefault(claimed, []).append(affordance["id"])
            self.claims[state] = claims

            comparable: dict[str, str] = {}
            for affordance in self.inventory[state]["affordances"]:
                node_path = pairs.get(affordance["id"])
                if node_path is None:
                    continue
                node = nodes.get(node_path)
                if node is None:
                    continue  # the breadth layer owns pairing integrity and reports this
                if len(claims.get(node_path, [])) > 1:
                    continue
                if not vouched_pairing(affordance["kind"], node):
                    continue
                comparable[affordance["id"]] = node_path
            self.comparable[state] = comparable


def gate(run: Run) -> int:
    if len(sys.argv) < 3:
        sys.stderr.write("usage: mock_fidelity.py <layers.json> <dump-dir> [--report <path>]\n")
        return 2
    manifest_path, dump_dir = sys.argv[1], sys.argv[2]
    if "--report" in sys.argv:
        index = sys.argv.index("--report") + 1
        if index >= len(sys.argv):
            sys.stderr.write("usage: mock_fidelity.py <layers.json> <dump-dir> [--report <path>]\n"
                             "       --report was given with no path after it\n")
            return 2
        run.report_path = sys.argv[index]
    report_path = run.report_path

    # The surface is needed for the unmeasured ledger before the manifest is known to parse, so it
    # falls back to the path rather than failing to name what could not be measured.
    surface = run.surface = os.path.basename(manifest_path).split(".")[0]

    try:
        with measuring("manifest"):
            manifest = load_json(manifest_path, "manifest")
            surface = run.surface = manifest.get("surface", surface)
            declared = {entry["name"]: entry for entry in manifest["layers"]}
    except Inconclusive as error:
        emit(f"INCONCLUSIVE {error}")
        write_unmeasured_report(report_path, surface, str(error))
        return 3

    # Every one of these five exits is a run that measured nothing, and each used to return 3 while
    # leaving the last good table on disk — the same stale ledger `measuring()` was added to end,
    # reached by a validation that failed rather than by an exception. `unmeasured()` is the single
    # door out, so a new check added here cannot forget the ledger without also forgetting to exit.
    def unmeasured(reason: str) -> int:
        emit(f"INCONCLUSIVE {reason}")
        write_unmeasured_report(report_path, surface, reason)
        return 3

    if len(manifest["layers"]) != len(declared):
        # `{entry["name"]: entry for entry in ...}` keeps the LAST of any repeated name and says
        # nothing, so a manifest carrying `breadth` twice — the second copy `required: false` with
        # a substitute — silences a required layer through a key collision. The dict is shorter
        # than the list it was built from, and until now nothing compared the two lengths.
        return unmeasured(
            f"manifest: declares {len(manifest['layers'])} layer entries under {len(declared)} "
            "distinct names, so at least one name appears twice and the later entry silently "
            "replaced the earlier one"
        )
    if set(LAYER_ORDER) != set(LAYERS):
        # The run order is written out longhand so the report reads in a fixed order, which makes it
        # a second list of layer names that can drift from `LAYERS`. If it does, `declared[name]`
        # raises a `KeyError` from outside `measuring()` — one line above the boundary that exists
        # to catch exactly that.
        return unmeasured(
            f"gate: the run order and the layer table disagree: "
            f"{sorted(set(LAYER_ORDER) ^ set(LAYERS))}"
        )
    unknown = set(declared) - set(LAYERS)
    if unknown:
        return unmeasured(f"manifest: declares layers this gate cannot run: {sorted(unknown)}")
    missing = set(LAYERS) - set(declared)
    if missing:
        return unmeasured(
            f"manifest: does not declare {sorted(missing)}, so those layers are silent")
    for name, entry in declared.items():
        if not entry.get("required", True) and name not in ALLOWED_OPTIONAL:
            return unmeasured(
                f"manifest: '{name}' is marked required:false. Only {sorted(ALLOWED_OPTIONAL)} may "
                "be, and that allowlist lives in the gate rather than in the manifest the gate "
                "reads."
            )
        if not entry.get("required", True) and not entry.get("substitute"):
            return unmeasured(f"manifest: '{name}' is optional with no substitute recorded")

    try:
        # Construction is inside the boundary as well as `load`. `Context.__init__` reads
        # `manifest["floors"]` and four more required keys, so a hand-authored `<surface>.layers.json`
        # missing one raised a `KeyError` from outside every `try` in this function — and that file
        # is the first artifact each of M15–M22 writes, which makes it the error a future conversion
        # is most likely to make first.
        with measuring("context"):
            ctx = Context(manifest, dump_dir)
            ctx.load()
    except Inconclusive as error:
        emit(f"INCONCLUSIVE {error}")
        write_unmeasured_report(report_path, surface, str(error))
        return 3

    results: list[Layer] = []
    blocked: list[tuple[str, str]] = []
    for name in LAYER_ORDER:
        entry = declared[name]
        try:
            with measuring(name):
                layer = LAYERS[name](ctx)
                # The floor every layer has, underneath the four a manifest names. `lintFiles` was
                # added because the literals layer read a census and compared it to nothing — but
                # that is a property of layers, not of that layer, and writing one floor per layer
                # closes a list. A required layer that ran, raised nothing and measured nothing has
                # produced the pass and the cannot-discriminate in the same shape, which is the G4
                # defect exactly (planning/features-to-triage/
                # G4-assertions-that-do-not-read-their-own-quantity.md). Its verdict does not
                # exist, so it says so. The optional layers are excluded because a substituted
                # layer is a measurement made somewhere else, recorded in the manifest.
                if entry.get("required", True) and layer.observations == 0:
                    raise Inconclusive(
                        f"{name}: the layer ran, raised nothing and measured nothing — 0 "
                        "observations. A layer with an empty population cannot tell a surface that "
                        "agrees from a surface it never looked at, and both of those print `clean`."
                    )
                results.append(layer)
        except Inconclusive as error:
            layer = Layer(name, inconclusive=str(error))
            results.append(layer)
            if entry.get("required", True):
                blocked.append((name, str(error)))

    # Written before a line of it is printed, and that order is the fix rather than a tidy-up.
    # The console loop below is several hundred `print` calls carrying arbitrary text from the
    # dumps, and it used to sit BETWEEN the layers and this write. A console that could not encode
    # one of those lines therefore killed the process at exit 1 — the code that means differences
    # were found — with the report never reached and the previous run's `servers.ledger.md` intact
    # on disk, while `mock-fidelity-gate.sh` printed `ledger written to …` on the next line. That is
    # the stale-ledger failure this gate has now closed three times, arriving one frame further out
    # each time. Measuring the layers and then losing the table to a `print` is the one ordering
    # that cannot be defended, so the table goes down first.
    if report_path:
        try:
            with measuring("report"):
                write_report(report_path, ctx, results, declared)
            run.report_written = True
            emit(REPORT_MARKER + report_path)
        except Inconclusive as error:
            emit(f"INCONCLUSIVE {error}")
            write_unmeasured_report(report_path, ctx.surface, str(error))
            return 3

    print(f"mock-fidelity: surface '{ctx.surface}' across {len(ctx.states)} states")
    findings = 0
    for layer in results:
        if layer.inconclusive:
            required = declared[layer.name].get("required", True)
            tag = "INCONCLUSIVE" if required else "inconclusive (substituted)"
            print(f"  {layer.name:18s} {tag}")
            for line in layer.inconclusive.splitlines():
                print(f"      {line}")
            if not required:
                print(f"      substitute: {declared[layer.name]['substitute']}")
            continue
        findings += len(layer.findings)
        status = "clean" if not layer.findings else f"{len(layer.findings)} finding(s)"
        print(f"  {layer.name:18s} ran · {layer.note} · {status}")
        for line in layer.findings[:400]:
            print(f"      - {line}")
        for line in layer.carried[:400]:
            # Truncated on purpose: an asset token's value is a base64 data URI several hundred
            # kilobytes long, and a report nobody can scroll is a report nobody reads. The full
            # value is in planning/fidelity/token-register.json, which the suite diffs against.
            print(f"      carried: {line[:200]}{'…' if len(line) > 200 else ''}")

    if blocked:
        print(f"mock-fidelity: EXIT 3 — {len(blocked)} required layer(s) could not run")
        return 3
    if findings:
        print(f"mock-fidelity: EXIT 1 — {findings} finding(s)")
        return 1
    print("mock-fidelity: EXIT 0 — every required layer ran and found nothing")
    return 0


def main() -> int:
    """The boundary around the whole run, which is the widest thing there is to put one around.

    `measuring()` closed the class one frame at a time and the class kept being wider than the
    frame. It wrapped the layers, then `Context(...)` and `ctx.load()`, then the report write — and
    each time, the next verifier found the property failing somewhere else in `main()`: the console
    print loop, which ran between the layers and the report write and is outside all of them.

    Enumerating the remaining frames one more time is the move that has now failed three times, so
    this stops enumerating. Everything `gate()` does is inside one `except Exception`, including
    the argument parse, the four validation returns, the handlers of the other boundaries, the
    console loop and the final verdict print. Whatever raises, the run did not deliver a verdict,
    and the exit code for that is 3 with the ledger saying so.

    Two things stay outside it, both deliberately. `KeyboardInterrupt` and `SystemExit` derive from
    `BaseException`: an operator pressing ^C is not an unmeasurable surface. And a ledger already
    written is not overwritten with "this run did not produce a table", because by then it did —
    the run failed to REPORT a measurement rather than to make one, and replacing a real table with
    an obituary would be this gate telling a reader something it knows to be untrue.

    So the property is about what this gate PRODUCES, not about every code the process can exit
    with: a verdict is 0, 1 or 3, a usage error is 2, and ^C is neither — it is the run being
    stopped rather than the run reaching an answer. `gpt-5.6-sol` was right that the unqualified
    form ("the process exits 0/1/2/3") is false at 130, and the honest repair is the wording rather
    than swallowing the interrupt.

    `Run()` is the one statement before the `try`, and it assigns three constants. The handler is
    the one region after it, and its body is wrapped so it cannot escape either — `emit` and
    `write_unmeasured_report` already swallow their own failures, and the guard makes that
    structural rather than a property of the two functions it happens to call today.
    """
    run = Run()
    try:
        code = gate(run)
        # The last thing that can raise, and it raises after every boundary inside `gate()` has
        # been left. Doing it here rather than letting the interpreter do it at shutdown is what
        # turns a broken pipe from exit 120 into exit 3. Both streams, because either one can
        # carry the process to 120 from a frame this file does not own.
        #
        # It is caught HERE rather than left to the boundary below, and the reason is the word
        # "after" in the line above. By this point `gate()` has returned: it has written whatever
        # ledger it was going to write and has already said, on the way past, what it did. Letting
        # this flush fall into that handler re-entered the obituary logic with `report_written`
        # False and a real `report_path`, so the obituary was written a SECOND time and the ledger
        # a reader opens said `gate: BrokenPipeError` where the first write had said
        # `manifest: no artifact at …` — the true cause replaced by a downstream symptom, in the
        # file whose subject is honest reporting. Measured 3/3 on a direct invocation whose stdout
        # had no reader; `mock-fidelity-gate.sh` cannot reach it because `tee` holds the pipe open.
        #
        # This says nothing about what is on disk. The route that reaches it includes the one where
        # the obituary write itself failed, and there the ledger is an earlier run's — the WARNING
        # one line above is what describes it, and a second sentence claiming the file records this
        # run would contradict it (`claude-fable-5`, asked to break rather than review).
        try:
            sys.stdout.flush()
            sys.stderr.flush()
        except Exception as error:
            emit(f"INCONCLUSIVE gate: {type(error).__name__}: {error}\n"
                 "            The verdict was reached and this happened while flushing after it, "
                 "so the run has no delivered verdict. What it already said about the ledger is "
                 "what stands.")
            hush_streams()
            return 3
        return code
    except Exception as error:
        try:
            # The reason says what is true of THIS run rather than one sentence for both cases. A
            # failure after the report was written has measured eight layers, and printing "nothing
            # this covers was measured" one line above "the ledger describes the layers that ran"
            # is the gate contradicting itself in the file whose subject is honest reporting
            # (`gpt-5.6-sol`).
            if run.report_written:
                what = ("            The layers ran and the ledger was written. What failed came "
                        "after the measurement, so this run has a table and no delivered verdict:")
            else:
                what = ("            Nothing this covers was measured. The gate raised outside "
                        "every layer, rather than returning a verdict:")
            reason = (
                f"gate: {type(error).__name__}: {error}\n{what}\n"
                + "\n".join("            " + line
                            for line in traceback.format_exc().rstrip().splitlines())
            )
            emit(f"INCONCLUSIVE {reason}")
            if run.report_written:
                emit(
                    f"mock-fidelity: the ledger at {run.report_path} was written before this "
                    "happened and describes the layers that ran. It stands; this run's verdict "
                    "does not."
                )
            else:
                write_unmeasured_report(run.report_path, run.surface, reason)
        except Exception:
            pass
        # Last, so nothing that still had something to say is silenced by it: if a stream is still
        # refusing at this point, the buffer it is refusing has to go somewhere or the interpreter
        # raises again during shutdown and overwrites this exit code with 120.
        try:
            sys.stdout.flush()
            sys.stderr.flush()
        except Exception:
            hush_streams()
        return 3


def write_unmeasured_report(path: str | None, surface: str, reason: str) -> None:
    """Overwrite the ledger for a run that did not reach a verdict.

    The stale-ledger failure has two halves, and fixing the exit code fixes one of them. A reader
    who opens `servers.ledger.md` after a run that raised still finds the last good run's table,
    with its counts and its `clean` cells, and nothing in the file says the run that just happened
    measured nothing. So a run that cannot measure replaces the file with what happened to it.

    It does not say *when* the run stopped, because it is called from stages that are not all before
    the layers — a `write_report` that raises has measured eight layers and lost the table, and a
    file claiming "before any layer ran" would be this gate telling a reader something it knows to
    be untrue. The `reason` opens with the stage name, so the file says only what it has.

    Nor can it fail quietly. Suppressing `OSError` made "the ledger was replaced" and "the ledger
    could not be replaced, so the table you are reading is the previous run's" print the same
    nothing, which is the stale ledger again with a permission bit in front of it. Anything raised
    here is reported and the exit stays 3: a ledger that could not be written is not a measurement.
    """
    if not path:
        return
    try:
        os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
        with open(path, "w", encoding="utf-8") as out:
            out.write(f"# Breadth ledger — {surface} (generated by "
                      "scripts/acceptance/mock-fidelity-gate.sh)\n\n")
            out.write("## This run did not produce a table\n\n"
                      "The gate exited 3 without completing a measurement, so there are no rows "
                      "below rather than no differences. What stopped it, and at which stage, "
                      "verbatim:\n\n```\n")
            out.write(reason.rstrip() + "\n```\n")
        emit(REPORT_MARKER + path)
    except Exception as error:
        emit(f"mock-fidelity: WARNING the ledger at {path} could not be replaced "
              f"({type(error).__name__}: {error}). Whatever table is on disk is an earlier run's "
              "and does not describe this one.")


def write_report(path: str, ctx: Context, results: list[Layer], declared: dict) -> None:
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w", encoding="utf-8") as out:
        out.write("# Breadth ledger — {} (generated by scripts/acceptance/mock-fidelity-gate.sh)\n\n".format(ctx.surface))
        out.write(
            "Every row is derived on the run that wrote this file: the mock side from\n"
            "`scripts/acceptance/mock-affordances.py`, the build side from the measurement harness's\n"
            "dump. Nothing here is hand-maintained, which is what stops a row being deleted to make a\n"
            "finding disappear.\n\n"
        )
        out.write("## Layers\n\n| Layer | Result | Detail |\n|---|---|---|\n")
        for layer in results:
            if layer.inconclusive:
                required = declared[layer.name].get("required", True)
                out.write("| `{}` | {} | {} |\n".format(
                    layer.name, "**INCONCLUSIVE**" if required else "inconclusive (substituted)",
                    layer.inconclusive.splitlines()[0].replace("|", "\\|")[:200]))
            else:
                out.write("| `{}` | {} | {} |\n".format(
                    layer.name, "clean" if not layer.findings else f"{len(layer.findings)} finding(s)",
                    layer.note.replace("|", "\\|")))
        out.write("\n## Present / divergent / absent\n\n")
        out.write("| State | Affordance | Kind | Status | Mock value | Build value | Citation |\n")
        out.write("|---|---|---|---|---|---|---|\n")
        for row in ctx.breadth_rows:
            out.write("| " + " | ".join(str(cell).replace("|", "\\|") for cell in row) + " |\n")


if __name__ == "__main__":
    sys.exit(main())
