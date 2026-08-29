#!/usr/bin/env python3
"""An instrument whose answer changes with the caller's working directory. This is what finds them.

## The defect this exists for

`G8`, first half. **A question answered at the wrong scope returns a clean answer.** There is no
dangling pointer, no missing file, no red — just a correct answer to a narrower question than the
one that mattered, indistinguishable from a correct answer to the right one.

The canonical instance is `git ls-files`. With no pathspec it enumerates **the current directory
downwards**, not the repository, so an enumeration written without an anchor answers about whatever
directory the caller happened to be standing in. Measured in this tree on 2026-08-29:

    git ls-files | wc -l          from the repository root      2163
    git ls-files | wc -l          from planning/                 955
    git ls-files | wc -l          from scripts/                  109

Three tracked instruments were reading their corpus that way, and all three were measured going
quiet:

  * `planning/claim-sweep.py` — 11 blocking hits and exit 1 from the root; **0 hits and exit 0**
    from `scripts/`. A clean answer, from the instrument whose own docstring is the rule about
    reading the whole corpus.
  * `planning/py39-annotation-gate.py` — `swept 77 tracked .py files` from the root, `swept 9` from
    `scripts/`. Both runs print `0 file(s) carry a PEP 604 union`, **and both print
    `control: HELD`**.
  * `planning/m33-branch-sweep.py` — `examined=233 affected=7 covered=0 n/a=226` from the root;
    `examined=233 affected=0 covered=0 n/a=233` from `scripts/`. It exists to find the branches
    whose green `swift test` covered nothing under `app/MCPRouter/`, and from a subdirectory it
    reports that there are none — with a full denominator beside the zero, which is the one guard
    its own header names.

The second one is the whole reason this gate exists beside `sweep-control-gate.py` rather than
inside it. A presence control plants an instance and confirms the instrument can see it — which it
can, in the nine files it was looking at. **A presence control proves the instrument is not blind.
It does not prove it was pointed at the right set.** The two failures look identical from outside
and one of them is invisible to the gate written for the other.

## What it checks

  1. **Statically**, over every tracked `.py` file: a `git` invocation whose subcommand enumerates a
     corpus (`ls-files`, `ls-tree`, `grep`) must be anchored — `-C <root>`, or a `cwd=` that is not
     a literal relative path. A `cwd="."` is the caller's directory under another name and is
     counted as unanchored. Subcommands that do not enumerate are counted and let through, with the
     count printed, so the population this gate declined is visible rather than assumed.
  2. **Dynamically**, over the instruments named in `INVARIANT_RUNS`: the same instrument run from
     the repository root and from a tracked subdirectory must produce the identical exit code and
     the identical stdout. This is the arm that runs the artifact instead of a model of it — the
     static rule is a claim about source text and the failure above is a claim about behaviour.
     This repository has already paid for a control that modelled an instrument rather than
     executing it: the lint-gate control that compared the old rule against the new one in
     isolation, and passed, while both defects sat in the script underneath it.

## Its own controls, run on every invocation

The headline claim is *no unanchored enumeration exists*, which is an absence claim, which is the
shape this repository distrusts. So eight arms run first, in a scratch tree under `mktemp` that is
never this corpus, and a run whose controls did not all hold exits 4 and prints no verdict:

    S1  an unanchored `git ls-files` must be reported
    S2  the same call with `-C <root>` must not
    S3  the same call with `cwd=root` must not
    S4  the same call with `cwd="."` must be reported — a literal relative cwd is not an anchor
    S5  `git rev-parse HEAD`, unanchored, must not be reported — it enumerates nothing
    D1  a planted cwd-sensitive script must be caught by the dynamic comparison
    D2  its anchored twin must pass it
    N1  a corpus of zero files must be a refusal, never a clean report

## What this does NOT reach, stated rather than implied

  * **Shell.** The population is Python, because an anchor in shell is a `cd` three lines earlier
    and a text scan cannot tell that from its absence. The gate measures how much it is declining
    rather than declaring the class empty: it counts tracked `.sh` files invoking an enumerating
    git subcommand and prints them by name. One does today — `scripts/acceptance/carrier-census.sh`,
    which `cd`s to a root it derives, the form a text scan cannot distinguish from its absence. The
    day a second appears, that line changes and nobody has to remember this paragraph.
  * **An argv this reader cannot resolve.** A `subprocess` call whose command is built from a
    variable is counted and named as unresolved, never assumed clean.
  * **Enumerations that are not git.** `os.walk`, `rglob` and `glob` on a root the instrument
    derives itself are already anchored by construction; on a literal `"."` they are not, and that
    form appears in this tree only inside a selftest that passes pre-canned text and never reads
    the path. Naming it here rather than blocking on it, because the finding would be false today
    and a gate whose first output is a false positive gets softened rather than fixed.
  * **Whether the anchored root is the right root.** This gate asks whether an enumeration is
    anchored to something the instrument derived, not whether that derivation is correct. A gate
    rooted at the wrong repository is anchored and wrong, and nothing here would see it.

## Exit codes

    0   every enumerating call is anchored and every invariant run agreed
    1   findings — an unanchored enumeration, or an instrument whose answer moved with its cwd
    2   usage
    3   inconclusive — the corpus is empty, git could not be read, or a file would not parse, so
        the set this gate would answer about does not exist
    4   a control did not hold, so nothing this run printed is evidence of anything
"""
from __future__ import annotations  # `X | None` is evaluated at def time on 3.9; the gates run under /usr/bin/python3

import argparse
import ast
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from input_accounting import Tally  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent

# A git subcommand whose result is a set of paths. Anchoring is load-bearing for exactly these:
# each one takes its pathspec relative to the process's working directory, so an unanchored call
# answers about a subtree rather than about the repository.
ENUMERATING = {"ls-files", "ls-tree", "grep"}

# The `subprocess` entry points. A wrapper method is not listed and does not need to be: the
# wrapper's own call site is in this corpus and is read there.
SUBPROCESS_FUNCS = {"run", "check_output", "Popen", "call", "check_call"}

# A `cwd=` holding one of these is the caller's directory spelled differently, not an anchor.
RELATIVE_CWD = {".", "./", ""}

# Vendored upstream. An edit that lands only here is a fork of the instrument, and a script
# behaving one way in this repo and another way everywhere else stops being evidence
# (`vendor/README.md`). Excluded from the finding set, counted and named on every run.
VENDOR_PREFIX = "vendor/"

# The instruments whose cwd-invariance is measured by running them, twice, on every invocation.
# Membership is a cost decision and each entry says what it costs.
INVARIANT_RUNS = [
    ("planning/py39-annotation-gate.py",
     "0.4s per run, reads the whole tracked .py corpus, writes nothing. The instrument G8's "
     "second measured instance was taken from."),
]

# Measured once rather than every run, with the reason. `planning/claim-sweep.py` reads all 2163
# tracked files whole; two runs cost ~24s of CPU inside a gate that otherwise costs one second.
# Its before/after is in `planning/evidence/G8/scope-invariance.md`, with the command.
NOT_RUN_HERE = [
    ("planning/claim-sweep.py",
     "reads every tracked file whole; ~12s CPU per run. Anchored and measured by hand at the "
     "commit that anchored it — see planning/evidence/G8/scope-invariance.md"),
]


# --------------------------------------------------------------------------------------------
# Reading the corpus


def tracked_python(root: Path) -> tuple[list[str], Tally]:
    """Every tracked `.py` path, and a tally naming everything this reader did not keep."""
    tally = Tally("scope-invariance corpus", "git ls-files -- '*.py'")
    out = subprocess.run(["git", "-C", str(root), "ls-files", "-z", "--", "*.py"],
                         capture_output=True)
    if out.returncode != 0:
        return [], tally
    fields = out.stdout.decode("utf-8", errors="replace").split("\0")
    # `git ls-files -z` TERMINATES every path, so the final field is always empty. It is removed by
    # position rather than filtered, so a truncated read is visible instead of being tidied away.
    if fields and fields[-1] == "":
        fields.pop()
    for rel in fields:
        if rel.startswith(VENDOR_PREFIX):
            tally.drop(rel, "vendored upstream")
        else:
            tally.keep(rel)
    return tally.kept, tally


def shell_enumerations(root: Path) -> tuple[list[str], Tally]:
    """Tracked `.sh` files invoking an enumerating git subcommand — the class this gate declines.

    The tally is returned and printed rather than the filter running silently, because "no shell file
    does this" is an absence claim over a set, and a set this reader narrowed without saying so is
    the defect the whole gate is about.
    """
    tally = Tally("shell decline", "git ls-files -- '*.sh'")
    out = subprocess.run(["git", "-C", str(root), "ls-files", "-z", "--", "*.sh"],
                         capture_output=True)
    fields = out.stdout.decode("utf-8", errors="replace").split("\0")
    if fields and fields[-1] == "":
        fields.pop()
    hits = []
    for rel in fields:
        try:
            text = (root / rel).read_text(encoding="utf-8", errors="replace")
        except OSError as exc:
            tally.drop(rel, f"unreadable ({exc.__class__.__name__})")
            continue
        if any(f"git {sub}" in text for sub in ENUMERATING):
            hits.append(tally.keep(rel))
        else:
            tally.drop(rel, "invokes no enumerating git subcommand")
    return sorted(hits), tally


# --------------------------------------------------------------------------------------------
# The static arm


def argv_prefix(node: ast.AST) -> list | None:
    """The literal string prefix of a subprocess argv, `None` when it is not a sequence literal.

    `["git", "-C", root] + list(a)` is the wrapper form three gates here use, so the left operand of
    a concatenation is read. An element this reader cannot resolve becomes `None` in the list rather
    than being dropped, because a hole in the middle of an argv is exactly what it must not assume.
    """
    if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Add):
        node = node.left
    if not isinstance(node, (ast.List, ast.Tuple)):
        return None
    return [el.value if isinstance(el, ast.Constant) and isinstance(el.value, str) else None
            for el in node.elts]


def subcommand(prefix: list) -> str | None:
    """The git subcommand, or `None` when an option or an unresolved element hides it."""
    i = 1
    while i < len(prefix):
        tok = prefix[i]
        if tok is None:
            return None
        if tok == "-C":
            i += 2
            continue
        if tok.startswith("-"):
            i += 1
            continue
        return tok
    return None


def anchor_of(prefix: list, keywords: list) -> str:
    """How this call is anchored: `-C`, `cwd=`, or `""` for not at all."""
    for i, tok in enumerate(prefix):
        if tok == "-C" and i + 1 < len(prefix):
            return "-C"
    for kw in keywords:
        if kw.arg != "cwd":
            continue
        value = kw.value
        if isinstance(value, ast.Constant) and isinstance(value.value, str) \
                and value.value in RELATIVE_CWD:
            continue  # a literal relative cwd is the caller's directory under another name
        return "cwd="
    return ""


def is_subprocess_call(node: ast.Call, imported: set) -> bool:
    """`subprocess.run(...)`, or a bare `run(...)` the module imported FROM subprocess.

    The bare-name half is gated on the import rather than on the spelling. Four files here define
    their own local `run()` or `.run()` wrapper around subprocess, and matching on the name alone
    classed every call to those helpers as an unresolved argv — 47 of them, an unreadable population
    this gate would then have had to declare. The helper's own call site is in this corpus and is
    where the anchor is decided.

    What this misses, named rather than implied: `import subprocess as sp`. No file here does it,
    and a module-alias table would be resolution two bindings deep in a gate that stops at one.
    """
    func = node.func
    if isinstance(func, ast.Attribute):
        return func.attr in SUBPROCESS_FUNCS and isinstance(func.value, ast.Name) \
            and func.value.id == "subprocess"
    if isinstance(func, ast.Name):
        return func.id in imported
    return False


def subprocess_imports(tree: ast.AST) -> set:
    """The names this module bound from `subprocess` — `from subprocess import run, PIPE`."""
    names = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.ImportFrom) and node.module == "subprocess":
            for alias in node.names:
                target = alias.asname or alias.name
                if alias.name in SUBPROCESS_FUNCS:
                    names.add(target)
    return names


class _CallScan(ast.NodeVisitor):
    """Every `subprocess` call site in one module, with one-binding-deep argv resolution.

    A command assembled into a local name — `cmd = ["git", "ls-files"]; subprocess.run(cmd)` — is
    resolved by looking the name up in its own function scope and then at module level. That is one
    binding deep and no further, the same depth `reader-accounting.py` resolves an iteration's
    subject to, and for the same reason: a name this reader cannot follow is COUNTED AND NAMED as
    unresolved rather than assumed clean.
    """

    def __init__(self, rel: str, imported: set):
        self.rel = rel
        self.imported = imported
        self.findings: list = []
        self.unresolved: list = []
        self.let_through = 0
        self._scopes: list[dict] = [{}]

    # -- scope tracking -------------------------------------------------------------------
    def _push(self, node) -> None:
        bindings: dict = {}
        for child in ast.walk(node):
            if isinstance(child, ast.Assign):
                for target in child.targets:
                    if isinstance(target, ast.Name) and isinstance(child.value, (ast.List, ast.Tuple)):
                        bindings[target.id] = child.value
        self._scopes.append(bindings)

    def visit_Module(self, node):  # noqa: N802
        self._push(node)
        self.generic_visit(node)

    def visit_FunctionDef(self, node):  # noqa: N802
        self._push(node)
        self.generic_visit(node)
        self._scopes.pop()

    visit_AsyncFunctionDef = visit_FunctionDef

    def _lookup(self, name: str):
        for scope in reversed(self._scopes):
            if name in scope:
                return scope[name]
        return None

    # -- the check ------------------------------------------------------------------------
    def visit_Call(self, node):  # noqa: N802
        self.generic_visit(node)
        if not is_subprocess_call(node, self.imported) or not node.args:
            return
        arg = node.args[0]
        if isinstance(arg, ast.Name):
            bound = self._lookup(arg.id)
            if bound is not None:
                arg = bound
        prefix = argv_prefix(arg)
        if prefix is None:
            self.unresolved.append((self.rel, node.lineno,
                                    "argv is neither a sequence literal nor a name bound to one"))
            return
        if not prefix or prefix[0] != "git":
            return
        anchor = anchor_of(prefix, node.keywords)
        sub = subcommand(prefix)
        if anchor:
            self.let_through += 1
        elif sub is None:
            self.findings.append((self.rel, node.lineno, "git ?",
                                  "unanchored, and the subcommand could not be resolved"))
        elif sub in ENUMERATING:
            self.findings.append((self.rel, node.lineno, f"git {sub}",
                                  "enumerates from the caller's working directory"))
        else:
            self.let_through += 1


def scan_source(text: str, rel: str) -> tuple[list, list, int]:
    """(findings, unresolved, let-through count) for one file's git call sites.

    Raises `SyntaxError` — a file this gate cannot parse is one it cannot answer about, and the
    caller turns that into exit 3 rather than into a silent pass.
    """
    tree = ast.parse(text)
    scan = _CallScan(rel, subprocess_imports(tree))
    scan.visit(tree)
    return scan.findings, scan.unresolved, scan.let_through


# --------------------------------------------------------------------------------------------
# The dynamic arm


def first_difference(a: str, b: str) -> tuple[str, str]:
    """The first line the two runs disagree on, so the report carries the disagreement itself."""
    la, lb = a.splitlines(), b.splitlines()
    for i in range(max(len(la), len(lb))):
        x = la[i] if i < len(la) else "<no line>"
        y = lb[i] if i < len(lb) else "<no line>"
        if x != y:
            return x.strip()[:90], y.strip()[:90]
    return "", ""


def run_twice(script: Path, root: Path, subdir: Path) -> tuple[bool, str, str]:
    """Run one instrument from `root` and from `subdir`.

    Returns (agreed, what-the-root-run-said, what-the-subdirectory-run-said). When they disagree the
    two strings carry the first line of output that differs, because an exit code alone would report
    `0 vs 0` on the instance this gate was written for.
    """
    a = subprocess.run([sys.executable, str(script)], cwd=str(root),
                       capture_output=True, text=True)
    b = subprocess.run([sys.executable, str(script)], cwd=str(subdir),
                       capture_output=True, text=True)
    if (a.returncode, a.stdout) == (b.returncode, b.stdout):
        return True, f"exit {a.returncode}", f"exit {b.returncode}"
    da, db = first_difference(a.stdout, b.stdout)
    return False, f"exit {a.returncode} · {da}", f"exit {b.returncode} · {db}"


# --------------------------------------------------------------------------------------------
# Controls


UNANCHORED_SRC = 'import subprocess\nsubprocess.run(["git", "ls-files"], capture_output=True)\n'
DASH_C_SRC = 'import subprocess\nsubprocess.run(["git", "-C", root, "ls-files"], capture_output=True)\n'
CWD_SRC = 'import subprocess\nsubprocess.run(["git", "ls-files"], capture_output=True, cwd=root)\n'
CWD_DOT_SRC = 'import subprocess\nsubprocess.run(["git", "ls-files"], capture_output=True, cwd=".")\n'
REV_PARSE_SRC = 'import subprocess\nsubprocess.run(["git", "rev-parse", "HEAD"], capture_output=True)\n'

PLANT_OFFENDER = (
    "import subprocess\n"
    "out = subprocess.run(['git', 'ls-files'], capture_output=True, text=True)\n"
    "print('files', len([x for x in out.stdout.split(chr(10)) if x]))\n"
)
PLANT_FIXED = (
    "import subprocess, pathlib\n"
    "ROOT = pathlib.Path(__file__).resolve().parent\n"
    "out = subprocess.run(['git', '-C', str(ROOT), 'ls-files'], capture_output=True, text=True)\n"
    "print('files', len([x for x in out.stdout.split(chr(10)) if x]))\n"
)


def controls() -> list[tuple[str, str, bool]]:
    """(id, what it proves, held). Every arm runs on every invocation."""
    arms: list[tuple[str, str, bool]] = []

    def found(src: str) -> bool:
        f, _, _ = scan_source(src, "<planted>")
        return bool(f)

    arms.append(("S1", "an unanchored `git ls-files` is reported", found(UNANCHORED_SRC)))
    arms.append(("S2", "`-C <root>` is not reported", not found(DASH_C_SRC)))
    arms.append(("S3", "`cwd=root` is not reported", not found(CWD_SRC)))
    arms.append(("S4", "`cwd=\".\"` IS reported — a literal relative cwd is not an anchor",
                 found(CWD_DOT_SRC)))
    arms.append(("S5", "`git rev-parse HEAD` is not reported — it enumerates nothing",
                 not found(REV_PARSE_SRC)))

    with tempfile.TemporaryDirectory() as tmp:
        d = Path(tmp)
        (d / "sub").mkdir()
        (d / "a.py").write_text("x = 1\n", encoding="utf-8")
        (d / "sub" / "b.py").write_text("y = 2\n", encoding="utf-8")
        (d / "offender.py").write_text(PLANT_OFFENDER, encoding="utf-8")
        (d / "fixed.py").write_text(PLANT_FIXED, encoding="utf-8")
        env_ok = True
        for cmd in (["git", "-C", str(d), "init", "-q"],
                    ["git", "-C", str(d), "add", "-A"]):
            if subprocess.run(cmd, capture_output=True).returncode != 0:
                env_ok = False
        if not env_ok:
            arms.append(("D1", "a scratch repository could be built", False))
            arms.append(("D2", "a scratch repository could be built", False))
            arms.append(("N1", "a scratch repository could be built", False))
        else:
            agreed, _, _ = run_twice(d / "offender.py", d, d / "sub")
            arms.append(("D1", "a planted cwd-sensitive script is caught by the comparison",
                         not agreed))
            agreed, _, _ = run_twice(d / "fixed.py", d, d / "sub")
            arms.append(("D2", "its anchored twin passes the comparison", agreed))
            empty = Path(tmp) / "empty"
            empty.mkdir()
            subprocess.run(["git", "-C", str(empty), "init", "-q"], capture_output=True)
            _, tally = tracked_python(empty)
            arms.append(("N1", "a corpus of zero files is a refusal, not a clean report",
                         tally.measured_nothing()))
    return arms


# --------------------------------------------------------------------------------------------


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--selftest", action="store_true",
                        help="run the controls only and report; changes nothing")
    parser.add_argument("--quiet", action="store_true", help="verdict lines only")
    args = parser.parse_args()

    arms = controls()
    for arm_id, what, held in arms:
        print(f"  control {arm_id}  {'HELD' if held else 'DID NOT HOLD'}  {what}")
    if not all(held for _, _, held in arms):
        print("\nCONTROL FAILED scope-invariance: an arm did not hold, so nothing this run would "
              "print about the corpus is evidence of anything.")
        return 4
    if args.selftest:
        print(f"\nscope-invariance selftest: {len(arms)} arms, all held.")
        return 0

    corpus, tally = tracked_python(ROOT)
    print()
    print(tally.line())
    for rel in sorted(tally.named("vendored upstream")):
        print(f"    not read (vendored): {rel}")
    if tally.measured_nothing():
        print("\nINCONCLUSIVE scope-invariance: the corpus is empty. A gate that compared nothing "
              "has not passed.")
        return 3

    findings, unresolved, let_through, unparsed = [], [], 0, []
    for rel in corpus:
        try:
            text = (ROOT / rel).read_text(encoding="utf-8", errors="replace")
        except OSError as exc:
            unparsed.append((rel, str(exc)))
            continue
        try:
            f, u, lt = scan_source(text, rel)
        except SyntaxError as exc:
            unparsed.append((rel, f"does not parse: {exc}"))
            continue
        findings.extend(f)
        unresolved.extend(u)
        let_through += lt

    shell, shell_tally = shell_enumerations(ROOT)

    print(f"read {len(corpus)} tracked .py files; {let_through} git call site(s) anchored or not "
          f"enumerating; {len(unresolved)} argv(s) unresolved; {len(unparsed)} unreadable")
    for rel, line, why in unresolved:
        if not args.quiet:
            print(f"    unresolved  {rel}:{line}  {why}")
    print("  " + shell_tally.line())
    print(f"declined: shell — {len(shell)} tracked .sh file(s) invoke an enumerating git "
          f"subcommand{':' if shell else '. The class is empty today.'}")
    for rel in shell:
        print(f"    {rel}")
    for rel, why in NOT_RUN_HERE:
        print(f"declined: per-run cost — {rel}: {why}")

    print()
    invariant_failures = []
    subdir = ROOT / "planning"
    if not subdir.is_dir():
        print("INCONCLUSIVE scope-invariance: planning/ is not a directory, so the invariant runs "
              "have no second working directory to use.")
        return 3
    for rel, why in INVARIANT_RUNS:
        script = ROOT / rel
        if not script.exists():
            invariant_failures.append((rel, "the instrument named in INVARIANT_RUNS is not there"))
            continue
        agreed, at_root, at_sub = run_twice(script, ROOT, subdir)
        verdict = "AGREED" if agreed else "MOVED"
        print(f"  invariant {verdict}  {rel}  root: {at_root} · planning/: {at_sub}")
        if not agreed:
            invariant_failures.append(
                (rel, f"answered differently from planning/ than from the repository root "
                      f"({at_root} vs {at_sub})"))

    if unparsed:
        print()
        for rel, why in unparsed:
            print(f"  unreadable  {rel}  {why}")
        print(f"INCONCLUSIVE scope-invariance: {len(unparsed)} file(s) could not be read, so this "
              f"run answers about {len(corpus) - len(unparsed)} of {len(corpus)}.")
        return 3

    if findings or invariant_failures:
        print()
        for rel, line, what, why in findings:
            print(f"  * {rel}:{line}  {what} — {why}")
        for rel, why in invariant_failures:
            print(f"  * {rel}  {why}")
        print(f"\nFINDINGS scope-invariance: {len(findings)} unanchored enumeration(s), "
              f"{len(invariant_failures)} instrument(s) whose answer moved with its cwd.")
        print("  Anchor the enumeration to a root the instrument derives itself — `git -C <root>` "
              "or `cwd=<root>` — and read the paths it returns relative to that same root.")
        return 1

    print(f"\nCLEAN scope-invariance: {len(corpus)} tracked .py files, 0 unanchored enumerations, "
          f"{len(INVARIANT_RUNS)} instrument(s) proved cwd-invariant by running them.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
