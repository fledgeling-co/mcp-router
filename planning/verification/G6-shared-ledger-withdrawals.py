#!/usr/bin/env python3
"""Insert the five withdrawal markers `G6` could not write itself, into the two shared ledgers.

`G6` took `planning/foreign-path-gate.py` from 45 blocking citations to 5. The five that remain are
in `ORCHESTRATOR.md` and `planning/features-to-triage/LEDGER.md`, which the `ai/g6` runner was not
permitted to write — they are shared fleet state and a runner editing them collides with every
other runner. `G7`'s run hit the same wall from the other side: the two largest holders of bare
citations in that corpus are the same two files.

So the fix is written here rather than applied there, as a script rather than a patch, because a
patch against a 2000-line ledger row rots the moment anyone else edits it and this re-derives its
targets from the gate on every run.

Run it from the repository root, on a branch that is allowed to write those two files:

    python3 planning/verification/G6-shared-ledger-withdrawals.py          # report only
    python3 planning/verification/G6-shared-ledger-withdrawals.py --apply  # write

It is idempotent: a citation already carrying a marker is left alone, so a second run reports zero.
Afterwards `python3 planning/foreign-path-gate.py` exits 0.

What it inserts, and why the marker rather than a repair: none of the five artifacts survives. All
twelve cited families were probed on 2026-08-26 and none had a single surviving member, and the
reports record their instruments by counts rather than by content — so a reconstruction would be an
instrument built to return the numbers already written down, which is a worse claim than an honest
absence. `(gone)` is the true thing to say.

Note what the last two are. `LEDGER.md:81` is the `G6` row itself: the ledger entry that describes
the dead-path defect carries two dead-path citations of its own, unmarked. The defect reproduced
inside its own description, which is the clearest argument for the gate that either half of this
item makes.
"""

import argparse
import importlib.util
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
TARGETS = ("ORCHESTRATOR.md", "planning/features-to-triage/LEDGER.md")
PATHCHAR = set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.~+=*-/{")


def load_gate():
    path = ROOT / "planning" / "foreign-path-gate.py"
    spec = importlib.util.spec_from_file_location("fpg", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--apply", action="store_true", help="write the files; otherwise report only")
    args = ap.parse_args()

    fpg = load_gate()
    total = 0
    for rel in TARGETS:
        p = ROOT / rel
        if not p.exists():
            print("%-46s not present, skipped" % rel)
            continue
        raw = p.read_text()
        blocking = sorted(
            {h["token"] for h in fpg.scan_collapsed(rel, raw) if h["class"] in fpg.BLOCKING},
            key=len, reverse=True)
        if not blocking:
            print("%-46s already clean" % rel)
            continue
        fences = fpg.fenced_spans(raw)
        n = 0
        for tok in blocking:
            out, i = [], 0
            while True:
                j = raw.find(tok, i)
                if j < 0:
                    out.append(raw[i:]); break
                end = j + len(tok)
                if end < len(raw) and raw[end] in PATHCHAR:
                    out.append(raw[i:end]); i = end; continue
                if fpg.in_span(fences, j):
                    out.append(raw[i:end]); i = end; continue
                k = end
                while k < len(raw) and raw[k] in "`*":
                    k += 1
                nxt = fpg.SCRATCH.search(raw, k)
                stop = min(k + fpg.WINDOW, nxt.start() if nxt else len(raw))
                if fpg.WITHDRAW.search(re.sub(r"\s+", " ", raw[k:stop])):
                    out.append(raw[i:k]); i = k; continue
                out.append(raw[i:k]); out.append(" (gone)"); i = k; n += 1
            raw = "".join(out)
        print("%-46s %d marker(s) %s   %s"
              % (rel, n, "written" if args.apply else "would be inserted", ", ".join(blocking)))
        if args.apply and n:
            p.write_text(raw)
        total += n

    print("\n%d marker(s) %s" % (total, "written" if args.apply else "pending — re-run with --apply"))
    if not args.apply and total:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
