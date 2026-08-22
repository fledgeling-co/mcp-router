#!/usr/bin/env python3
"""Every raw-input reader in `planning/` and `scripts/` must account for what it drops.

G4's subject is an assertion named for a quantity that reads a different one, and the half of that
class this gate reaches is the silent drop: a reader takes N items from outside the process, keeps
M of them, and never says that N - M went missing. Its pass and its cannot-discriminate are then
indistinguishable, because the number it reports is a count of what it managed to parse rather than
a count of what it was given.

Three of the eight instances in `G4-assertions-that-do-not-read-their-own-quantity.md` are in one
file, `ledger-reconcile.py`, and all three were found the same way: that script prints
`H examined N rows ... skipped K with fewer cells than their header`, somebody read the second
number, and the drop stopped being invisible. Check J exists because H's skip list reads one
direction only. Check L exists because every table reader in the file drops a line that does not
begin with a pipe, and two merge-conflict blocks sat in the memory of record for a day behind
exactly that drop.

So the convention works and it is one script's habit. This turns it into a contract:

  A reader that discards part of its raw input either RECORDS what it discarded and reports it,
  or carries a written declaration in `planning/reader-accounting.tsv` saying what it drops and
  why that is not this reader's subject.

What this gate does NOT do, stated here rather than implied, because a gate that overstates its
reach is the defect wearing the fix's clothes:

  * It reaches Python only. 66 shell files under `scripts/` and `planning/` hold readers too, and
    a `grep | while read` pipeline has no syntax this gate can resolve. `null-run-gate.py` is the
    mechanism that reaches those.
  * It reaches the SILENT drop. Instances 2, 3, 7 and the `egress` one in that brief each read a
    real quantity that is the wrong one, with nothing dropped at all. They pass this gate, and
    they are still defects. Half that brief's table is out of scope for its own fix.
  * It resolves an iteration's subject syntactically, one binding deep. An iteration whose
    subject it cannot resolve is COUNTED AND NAMED as unresolved rather than assumed derived —
    the same rule the thing being gated is held to.

Exit 0 when every raw-input reader is accounted, declared or a recorded gap; 1 on a reader that
drops silently and says nothing; 2 when the gate measured nothing, which is not a pass.
"""

import ast
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REGISTRY = Path(__file__).resolve().parent / "reader-accounting.tsv"
SCANNED = ("planning", "scripts")

# ---------------------------------------------------------------------------------------------
# Where raw input enters a process. Deliberately short: a name is only "from outside" if it can be
# traced to one of these, and everything else is a container the program built for itself. A dict
# assembled from a file's lines is derived, not raw — its keys are the program's own vocabulary,
# and a check that treated it as raw would report the program's own filtering as a drop.
SOURCE_CALLS = {
    "open", "input",
    "read_text", "read_bytes", "readlines", "readline", "read",
    "glob", "rglob", "iterdir", "walk", "listdir", "scandir",
    "run", "Popen", "check_output", "getoutput", "communicate",
    "load", "loads",
}
SOURCE_ATTRS = {"stdin", "argv", "environ"}

# Methods that carry taint along a string without leaving string-space.
PROPAGATE = {
    "split", "splitlines", "strip", "rstrip", "lstrip", "lower", "upper", "replace", "casefold",
    "decode", "encode", "join", "format", "expandvars", "expanduser", "removeprefix",
    "removesuffix", "title", "get", "sub", "read", "readlines", "stdout", "stderr",
}

# The forms that decompose raw input into items. An iteration over one of these is a READER; an
# iteration over anything else is downstream of one and is not this gate's subject.
DECOMPOSE_ANY = {"open", "walk", "listdir", "scandir", "glob", "rglob", "iterdir",
                 "readlines", "load", "reader", "DictReader"}

# Four of those names mean something else in another module, and the difference is not a detail:
# `ast.walk` traverses a tree the program already holds and `os.walk` reads a filesystem. The first
# cut of this gate did not distinguish them, classified its own `for node in ast.walk(tree)` as a
# raw-input reader, and reported itself as one of the two accounting readers in the repository on
# the strength of it. A detector that guesses which module a bare name came from is the ambiguous
# binding the Google lane refused for name → quantity, one layer down.
MODULE_QUALIFIED = {
    "walk": {"os"},
    "load": {"json", "tomllib", "plistlib", "yaml", "pickle"},
    "reader": {"csv"},
    "DictReader": {"csv"},
}
DECOMPOSE_TAINTED = {"splitlines", "split", "finditer", "findall", "loads"}
WRAPPERS = {"enumerate", "sorted", "reversed", "list", "tuple", "set", "iter", "zip", "filter"}

# Statements that record a dropped item somewhere it can outlive the loop. `drop` is
# `input_accounting.Tally`'s own verb; the rest are what a reader that hand-rolls the same thing
# reaches for, and both are accepted because the contract is about the record, not the vehicle.
RECORD_METHODS = {"drop", "append", "add", "update", "extend", "setdefault", "write", "insert"}


class Taint:
    """Which names in one module hold something that came from outside the process."""

    def __init__(self, tree: ast.AST, seeds: set[str]):
        self.names = set(seeds)
        for _ in range(8):
            if not self._pass(tree):
                break

    def of(self, node: ast.AST | None) -> bool:
        if node is None:
            return False
        if isinstance(node, ast.Name):
            return node.id in self.names
        if isinstance(node, ast.Attribute):
            return node.attr in SOURCE_ATTRS or self.of(node.value)
        if isinstance(node, ast.Call):
            f = node.func
            name = f.attr if isinstance(f, ast.Attribute) else getattr(f, "id", None)
            if name in SOURCE_CALLS:
                return True
            if name in PROPAGATE and isinstance(f, ast.Attribute) and self.of(f.value):
                return True
            return any(self.of(a) for a in node.args)
        if isinstance(node, ast.Subscript):
            return self.of(node.value)
        if isinstance(node, ast.BinOp):
            return self.of(node.left) or self.of(node.right)
        if isinstance(node, ast.JoinedStr):
            return any(self.of(v) for v in node.values)
        if isinstance(node, ast.FormattedValue):
            return self.of(node.value)
        if isinstance(node, (ast.Tuple, ast.List, ast.Set)):
            return any(self.of(e) for e in node.elts)
        if isinstance(node, ast.IfExp):
            return self.of(node.body) or self.of(node.orelse)
        if isinstance(node, ast.Starred):
            return self.of(node.value)
        return False

    def _bind(self, target: ast.AST, tainted: bool) -> bool:
        if not tainted:
            return False
        changed = False
        for n in ast.walk(target):
            if isinstance(n, ast.Name) and n.id not in self.names:
                self.names.add(n.id)
                changed = True
        return changed

    def _pass(self, tree: ast.AST) -> bool:
        changed = False
        for n in ast.walk(tree):
            if isinstance(n, ast.Assign):
                for t in n.targets:
                    changed |= self._bind(t, self.of(n.value))
            elif isinstance(n, (ast.AnnAssign, ast.AugAssign)):
                changed |= self._bind(n.target, self.of(n.value))
            elif isinstance(n, (ast.For, ast.AsyncFor)):
                changed |= self._bind(n.target, self.of(n.iter))
            elif isinstance(n, ast.With):
                for item in n.items:
                    if item.optional_vars is not None:
                        changed |= self._bind(item.optional_vars, self.of(item.context_expr))
            elif isinstance(n, (ast.ListComp, ast.SetComp, ast.DictComp, ast.GeneratorExp)):
                for g in n.generators:
                    changed |= self._bind(g.target, self.of(g.iter))
        return changed


def seed_params(tree: ast.AST) -> set[str]:
    """Parameter names that some call site in this module hands raw input to.

    `ledger-reconcile.py`'s readers take `text: str` and are called with a file's contents, so a
    module-local taint that stopped at the call boundary would classify none of them. Iterated to
    a fixpoint because one reader's parameter feeds the next reader's call.
    """
    funcs = {n.name: n for n in ast.walk(tree)
             if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))}
    seeds: set[str] = set()
    for _ in range(6):
        taint = Taint(tree, seeds)
        grown = set(seeds)
        for n in ast.walk(tree):
            if not (isinstance(n, ast.Call) and isinstance(n.func, ast.Name)):
                continue
            fn = funcs.get(n.func.id)
            if fn is None:
                continue
            params = [a.arg for a in fn.args.posonlyargs + fn.args.args]
            for i, arg in enumerate(n.args):
                if i < len(params) and taint.of(arg):
                    grown.add(params[i])
        if grown == seeds:
            break
        seeds = grown
    return seeds


def call_name(node: ast.AST) -> str | None:
    if not isinstance(node, ast.Call):
        return None
    f = node.func
    return f.attr if isinstance(f, ast.Attribute) else getattr(f, "id", None)


def raw_subject(node: ast.AST, bindings: dict[str, list[ast.AST]], taint: Taint,
                depth: int = 0) -> str | None:
    """What raw input this iteration decomposes, or None when it decomposes none.

    Syntactic, and one unambiguous binding deep. A name assigned twice resolves to nothing rather
    than to a guess — under-claiming is the safe direction for a gate whose finding is "you did not
    say what you dropped", and the count of what it could not resolve is printed on every run so
    the under-claim is visible rather than absorbed.
    """
    if depth > 4 or node is None:
        return None
    if isinstance(node, ast.Call):
        name = call_name(node)
        if name in WRAPPERS and node.args:
            return raw_subject(node.args[0], bindings, taint, depth + 1)
        if name in DECOMPOSE_ANY:
            allowed = MODULE_QUALIFIED.get(name)
            if allowed is not None:
                owner = node.func.value if isinstance(node.func, ast.Attribute) else None
                if not (isinstance(owner, ast.Name) and owner.id in allowed) \
                        and not any(taint.of(a) for a in node.args):
                    return None
                return f"{getattr(owner, 'id', '')}.{name}(...)".lstrip(".")
            return f"{name}(...)"
        if name in DECOMPOSE_TAINTED:
            f = node.func
            if isinstance(f, ast.Attribute) and taint.of(f.value):
                return f"{ast.unparse(f.value)[:40]}.{name}()"
            if any(taint.of(a) for a in node.args):
                return f"{name}() over input"
        return None
    if isinstance(node, ast.Name):
        bound = bindings.get(node.id, [])
        if len(bound) != 1:
            return None
        return raw_subject(bound[0], bindings, taint, depth + 1)
    if isinstance(node, ast.Attribute) and node.attr in ("stdin",):
        return "sys.stdin"
    return None


def scope_bindings(scope: ast.AST) -> dict[str, list[ast.AST]]:
    """Every value each local name is assigned, so a single-binding name can be followed."""
    out: dict[str, list[ast.AST]] = {}
    for n in ast.walk(scope):
        if isinstance(n, ast.Assign):
            for t in n.targets:
                if isinstance(t, ast.Name):
                    out.setdefault(t.id, []).append(n.value)
        elif isinstance(n, ast.AnnAssign) and isinstance(n.target, ast.Name) and n.value:
            out.setdefault(n.target.id, []).append(n.value)
        elif isinstance(n, ast.With):
            for item in n.items:
                if isinstance(item.optional_vars, ast.Name):
                    out.setdefault(item.optional_vars.id, []).append(item.context_expr)
    return out


def bound_inside(node: ast.AST) -> set[str]:
    names = set()
    for n in ast.walk(node):
        if isinstance(n, (ast.For, ast.AsyncFor)):
            for t in ast.walk(n.target):
                if isinstance(t, ast.Name):
                    names.add(t.id)
        elif isinstance(n, ast.Assign):
            for t in n.targets:
                for x in ast.walk(t):
                    if isinstance(x, ast.Name):
                        names.add(x.id)
    return names


def mentions(node: ast.AST | None, local: set[str]) -> bool:
    """Whether an expression names something bound inside the loop — the item itself."""
    if node is None:
        return False
    return any(isinstance(n, ast.Name) and n.id in local for n in ast.walk(node))


def records(stmt: ast.AST, local: set[str]) -> str | None:
    """The name this statement records the DROPPED ITEM into, when that name outlives the loop.

    The recorded value must mention the item. A bare `examined += 1` at the top of a loop satisfies
    a rule that only asks whether some escaping name was touched, and it is exactly the thing this
    gate exists to refuse: a number that moves whether or not the drop happened, standing in for a
    record of what went missing. The first cut of this function accepted it, and the gate then
    reported itself as the one accounting reader in the repository on the strength of an unrelated
    counter two lines above a `continue`. `dropped` in the contract is a set of items, not a count.
    """
    target = value = None
    if isinstance(stmt, ast.Expr) and isinstance(stmt.value, ast.Call):
        f = stmt.value.func
        if isinstance(f, ast.Attribute) and f.attr in RECORD_METHODS:
            target = f.value
            value = ast.Tuple(elts=list(stmt.value.args)
                              + [k.value for k in stmt.value.keywords], ctx=ast.Load())
    elif isinstance(stmt, ast.AugAssign):
        target, value = stmt.target, stmt.value
    elif isinstance(stmt, ast.Assign) and isinstance(stmt.targets[0], ast.Subscript):
        target = stmt.targets[0].value
        value = ast.Tuple(elts=[stmt.targets[0].slice, stmt.value], ctx=ast.Load())
    if target is None or not mentions(value, local):
        return None
    base = target
    while True:
        if isinstance(base, ast.Call) and isinstance(base.func, ast.Attribute):
            # `self.extra_allowed.setdefault(state, {})[k] = v` records into `self.extra_allowed`,
            # and a walker that stops at the call reports a real record as a silent drop.
            base = base.func.value
        elif isinstance(base, ast.Subscript):
            base = base.value
        elif isinstance(base, ast.Attribute):
            if isinstance(base.value, ast.Name):
                return ast.unparse(base)  # `self.citations` — instance state outlives the loop
            base = base.value
        else:
            break
    if not isinstance(base, ast.Name):
        return None
    return None if base.id in local else base.id


def escapes(name: str, scope: ast.AST) -> bool:
    """Whether a recorded drop can be read outside the loop that recorded it.

    A counter nobody returns, prints or yields is the silent drop with an extra step: the number
    exists and no reader of the output can see it. `status_rows` passes this because it returns
    `skipped` and `main` prints the list; a version that counted into a local and dropped it on the
    floor would not, and should not.
    """
    if name.startswith("self."):
        return True
    for n in ast.walk(scope):
        if isinstance(n, (ast.Return, ast.Yield, ast.YieldFrom)) and n.value is not None:
            if any(isinstance(x, ast.Name) and x.id == name for x in ast.walk(n.value)):
                return True
        if isinstance(n, ast.Call) and getattr(n.func, "id", None) in ("print", "report", "fail"):
            for a in list(n.args) + [k.value for k in n.keywords]:
                if any(isinstance(x, ast.Name) and x.id == name for x in ast.walk(a)):
                    return True
        if isinstance(n, (ast.Global, ast.Nonlocal)) and name in n.names:
            return True
    return False


class Reader:
    """One function (or one module's top level) that decomposes raw input and discards some of it."""

    def __init__(self, key: str, scope_name: str):
        self.key = key
        self.scope = scope_name
        self.subjects: list[str] = []
        self.lines: list[int] = []
        self.recorded = 0
        self.silent: list[str] = []

    @property
    def accounts(self) -> bool:
        return not self.silent


def enclosing(node: ast.AST, parents: dict[int, ast.AST]) -> tuple[ast.AST | None, str]:
    """The function a node sits in, and its dotted name; `<module>` at the top level."""
    names: list[str] = []
    scope = None
    cur = parents.get(id(node))
    while cur is not None:
        if isinstance(cur, (ast.FunctionDef, ast.AsyncFunctionDef)):
            names.append(cur.name)
            if scope is None:
                scope = cur
        elif isinstance(cur, ast.ClassDef):
            names.append(cur.name)
        cur = parents.get(id(cur))
    return scope, ".".join(reversed(names)) or "<module>"


def discard_sites(loop: ast.AST) -> list[ast.Continue]:
    """Every `continue` whose nearest enclosing loop is this one."""
    out = []
    def walk(node, inner):
        for child in ast.iter_child_nodes(node):
            if isinstance(child, ast.Continue) and not inner:
                out.append(child)
            elif isinstance(child, (ast.For, ast.AsyncFor, ast.While)):
                walk(child, True)
            else:
                walk(child, inner)
    walk(loop, False)
    return out


def path_to(target: ast.AST, block: list[ast.AST]) -> list[list[ast.AST]] | None:
    """The chain of statement blocks leading to `target`, outermost first."""
    for i, stmt in enumerate(block):
        if stmt is target:
            return [block[:i]]
        for field in ("body", "orelse", "finalbody"):
            sub = getattr(stmt, field, None)
            if isinstance(sub, list):
                deeper = path_to(target, sub)
                if deeper is not None:
                    return [block[:i]] + deeper
        for handler in getattr(stmt, "handlers", []):
            deeper = path_to(target, handler.body)
            if deeper is not None:
                return [block[:i]] + deeper
    return None


def analyse_file(path: Path, rel: str) -> tuple[dict[str, Reader], int, int, list[str]]:
    src = path.read_text(encoding="utf-8", errors="replace")
    tree = ast.parse(src)
    parents = {}
    for node in ast.walk(tree):
        for child in ast.iter_child_nodes(node):
            parents[id(child)] = node
    taint = Taint(tree, seed_params(tree))

    readers: dict[str, Reader] = {}
    iterations = 0
    discarding = 0
    unresolved: list[str] = []

    def reader_for(node) -> Reader:
        scope, name = enclosing(node, parents)
        key = f"{rel}::{name}"
        if key not in readers:
            readers[key] = Reader(key, name)
        return readers[key]

    for node in ast.walk(tree):
        if isinstance(node, (ast.For, ast.AsyncFor)):
            iterations += 1
            sites = discard_sites(node)
            if not sites:
                continue
            discarding += 1
            scope, _ = enclosing(node, parents)
            subject = raw_subject(node.iter, scope_bindings(scope or tree), taint)
            if subject is None:
                unresolved.append(f"{rel}:{node.lineno} for … in {ast.unparse(node.iter)[:52]}")
                continue
            reader = reader_for(node)
            reader.subjects.append(subject)
            reader.lines.append(node.lineno)
            local = bound_inside(node)
            for site in sites:
                blocks = path_to(site, node.body) or []
                name = next((r for block in blocks for stmt in block
                             if (r := records(stmt, local)) and escapes(r, scope or tree)), None)
                if name:
                    reader.recorded += 1
                else:
                    reader.silent.append(f"{rel}:{site.lineno} continue")
        elif isinstance(node, (ast.ListComp, ast.SetComp, ast.DictComp, ast.GeneratorExp)):
            iterations += 1
            if not any(g.ifs for g in node.generators):
                continue
            discarding += 1
            scope, _ = enclosing(node, parents)
            bindings = scope_bindings(scope or tree)
            subject = next((s for g in node.generators
                            if g.ifs and (s := raw_subject(g.iter, bindings, taint))), None)
            if subject is None:
                unresolved.append(f"{rel}:{node.lineno} comprehension over "
                                  f"{ast.unparse(node.generators[0].iter)[:44]}")
                continue
            reader = reader_for(node)
            reader.subjects.append(subject)
            reader.lines.append(node.lineno)
            # A comprehension has nowhere to record a drop: the filtered item leaves no trace by
            # construction. So one over raw input is silent by shape, and its declaration in the
            # registry is the only place its drop can be written down.
            reader.silent.append(f"{rel}:{node.lineno} comprehension filter")

    return readers, iterations, discarding, unresolved


def read_registry() -> tuple[dict[str, tuple[str, str]], list[str], int]:
    """The declarations, the rows this reader could not parse, and the row count it was pinned to.

    This gate is itself a reader, so it accounts for its own input on the same terms it imposes:
    a malformed row is named rather than skipped, and the pinned `# rows:` header makes a row
    silently disappearing a red instead of a smaller denominator.
    """
    declared: dict[str, tuple[str, str]] = {}
    malformed: list[str] = []
    pinned = -1
    if not REGISTRY.is_file():
        return declared, ["registry file is missing"], pinned
    for n, line in enumerate(REGISTRY.read_text(encoding="utf-8").splitlines(), 1):
        if line.startswith("# rows:"):
            pinned = int(line.split(":", 1)[1].strip())
            continue
        if not line.strip() or line.startswith("#"):
            continue
        cells = line.split("\t")
        if len(cells) != 3:
            malformed.append(f"line {n}: {len(cells)} tab-separated cells, expected 3")
            continue
        key, disposition, reason = (c.strip() for c in cells)
        if disposition not in ("declared", "gap"):
            malformed.append(f"line {n}: disposition {disposition!r} is neither declared nor gap")
            continue
        if not reason:
            malformed.append(f"line {n}: {key} carries no reason")
            continue
        if key in declared:
            malformed.append(f"line {n}: {key} is declared twice")
            continue
        declared[key] = (disposition, reason)
    return declared, malformed, pinned


def main() -> int:
    files = sorted(p for d in SCANNED for p in (ROOT / d).rglob("*.py")
                   if "node_modules" not in p.parts)
    if not files:
        print("usage error: no Python files found under "
              f"{', '.join(SCANNED)} — the gate did not run", file=sys.stderr)
        return 2

    readers: dict[str, Reader] = {}
    iterations = discarding = 0
    unresolved: list[str] = []
    unparsed: list[str] = []
    for path in files:
        rel = str(path.relative_to(ROOT))
        try:
            found, it, disc, unres = analyse_file(path, rel)
        except (SyntaxError, ValueError, RecursionError) as exc:
            unparsed.append(f"{rel}: {exc}")
            continue
        readers.update(found)
        iterations += it
        discarding += disc
        unresolved += unres

    declared, malformed, pinned = read_registry()

    accounted = sorted(k for k, r in readers.items() if r.accounts)
    silent = sorted(k for k, r in readers.items() if not r.accounts)
    covered = [k for k in silent if k in declared]
    findings = [k for k in silent if k not in declared]
    stale = sorted(k for k in declared if k not in silent)
    gaps = sorted(k for k in covered if declared[k][0] == "gap")

    print("reader-accounting — raw-input readers in " + " and ".join(f"{d}/" for d in SCANNED))
    print()
    print(f"  files        {len(files):4d} Python files, {len(unparsed)} unparsed")
    print(f"  iterations   {iterations:4d} examined; {discarding} discard at least one item")
    print(f"  subject      {len(unresolved):4d} discarding iterations decompose no raw input this "
          f"gate can resolve")
    print(f"  readers      {len(readers):4d} raw-input readers over "
          f"{sum(len(r.subjects) for r in readers.values())} discarding iterations")
    sites = sum(r.recorded + len(r.silent) for r in readers.values())
    kept = sum(r.recorded for r in readers.values())
    print(f"  drop sites   {sites:4d} places a reader discards an item; {kept} name what they "
          f"dropped, {sites - kept} do not")
    print()
    print(f"  accounts     {len(accounted):4d} record every drop into something they return, "
          f"print or yield")
    print(f"  declared     {len(covered) - len(gaps):4d} drop by design, with a written reason")
    print(f"  gap          {len(gaps):4d} drop silently and are recorded as known gaps")
    print(f"  unaccounted  {len(findings):4d} drop silently and say nothing")
    print()

    if iterations == 0 or not readers:
        print("usage error: the gate resolved no raw-input readers at all. The detector stopped "
              "matching; a gate that never ran is not a gate that passed.", file=sys.stderr)
        return 2

    if unresolved:
        by_file: dict[str, int] = {}
        for u in unresolved:
            by_file[u.split(":", 1)[0]] = by_file.get(u.split(":", 1)[0], 0) + 1
        print(f"Subjects this gate could not resolve to raw input ({len(unresolved)}), by file. "
              "Each is a discarding")
        print("iteration this gate says nothing about, printed for the same reason it demands a "
              "skip list of")
        print("everything else. `--unresolved` names them individually:")
        for name, count in sorted(by_file.items(), key=lambda kv: (-kv[1], kv[0])):
            print(f"  {count:3d}  {name}")
        if "--unresolved" in sys.argv:
            print()
            for u in unresolved:
                print(f"       {u}")
        print()

    if gaps:
        print(f"Known gaps ({len(gaps)}) — silent drops recorded rather than fixed. The gate is "
              "green over the readers it")
        print("can account for and these are not among them:")
        for k in gaps:
            print(f"  {k}\n    {declared[k][1]}")
        print()

    problems: list[str] = []
    if unparsed:
        problems.append("files this gate could not parse, so their readers were never examined:\n"
                        + "\n".join(f"    {u}" for u in unparsed))
    if malformed:
        problems.append("rows in reader-accounting.tsv this gate could not read:\n"
                        + "\n".join(f"    {m}" for m in malformed))
    if pinned >= 0 and pinned != len(declared):
        problems.append(f"reader-accounting.tsv declares {len(declared)} readers against a pinned "
                        f"`# rows: {pinned}`. A row that vanishes shrinks the denominator and the\n"
                        "    gate reports better; move the pin in the same change as the row.")
    if stale:
        problems.append("declared readers that no longer drop anything the gate can see — the "
                        "declaration outlived its reader:\n"
                        + "\n".join(f"    {k}: {declared[k][1][:70]}" for k in stale))
    if findings:
        problems.append(f"{len(findings)} reader(s) discard raw input and record nothing:\n"
                        + "\n".join(f"    {k}\n      drops at " + ", ".join(readers[k].silent)
                                    for k in findings))

    if not problems:
        n_gap = len(gaps)
        print(f"accounted — {len(accounted)} readers record their drops, "
              f"{len(covered) - n_gap} declare them, {n_gap} "
              f"{'is a recorded gap' if n_gap == 1 else 'are recorded gaps'}.")
        print("This gate reaches the SILENT drop in Python only. A reader that reads a real "
              "quantity that is the")
        print("wrong one drops nothing and passes here; so do all 66 shell readers under "
              "planning/ and scripts/.")
        return 0
    for p in problems:
        print(f"  {p}\n")
    print("Record the drop (return or print what you discarded) or declare it in "
          "planning/reader-accounting.tsv")
    print("with a reason saying why it is not this reader's subject.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
