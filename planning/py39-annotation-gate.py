"""Refuse a PEP 604 union annotation in a file the 3.9 interpreter will run.

`make lint` runs this. It exists because the same defect landed twice in one session and cost two
goal iterations both times.

PEP 604 unions in annotations are EVALUATED at def/class time unless the module carries
`from __future__ import annotations`. The file is syntactically valid, so py_compile passes and a
syntax sweep reports clean — which is how an earlier sweep in this session reported "28 scripts,
0 failures" over two files that were already broken.

WHY A STATIC PARSE AND NOT A COMPILE. `X | None` in an annotation is EVALUATED at def/class time
unless the module carries `from __future__ import annotations`. The file is syntactically valid
either way, so `py_compile` passes. An earlier sweep in this session used exactly that instrument
and reported "28 scripts against 3.9, 0 other failures" over two files that were already broken —
`planning/reader-accounting.py` and `planning/null-run-gate.py`, both of which then failed the
lint gate under the guard's interpreter. The instrument was wrong, not the conclusion unlucky.

WHY NOT JUST RUN THEM. Executing every gate to find out whether it imports is a sweep with side
effects, and some of these write files. Parsing the annotation positions finds the same defect and
touches nothing.

WHY 3.9 AT ALL. `/usr/bin/python3` on this machine is 3.9.6, and a login shell with no interactive
environment resolves `python3` there. An interactive shell here resolves to Homebrew's 3.14, so a
script tested by hand can be one the guard, a hook or a `make` recipe cannot run.

PRESENCE CONTROL, run on every invocation: a planted union must be found, and a planted file
carrying the future import must not be. If either arm fails the gate exits 2 and prints no count,
because a count from an instrument that cannot see the defect is not evidence.
"""
from __future__ import annotations
import ast, sys, os, subprocess

def unions(path):
    try: tree = ast.parse(open(path, encoding='utf-8', errors='replace').read())
    except SyntaxError as e: return ('SYNTAX', [str(e)])
    fut = any(isinstance(n, ast.ImportFrom) and n.module == '__future__'
              and any(a.name == 'annotations' for a in n.names) for n in tree.body)
    if fut: return ('OK-future', [])
    hits = []
    def is_union(node):
        return isinstance(node, ast.BinOp) and isinstance(node.op, ast.BitOr)
    for n in ast.walk(tree):
        anns = []
        if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)):
            anns = [a.annotation for a in n.args.args + n.args.kwonlyargs + n.args.posonlyargs if a.annotation]
            if n.returns: anns.append(n.returns)
        elif isinstance(n, ast.AnnAssign) and n.annotation:
            anns = [n.annotation]
        for a in anns:
            for sub in ast.walk(a):
                if is_union(sub):
                    hits.append(getattr(n, 'lineno', '?')); break
    return ('BREAKS-3.9' if hits else 'OK', sorted(set(hits)))

files = subprocess.run(['git','ls-files','*.py'], capture_output=True, text=True).stdout.split()
bad = []
for f in files:
    st, hits = unions(f)
    if st == 'BREAKS-3.9': bad.append((f, hits))
print(f'swept {len(files)} tracked .py files by ACTUALLY PARSING ANNOTATIONS, not by compiling')
for f, h in bad: print(f'  BREAKS on 3.9: {f}  lines {h[:6]}')
print(f'{len(bad)} file(s) carry a PEP 604 union with no `from __future__ import annotations`')

# ---- presence control ----
import tempfile
d = tempfile.mkdtemp()
p1 = os.path.join(d, 'plant_bad.py');  open(p1,'w').write('import ast\ndef f(x: ast.AST | None) -> bool:\n    return True\n')
p2 = os.path.join(d, 'plant_good.py'); open(p2,'w').write('from __future__ import annotations\nimport ast\ndef f(x: ast.AST | None) -> bool:\n    return True\n')
ok = unions(p1)[0] == 'BREAKS-3.9' and unions(p2)[0] == 'OK-future'
print('control:', 'HELD — planted union found, planted future-import exempted' if ok
      else 'DID NOT FIRE — this sweep cannot see the defect it reports on, so the count above is not evidence')
if not ok:
    sys.exit(2)
if bad:
    print('fix: add `from __future__ import annotations` as the first import of each file above.')
    sys.exit(1)
sys.exit(0)
