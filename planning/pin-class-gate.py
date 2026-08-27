#!/usr/bin/env python3
"""Every parity vector declares what it pins, and a vector that re-types its reference is refused.

P11. Five vectors have now been found carrying a hand-copy of the reference expression they exist
to pin -- `auth-pages`, `registry-limit`, `string-ordering`, `usage-limit`, `locale-compare` -- and
each was proved blind the same way: mutate the reference, and `make parity-regen` stays at exit 0.
A vector that re-types its reference cannot see that reference move, so it reports the committed
corpus as matching while the thing it names has drifted.

All five are closed as of `P9`, and `CARRY` below is empty. **The sweep that found them was a
snapshot.** Nothing prevented a sixth, which is what this gate is: the default for a new vector is
refusal.

THE TWO CLASSES, and why there are exactly two.

  src-export        The vector pins a named production export. It must `require` that export out
                    of the built reference and carry no local implementation of it. This is the
                    class every vector over router behaviour belongs to, because there is a second
                    copy -- the Swift port -- and the vector exists to catch the two diverging.

  platform-builtin  The vector pins the PLATFORM's own semantics, where there is no second copy
                    that can drift: `JSON.parse`/`JSON.stringify` round-tripping, `toISOString`,
                    `Number(x)` coercion, `new URL(...)` parsing. Computing the expectation live
                    from the builtin is the only way to state it, and the builtin is the oracle.
                    Four vectors are legitimately this: json-roundtrip, iso8601, js-to-number,
                    url-parse. The vocabulary is closed (`BUILTINS` below) and `localeCompare` is
                    deliberately NOT in it -- the registry has its own comparator, so that IS a
                    second copy.

An UNANNOTATED writer is a finding. That is the property that makes this a prevention rather than
another snapshot: a sixth vector added tomorrow fails until somebody says what it pins.

WHAT THE ENFORCEMENT ACTUALLY MEASURES, stated rather than implied.

  R0  a `src-export` region must reach its declared exports through a binding this file resolved
      back to `require(join(distDir, '<module>.js'))`. `auth-pages` was the shape: it named
      `src/auth.ts`'s `PAGE` in a comment and required nothing at all. `P9` closed it by importing
      `PAGE`, and R0 is what now holds that import in place.
  R1  a `src-export` region may contain none of the computation constructs in `COMPUTATION` --
      measured, not guessed: those seven patterns fire on exactly the four re-typed regions in
      `scripts/parity/` and on none of the nineteen compliant `src-export` regions beside them.
  R2  a `platform-builtin` region may declare only names in `BUILTINS`, must exercise each one it
      declares, must reference no reference-module binding, and may use a computation construct
      only where that construct IS the builtin it declared.
  R3  no region may carry a template literal of 40 characters or more that appears verbatim in
      `src/`. That is the `auth-pages` shape stated directly: five fragments of `src/auth.ts`'s
      `PAGE` were re-typed into the generator under a comment claiming the opposite. The threshold
      and the backtick restriction are both measured -- a plain string of the same length is a
      legitimate case INPUT, and `P9`'s corrected generator still carries one.

  It does NOT prove a vector is aimed at the right export, and it does not prove the expectation
  is the one the Swift consumer reads. A region can satisfy every rule here and still pin a
  neighbouring export. `scripts/parity/mutation-gate.sh` is the instrument for that; this one
  answers the narrower question of whether an expectation was computed or copied.

THE CARRY, and why it is a constant in this file rather than a registry.

  Five regions failed R0/R1/R3 when this gate was written, and they were the five the item was
  about. Their fix was `P9`'s -- it adds four production exports (`config.compareStrings`,
  `control.usageRecentLimit`, `control.registrySearchLimit`, `registry.compareUpdatedAt`) and could
  not be re-done here without re-doing that branch. So they were carried BY NAME in `CARRY`, each
  declaring the item that closes it in a `// pin-carry:` line the region itself also carried. `P9`
  merged, the five regions now import their exports, and both the entries and the `// pin-carry:`
  lines are gone -- which is the mechanism working, not it being switched off.

  A carry is not a class and cannot be declared into existence: a name absent from `CARRY` is a
  blocking finding however the region annotates itself, so a sixth vector cannot join by copying
  its neighbour's comment. A carry also names the CLASS it excuses, because re-labelling is the
  cheapest escape and this gate's own arm found it -- declaring `locale-compare` a
  `platform-builtin` made its finding vanish and the run exit 0 before the class was carried too.
  `CARRY` can only shrink -- a carried region that passes every rule is itself a finding, so `P9`
  deleted its entries in the same change that fixed the regions. Every run prints the carried set
  at the top of the report, so a green here never reads as clean; with `CARRY` empty the report
  says `0 carried`, and that is the only reading of this gate that means what it appears to.

Exit codes: 0 every region declared and compliant (carried regions named), 1 a finding, 2 the
control failed or the population was empty -- which is not a pass.
"""
from __future__ import annotations  # `X | None` is evaluated at def time on 3.9; the gates run under /usr/bin/python3


import argparse
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
VECTORS = "app/Tests/RouterCoreTests/Vectors"
SRC = "src"

CLASSES = ("src-export", "platform-builtin")

#: The closed vocabulary a `platform-builtin` region may declare, and how each is recognised in
#: code. Nothing joins this without an argument that the platform is the ONLY implementation --
#: which is why `localeCompare` is not here and never was.
BUILTINS = {
    "JSON.parse": re.compile(r"\bJSON\.parse\s*\("),
    "JSON.stringify": re.compile(r"\bJSON\.stringify\s*\("),
    "Date#toISOString": re.compile(r"\.toISOString\s*\("),
    "Number": re.compile(r"(?<![.\w])Number\s*\("),
    "URL": re.compile(r"\bnew\s+URL\s*\("),
}

#: How an expectation gets computed locally instead of imported. Each row was checked against the
#: whole generator corpus with comments and string literals stripped: together they fire on
#: string-ordering, locale-compare, usage-limit and registry-limit, and on nothing else -- not on
#: the nineteen compliant `src-export` regions, and not on the four `platform-builtin` ones.
#:
#: `.toISOString(` is deliberately absent even though `iso8601` pins it. A seeded usage record
#: stamps its own timestamp, so the pattern fires on legitimate INPUT data in a `src-export`
#: region; it is recognised as a declarable builtin above and not as a computation here.
#: `?? null` is likewise absent: coalescing an absent member to `null` is JSON projection, where
#: coalescing to a value (`?? 200`, `?? 30`) is the reference's default re-typed.
COMPUTATION = [
    ("Math.* other than Math.sign", re.compile(r"\bMath\.(?!sign\b)\w+")),
    ("Number(...) coercion", re.compile(r"(?<![.\w])Number\s*\(")),
    ("parseInt/parseFloat", re.compile(r"(?<![.\w])parse(?:Int|Float)\s*\(")),
    ("localeCompare", re.compile(r"\.localeCompare\s*\(")),
    ("sort with an inline comparator", re.compile(r"\.sort\s*\(\s*(?:\(|function\b)")),
    ("?? with a default other than null", re.compile(r"\?\?(?!\s*null\b)")),
    ("|| as a default", re.compile(r"\|\|")),
]
#: Which computation row a declared builtin makes legitimate. Only one overlaps.
BUILTIN_EXEMPTS = {"Number": "Number(...) coercion"}

VERBATIM_MIN = 40

#: Regions that re-type their reference and are already scheduled: vector -> (the item that closes
#: it, the class the carry is for). This set may shrink and may never grow -- a name that is not
#: here is a blocking finding.
#:
#: **Empty, and that is the state this file was written to reach.** P11 opened it with five --
#: `auth-pages`, `string-ordering`, `locale-compare`, `usage-limit`, `registry-limit` -- each
#: naming `P9` as the item that closes it. P9 landed: all five now reach their declared export
#: through a `require(join(distDir, ...))` binding, so all five break no rule, and the gate's own
#: report turns a spent carry into a finding ("is carried and now breaks no rule -- the carry is
#: spent, delete it from CARRY"). Deleting them is therefore not tidying: a carry left behind a
#: fixed region is a permanent hole that every later run prints as a known one.
#:
#: The class is carried with the name because of what happened when this gate's own arm re-declared
#: `locale-compare` as `platform-builtin — String#localeCompare`: the vocabulary check fired, the
#: carry absorbed it, and the run exited 0. Re-labelling a vector is the cheapest way to silence
#: this gate, so a carry excuses only the class it was recorded against. That rule stays armed for
#: whatever is carried next.
CARRY: dict[str, tuple[str, str]] = {}

ANNOTATION = re.compile(r"//\s*pin-class:\s*([a-z-]+)\s*(?:—|--)\s*(.+?)\s*$", re.M)
CARRY_NOTE = re.compile(r"//\s*pin-carry:\s*([A-Za-z0-9]+)\s*(?:—|--)\s*(.+?)\s*$", re.M)
#: The two shapes a generator writes a committed vector with. `write(name, payload)` is the helper
#: every generator shares; the `writeFileSync` form is how `auth-pages` reached the corpus before
#: it was folded in, and leaving it out would exempt exactly the vector this item was raised over.
WRITER = re.compile(r"""(?:\bwrite\s*\(\s*['"]([a-z0-9-]+)['"]|writeFileSync\s*\([^)]*?Vectors/([a-z0-9-]+)\.json)""")
REQUIRE = re.compile(r"const\s+(\{[^}]*\}|\w+)\s*=\s*require\(\s*join\(\s*distDir\s*,\s*['\"](\w+)\.js['\"]")
DEFINITION = re.compile(r"(?m)^\s*(?:async\s+)?function\s+(\w+)\s*\(|^\s*(?:const|let)\s+(\w+)\s*=")
CALL = re.compile(r"(?<![.\w])(\w+)\s*\(")

CONTROL_FAILED = 2


# --------------------------------------------------------------------------------- source reading

def strip_comments(text: str) -> str:
    """`text` with every comment blanked to spaces, newlines kept.

    Length-preserving, so an offset in the result is the same offset in the original. That is what
    lets the writer search run over one view and the rule scan over another without either having
    to re-derive a line number.
    """
    out = list(text)
    i, n = 0, len(text)
    while i < n:
        two = text[i:i + 2]
        if two == "//":
            j = text.find("\n", i)
            j = n if j < 0 else j
            for k in range(i, j):
                out[k] = " "
            i = j
            continue
        if two == "/*":
            j = text.find("*/", i + 2)
            j = n if j < 0 else j + 2
            for k in range(i, min(j, n)):
                if out[k] != "\n":
                    out[k] = " "
            i = j
            continue
        if text[i] in "'\"`":
            i = end_of_string(text, i)
            continue
        i += 1
    return "".join(out)


def strip_strings(text: str) -> str:
    """`text` with the CONTENTS of every string and template literal blanked, quotes kept.

    Applied after the comments have gone, so what is left is live code alone. That distinction is
    load-bearing: `description: 'Math.min(Number(x ?? 30) || 30, 60) …'` is prose ABOUT the
    reference, and the same characters in an expression are a copy OF it. A scan over the raw file
    cannot tell those apart and reports both.
    """
    out = list(text)
    i, n = 0, len(text)
    while i < n:
        if text[i] in "'\"`":
            j = end_of_string(text, i)
            for k in range(i + 1, max(i + 1, j - 1)):
                if out[k] != "\n":
                    out[k] = " "
            i = j
            continue
        i += 1
    return "".join(out)


def end_of_string(text: str, start: int) -> int:
    """Offset just past the quote that closes the literal opening at `start`."""
    quote = text[start]
    j = start + 1
    n = len(text)
    while j < n:
        if text[j] == "\\":
            j += 2
            continue
        if text[j] == quote:
            return j + 1
        j += 1
    return n


def template_literals(text: str) -> list[tuple[int, str]]:
    """Every backtick literal, as (offset, body). Plain strings are not returned, by measurement.

    A 48-character plain string in this corpus is a case input that happens to be a value the
    reference also spells -- `P9`'s corrected auth generator still carries one, and reddening it
    would punish the fix. The five re-typed fragments of `PAGE` are all backtick literals.
    """
    found = []
    i, n = 0, len(text)
    while i < n:
        ch = text[i]
        if ch == "/" and text[i:i + 2] == "//":
            j = text.find("\n", i)
            i = n if j < 0 else j
            continue
        if ch in "'\"`":
            j = end_of_string(text, i)
            if ch == "`":
                found.append((i + 1, text[i + 1:max(i + 1, j - 1)]))
            i = j
            continue
        i += 1
    return found


def close_of_call(text: str, start: int) -> int:
    """Offset just past the `)` that closes the call opening at or after `start`.

    Paren depth over `strip_noise`d text, so a parenthesis inside a string or a comment cannot end
    a region early. Returns the end of the file when the parentheses do not balance, which makes
    an unbalanced generator over-scan rather than under-scan.
    """
    i = text.find("(", start)
    if i < 0:
        return len(text)
    depth = 0
    while i < len(text):
        if text[i] == "(":
            depth += 1
        elif text[i] == ")":
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    return len(text)


def statement_end(code: str, start: int) -> int:
    """Offset just past the statement beginning at `start`, over a strings-blanked view."""
    depth = 0
    i, n = start, len(code)
    while i < n:
        ch = code[i]
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        elif depth == 0 and ch in ";\n" and i > start:
            return i + 1
        i += 1
    return n


def definitions(code: str) -> dict[str, tuple[int, int]]:
    """Every named definition in the file, as name -> (start, end) offsets."""
    found: dict[str, tuple[int, int]] = {}
    for m in DEFINITION.finditer(code):
        name = m.group(1) or m.group(2)
        if name and name not in found:
            found[name] = (m.start(), statement_end(code, m.end()))
    return found


def with_helpers(region_code: str, region_raw: str, span: tuple[int, int],
                 code: str, text: str, defs: dict[str, tuple[int, int]]) -> tuple[str, str, list[str]]:
    """The region's own source plus the body of every local helper it calls, one binding deep.

    `usage-limit` computed its expectation in a `for` loop and `auth-pages` in a `PAGE` helper, so
    the shape this gate is written for is one where the copy sits beside the writer rather than
    inside it. Placing the annotation above the computation covers the first; pulling in a called
    helper covers the second, and it covers the general case of a copy hidden one call away.

    One level, syntactically, and it says so: a helper that calls a second helper is not followed.
    That is the same bound `reader-accounting.py` holds itself to, and for the same reason -- a
    resolution this gate cannot do is named rather than assumed away.

    Returns what it followed AND what it could not resolve to a definition in this file -- a
    builtin, an import, a method. The unresolved names are this gate's own blind spot, so they come
    back with the corpus and are counted in the report rather than dropped here in silence.
    """
    pulled: list[str] = []
    unresolved: list[str] = []
    extra_code, extra_raw = [], []
    for m in CALL.finditer(region_code):
        name = m.group(1)
        if name not in defs:
            unresolved.append(name)
        elif not (span[0] <= defs[name][0] < span[1]):
            # A definition already inside the region needs no pulling in; it is being scanned.
            start, end = defs[name]
            pulled.append(name)
            extra_code.append(code[start:end])
            extra_raw.append(text[start:end])
    return (region_code + "\n" + "\n".join(extra_code),
            region_raw + "\n" + "\n".join(extra_raw),
            sorted(set(pulled)), sorted(set(unresolved)))


class Region:
    def __init__(self, path, line, klass, spec, carry, vector, raw, code):
        self.path, self.line, self.klass, self.spec = path, line, klass, spec
        self.carry, self.vector, self.raw, self.code = carry, vector, raw, code
        self.helpers: list[str] = []
        self.unresolved: list[str] = []


def generators(root: Path) -> tuple[list[str], dict[str, list[str]]]:
    """Tracked `.mjs` under `scripts/`, and everything this reader threw away to reach them.

    The discards come back with the corpus rather than being filtered away in a comprehension:
    a narrowing nobody counts is the shape this whole family of gates exists to refuse, and a
    generator written in a language this reader cannot open must be visible as a hole rather than
    absent from the figure.
    """
    out = subprocess.run(["git", "ls-files"], capture_output=True, text=True, cwd=root)
    kept: list[str] = []
    dropped: dict[str, list[str]] = {"not under scripts/": [], "not a .mjs": []}
    for path in out.stdout.splitlines():
        if not path.startswith("scripts/"):
            dropped["not under scripts/"].append(path)
            continue
        if not path.endswith(".mjs"):
            dropped["not a .mjs"].append(path)
            continue
        kept.append(path)
    return kept, dropped


def regions_in(path: str, text: str) -> tuple[list[Region], list[tuple[int, str]]]:
    """Annotated regions in one generator, and every writer call that no annotation covers.

    A region opens at its `// pin-class:` line and closes at the end of the writer call that names
    the vector, so everything the annotation is standing over -- the seeding block, the local
    `const` a case list is built from -- is inside it. `usage-limit` computes its expectation
    before `write` is ever called, and a region that began at the writer call would not have seen
    the defect this gate was written for.

    Two views of the same source, both length-preserving so their offsets agree. The writer is
    found with strings intact, because the vector's NAME is a string literal; the rules are scanned
    with strings blanked, because a description quoting the reference is not a copy of it.
    """
    uncommented = strip_comments(text)
    code = strip_strings(uncommented)
    defs = definitions(code)
    found: list[Region] = []
    covered: list[tuple[int, int]] = []
    for m in ANNOTATION.finditer(text):
        line = text[:m.start()].count("\n") + 1
        klass, spec = m.group(1), m.group(2)
        carry = None
        # The carry note must be the NEXT line, so it cannot drift away from what it excuses.
        following = text[m.end():].split("\n", 2)
        if len(following) > 1:
            cm = CARRY_NOTE.search(following[1])
            if cm:
                carry = (cm.group(1), cm.group(2))
        wm = WRITER.search(uncommented, m.end())
        if not wm:
            found.append(Region(path, line, klass, spec, carry, None, "", ""))
            continue
        end = close_of_call(code, wm.start())
        vector = wm.group(1) or wm.group(2)
        span = (m.start(), end)
        body_code, body_raw, pulled, unresolved = with_helpers(
            code[m.start():end], text[m.start():end], span, code, text, defs)
        region = Region(path, line, klass, spec, carry, vector, body_raw, body_code)
        region.helpers = pulled
        region.unresolved = unresolved
        found.append(region)
        covered.append(span)
    orphans = []
    for wm in WRITER.finditer(uncommented):
        if any(a <= wm.start() < b for a, b in covered):
            continue
        orphans.append((text[:wm.start()].count("\n") + 1, wm.group(1) or wm.group(2)))
    return found, orphans


# ---------------------------------------------------------------------------------- the rules

def bindings_for(text: str) -> tuple[dict[str, str], set[str]]:
    """module name -> the binding it was required into, plus every destructured export name."""
    members: dict[str, str] = {}
    names: set[str] = set()
    for m in REQUIRE.finditer(text):
        lhs, module = m.group(1), m.group(2)
        if lhs.startswith("{"):
            for part in lhs.strip("{} ").split(","):
                part = part.strip().split(":")[-1].strip()
                if part:
                    names.add(part)
                    members[module] = members.get(module, "")
        else:
            members[module] = lhs
    return members, names


def judge(region: Region, file_text: str, src_corpus: str) -> list[str]:
    """Every rule this region breaks, as sentences. Empty means it complies."""
    findings: list[str] = []
    members, destructured = bindings_for(file_text)
    declared = [s.strip() for s in region.spec.split(",") if s.strip()]

    if region.klass == "src-export":
        for name in declared:
            module, _, export = name.partition(".")
            if not export:
                findings.append(f"R0 `{name}` is not a `module.export` name")
                continue
            binding = members.get(module)
            if binding is None:
                findings.append(f"R0 nothing in this file requires `{module}.js` out of the built reference")
                continue
            reached = (binding and re.search(rf"\b{re.escape(binding)}\.{re.escape(export)}\b", region.code)) or \
                      (export in destructured and re.search(rf"(?<![.\w]){re.escape(export)}\s*\(", region.code))
            if not reached:
                findings.append(f"R0 declares `{name}` and never calls it")
        for label, pattern in COMPUTATION:
            if pattern.search(region.code):
                findings.append(f"R1 computes its own expectation — {label}")
    elif region.klass == "platform-builtin":
        for name in declared:
            if name not in BUILTINS:
                findings.append(f"R2 `{name}` is not in the closed builtin vocabulary {sorted(BUILTINS)}")
            elif not BUILTINS[name].search(region.code):
                findings.append(f"R2 declares `{name}` and never uses it")
        for module, binding in members.items():
            if binding and re.search(rf"\b{re.escape(binding)}\.", region.code):
                findings.append(f"R2 reaches into the reference (`{binding}`) — that is a `src-export` vector")
        exempt = {BUILTIN_EXEMPTS[n] for n in declared if n in BUILTIN_EXEMPTS}
        for label, pattern in COMPUTATION:
            if label not in exempt and pattern.search(region.code):
                findings.append(f"R2 uses `{label}`, which it did not declare")
    else:
        findings.append(f"`{region.klass}` is not one of {list(CLASSES)}")

    for _, body in template_literals(region.raw):
        if len(body) >= VERBATIM_MIN and body in src_corpus:
            findings.append(f"R3 carries a {len(body)}-character template literal that appears "
                            f"verbatim in {SRC}/: {body[:48]!r}…")
    return findings


# ------------------------------------------------------------------------------------ the control

CLEAN_FIXTURE = """// pin-class: src-export — config.parseServer
write('fixture-one', {
  description: 'x',
  cases: rows.map((r) => ({ id: r.id, out: config.parseServer(r.name, r.raw) }))
});
"""
RETYPED_FIXTURE = """// pin-class: src-export — config.parseServer
write('fixture-one', {
  description: 'x',
  cases: rows.map((r) => ({ id: r.id, out: Math.min(Number(r.raw) || 30, 60) }))
});
"""
HELPER_FIXTURE = """const shape = (r) => Math.min(Number(r.raw) || 30, 60);
// pin-class: src-export — config.parseServer
write('fixture-one', {
  description: 'x',
  cases: rows.map((r) => ({ id: r.id, out: shape(config.parseServer(r.name, r.raw)) }))
});
"""
BARE_FIXTURE = """write('fixture-one', {
  description: 'x',
  cases: rows.map((r) => ({ id: r.id, out: config.parseServer(r.name, r.raw) }))
});
"""
PREAMBLE = "const config = require(join(distDir, 'config.js'));\n"


def control() -> str | None:
    """Prove all three arms on a synthetic generator before a real one is read.

    A rule set that matches nothing returns clean over any tree, which is indistinguishable from a
    clean tree. So, on a synthetic generator: a compliant region must be silent, a region that
    computes its own expectation must be reported, a copy hidden in a helper one call away must be
    reported, a writer with no annotation must be reported as uncovered, and a template literal
    lifted verbatim out of the reference must be reported.
    """
    src_corpus = "unrelated reference text"
    clean = PREAMBLE + CLEAN_FIXTURE
    regions, orphans = regions_in("control.mjs", clean)
    if len(regions) != 1 or orphans:
        return f"the clean arm resolved {len(regions)} region(s) and {len(orphans)} orphan(s), expected 1 and 0"
    if judge(regions[0], clean, src_corpus):
        return f"the clean arm reported a compliant region: {judge(regions[0], clean, src_corpus)}"

    retyped = PREAMBLE + RETYPED_FIXTURE
    regions, _ = regions_in("control.mjs", retyped)
    if not any(f.startswith("R1") for f in judge(regions[0], retyped, src_corpus)):
        return "the re-typed arm did not report a locally computed expectation"

    bare = PREAMBLE + BARE_FIXTURE
    regions, orphans = regions_in("control.mjs", bare)
    if len(orphans) != 1:
        return f"the unannotated arm reported {len(orphans)} uncovered writer(s), expected 1"

    helper = PREAMBLE + HELPER_FIXTURE
    regions, _ = regions_in("control.mjs", helper)
    if not any(f.startswith("R1") for f in judge(regions[0], helper, src_corpus)):
        return "the helper arm did not follow a call into a copy sitting one binding away"

    verbatim = PREAMBLE + "// pin-class: src-export — config.parseServer\nwrite('fixture-one', {\n" \
        "  cases: rows.map((r) => config.parseServer(`" + "a" * VERBATIM_MIN + "`))\n});\n"
    regions, _ = regions_in("control.mjs", verbatim)
    if not any(f.startswith("R3") for f in judge(regions[0], verbatim, "x " + "a" * VERBATIM_MIN + " y")):
        return "the verbatim arm did not report a template literal copied out of the reference"
    return None


# ------------------------------------------------------------------------------------- the report

def main() -> int:
    parser = argparse.ArgumentParser(description="Refuse a parity vector that does not say what it pins.")
    parser.add_argument("--control", action="store_true", help="run the arms and print the verdict only")
    args = parser.parse_args()

    bad = control()
    if bad:
        print(f"control FAILED: {bad}")
        print("no census printed — an instrument that cannot see the defect is not evidence")
        return CONTROL_FAILED
    print("control HELD (a compliant region is silent; a re-typed one, a copy one call away, an "
          "unannotated writer and a verbatim copy are each reported)")
    if args.control:
        return 0

    files, dropped = generators(ROOT)
    src_dir = ROOT / SRC
    src_corpus = "\n".join(p.read_text(encoding="utf-8") for p in sorted(src_dir.rglob("*.ts"))) \
        if src_dir.exists() else ""
    if not src_corpus:
        print(f"NOT A PASS — no TypeScript reference under {SRC}/, so R3 could not compare anything")
        return CONTROL_FAILED

    committed = sorted(p.stem for p in (ROOT / VECTORS).glob("*.json")) if (ROOT / VECTORS).exists() else []

    regions: list[Region] = []
    orphans: list[tuple[str, int, str]] = []
    unreadable: list[str] = []
    for relative in files:
        try:
            text = (ROOT / relative).read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError) as error:
            unreadable.append(f"{relative}: {type(error).__name__}")
            continue
        got, bare = regions_in(relative, text)
        regions.extend(got)
        orphans.extend((relative, line, name) for line, name in bare)

    print(f"corpus: {len(files)} tracked generator(s) under scripts/, "
          f"{len(regions)} annotated region(s), {len(committed)} committed vector file(s)")
    print(f"  not read: {len(dropped['not under scripts/'])} tracked path(s) outside scripts/, "
          f"{len(dropped['not a .mjs'])} under scripts/ that are not .mjs")
    for note in unreadable:
        print(f"  NOT READ — {note}")

    if not regions and not orphans:
        print("NOT A PASS — no writer and no annotation was found, so this run measured nothing.")
        return CONTROL_FAILED

    findings: list[str] = []
    carried_report: list[str] = []
    by_class = {k: 0 for k in CLASSES}

    for relative in files:
        try:
            text = (ROOT / relative).read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        for region in [r for r in regions if r.path == relative]:
            if region.vector is None:
                findings.append(f"{region.path}:{region.line} — an annotation with no writer after it")
                continue
            by_class[region.klass] = by_class.get(region.klass, 0) + 1
            broke = judge(region, text, src_corpus)
            carried = region.vector in CARRY and region.klass == CARRY[region.vector][1]
            if region.vector in CARRY and not carried:
                findings.append(f"{region.path}:{region.line} `{region.vector}` is carried as "
                                f"`{CARRY[region.vector][1]}` and now declares `{region.klass}` — a "
                                f"carry excuses the class it was recorded for, never a re-label")
            if carried and region.carry is None:
                findings.append(f"{region.path}:{region.line} `{region.vector}` is carried in this "
                                f"gate and carries no `// pin-carry:` line of its own")
            if region.carry and region.vector not in CARRY:
                findings.append(f"{region.path}:{region.line} `{region.vector}` declares a "
                                f"`// pin-carry:` line and is not in this gate's CARRY set — a carry "
                                f"cannot be declared into existence")
            if carried and not broke:
                findings.append(f"{region.path}:{region.line} `{region.vector}` is carried and now "
                                f"breaks no rule — the carry is spent, delete it from CARRY")
            if broke and not carried:
                for f in broke:
                    findings.append(f"{region.path}:{region.line} `{region.vector}` — {f}")
            if broke and carried:
                item = region.carry[0] if region.carry else CARRY[region.vector][0]
                carried_report.append(f"  {region.vector} (closes with {item}): " + "; ".join(broke))

    for relative, line, name in orphans:
        findings.append(f"{relative}:{line} `{name}` is written by nothing that declares a pin class")

    produced = {r.vector for r in regions if r.vector} | {n for _, _, n in orphans}
    for name in committed:
        if name not in produced:
            findings.append(f"{VECTORS}/{name}.json is committed and no generator region produces it")
    for name in sorted(produced):
        if name not in committed:
            findings.append(f"a region produces `{name}` and {VECTORS}/{name}.json is not committed")

    unused = sorted(set(CARRY) - produced)
    for name in unused:
        findings.append(f"CARRY names `{name}` and no region produces it — a carry for a vector "
                        f"that does not exist hides nothing and should go")

    print(f"classes: {by_class.get('src-export', 0)} src-export, "
          f"{by_class.get('platform-builtin', 0)} platform-builtin")
    if carried_report:
        print()
        print(f"CARRIED — {len(carried_report)} region(s) that re-type their reference, each already "
              f"scheduled. This is a known hole, not a clean result:")
        for row in carried_report:
            print(row)

    if findings:
        print()
        print("FINDINGS:")
        for f in findings:
            print(f"  {f}")
        print()
        print("A vector says what it pins, or it is refused. `src-export` imports a named production")
        print("export and carries no copy of it; `platform-builtin` computes from a builtin in the")
        print(f"closed vocabulary {sorted(BUILTINS)}.")
        return 1

    print()
    print(f"every vector declares a pin class; {len(carried_report)} carried, "
          f"{len(regions) - len(carried_report)} compliant")
    return 0


if __name__ == "__main__":
    sys.exit(main())
