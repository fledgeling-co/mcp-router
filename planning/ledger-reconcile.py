#!/usr/bin/env python3
"""Reconcile `planning/features-to-triage/LEDGER.md` against `ORCHESTRATOR.md`.

Two files record the same ids and neither is the authority its header claims to be.
On 2026-08-21 that cost two sessions in one hour: one allocated `I6` for a new brief
while it was already merged at `ef4f615`, and the other nearly filled the `X4`/`X5`
gap while both were merged branches. Neither could see it, because an id can be
absent from one file, present only in the other's prose, or hidden inside a range.

Four independent checks, because each is blind to the others:

  A  a row in ORCHESTRATOR.md with no LEDGER row     — a triage run re-allocates a
                                                       shipped id
  B  a row in LEDGER.md with no ORCHESTRATOR mention — a resuming fleet re-plans
                                                       work that already merged
  C  an id named only in prose, never in a table row — an allocator scans the table,
                                                       so prose does not protect it
  D  an allocation note's range covering a live id   — reads clean in A, B and C, and
                                                       nothing fires

`M11` is the worked example of D: it is merged at `2a434b9`, and a note reading
"M9-M12 are unused" absorbed it. A membership check that expands ranges reports it
reconciled; one that does not, reports it missing. Both are wrong, so D is reported
separately rather than folded into either.

There is deliberately no `--fix`. Which file is right is a judgement about what
shipped, and a script that guesses would write the next false note.

Exit 0 clean, 1 on any finding, 2 on a usage error.
"""

import re
import subprocess
import sys
from pathlib import Path

# The id series this pipeline allocates. `D-<parent>-<letter>` deferred children and
# `R1-D3`-style defect ids are NOT allocations and are excluded below.
SERIES = r"(?:F|R|M|I|P|D|G|V|X)"
ID = re.compile(rf"(?<![A-Za-z0-9])({SERIES}\d+(?:-[A-Z]\d*)?)(?![0-9])")
RANGE = re.compile(rf"({SERIES})(\d+)\s*[–—-]\s*({SERIES})?(\d+)")

# Ids that look like allocations and are not. Mutation ids share the M prefix and run
# to M57; `D1-D7` appears in prose about a spec's own table.
NOT_ALLOCATIONS = {f"M{n}" for n in range(50, 100)}


def table_ids(text: str) -> set[str]:
    """Ids in the first cell of a markdown table row — what an allocator scans."""
    found = set()
    for line in text.split("\n"):
        if not line.startswith("| "):
            continue
        cell = line.split("|")[1].strip().replace("**", "").replace("~~", "").strip()
        m = re.fullmatch(rf"{SERIES}\d+(?:-[A-Z]\d*)?", cell)
        if m:
            found.add(cell)
    return found - NOT_ALLOCATIONS


# Stopwords for check F. The bar is deliberately low — see the comment on `describes`.
FILLER = {
    "the", "a", "an", "and", "or", "but", "of", "to", "for", "in", "on", "at", "by", "with",
    "is", "it", "its", "that", "this", "not", "no", "every", "all", "any", "one", "two",
    "from", "into", "than", "then", "when", "which", "who", "what", "does", "do", "did",
    "be", "been", "was", "were", "are", "as", "has", "have", "had", "can", "cannot", "s",
}

def describes(text: str, source: str) -> dict[str, list[tuple[str, str]]]:
    """Every table row's description cell, keyed by the id in the first cell.

    This is what an allocator reads to decide whether an id is the item it means. Checks A
    and B ask only whether an id APPEARS in both files; they cannot see two different items
    wearing one id, because both files having a row satisfies membership. Identity drifts
    separately from membership, the same way status does.

    A **list** per id, not one entry, and that is the whole correctness of check F. The first
    version of this returned one row per file via `setdefault` and missed a live collision on
    its first run: `ORCHESTRATOR.md` carries two `R6` rows — the child-PATH item in the wave
    table and a router-side eval runner in the deferred register — and the row that agreed
    with LEDGER was simply the earlier one. A collision inside a single file is the same
    defect as one across two, and a check that reads one row per file cannot see it.
    """
    out: dict[str, list[tuple[str, str]]] = {}
    for line in text.split("\n"):
        if not line.startswith("| "):
            continue
        cells = line.split("|")
        if len(cells) < 3:
            continue
        cell = cells[1].strip().replace("**", "").replace("~~", "").strip()
        if not re.fullmatch(rf"{SERIES}\d+(?:-[A-Z]\d*)?", cell) or cell in NOT_ALLOCATIONS:
            continue
        out.setdefault(cell, []).append((source, cells[2].strip()))
    return out

def status_rows(
    text: str,
) -> tuple[dict[str, list[tuple[int, str]]], list[tuple[int, str]]]:
    """Every table row's Status cell, keyed by id, indexed by the column's HEADER name.

    Positional indexing would be wrong here. This file has one 9-column table carrying a
    `Status` column and a 4-column deferred register that carries none, and a row from the
    second read positionally yields whatever happens to sit at that offset. So each row is
    matched against its nearest preceding header, and an id whose only second row lives in a
    table with no Status column is left alone rather than compared against a cell that means
    something else — which is what keeps M11 out of this check and R4-C in it.

    A row with MORE cells than the header is still placed, and correctly: a stray `|` inside a
    cell shifts only the cells after it, so every column before the offending pipe keeps its
    index. `D3` is the live case — 11 cells against a 9-column header, `Status` still landing on
    `**Merged**`.

    A row with FEWER cells is skipped, and the skip is **counted and named** rather than
    dropped. That is the whole reason this returns a second value. A check that quietly discards
    the rows it cannot parse reports clean over a subset, which is the same denominator failure
    as a campaign publishing a pass rate over the surfaces it happened to reach. This file has 23
    four-cell deferred-child rows interleaved in the nine-column table with no header of their
    own; none can disagree about a status it has no cell for, but an instrument that says nothing
    about half its input has not earned the word clean.
    """
    out: dict[str, list[tuple[int, str]]] = {}
    skipped: list[tuple[int, str]] = []
    header: list[str] = []
    lines = text.split("\n")
    for n, line in enumerate(lines, 1):
        if re.match(r"^\|[\s:\-]+\|", line) and n >= 2:
            header = [c.strip().lower() for c in lines[n - 2].split("|")][1:-1]
            continue
        if not line.startswith("| ") or "status" not in header:
            continue
        cells = [c.strip() for c in line.split("|")][1:-1]
        if len(cells) < len(header):
            skipped.append((n, cells[0].replace("**", "").replace("~~", "").strip() if cells else ""))
            continue
        idc = cells[0].replace("**", "").replace("~~", "").strip()
        if not re.fullmatch(rf"{SERIES}\d+(?:-[A-Z]\d*)?", idc) or idc in NOT_ALLOCATIONS:
            continue
        out.setdefault(idc, []).append((n, cells[header.index("status")]))
    return out, skipped

# The lifecycle states a status cell can name, most specific first. Check I compares STATE,
# never wording: the two files legitimately phrase one status differently — ORCHESTRATOR
# writes "**Merged** `cbe5cc3`" where LEDGER writes "**Done** — merged to `main` at `cbe5cc3`" —
# and a check that compared strings would flood on that difference while a check that compared
# nothing would miss the one that matters. What must never differ is whether the item shipped.
STATES = [
    (r"needs more work", "needs-more-work"),
    (r"needs input", "needs-input"),
    (r"superseded", "superseded"),
    (r"retired", "retired"),
    (r"\bheld\b", "held"),
    (r"\bmerged\b|\bdone\b", "shipped"),
    # "Ready to verify" must be tested BEFORE "verified": it is the state every item passes
    # through on its way to Done, and `\bverified\b` does not match "verify", so before this
    # row existed the check that is named for currency read nothing at all for the one moment
    # the two files are most likely to disagree. It announced the skip rather than passing
    # silently, which is the only reason it was cheap to find.
    (r"ready to verify|ready for verification", "ready-to-verify"),
    (r"ready to merge|\bverified\b", "verified"),
    (r"in progress|dispatched", "in-progress"),
    (r"ready for ai", "ready-for-ai"),
    (r"\bto do\b", "to-do"),
    (r"untriaged", "untriaged"),
    (r"deferred", "deferred"),
    (r"\bblocked\b", "blocked"),
]


def lifecycle(cell: str) -> str | None:
    """The coarse state a status cell names, or None when nothing matches.

    Only the cell's HEAD is read — everything up to the first em-dash, bracket, semicolon or
    comma. A status cell routinely goes on to describe the state of OTHER ids, and matching
    anywhere in it makes those descriptions the row's own status. Measured on this repository
    the first time this check ran: R4-C's `**Superseded — split into R4-C1 (Done) and R4-C2
    (Held)**` classified as `shipped` on its child's `(Done)`, and LEDGER's `Blocked — … R4-C1
    shipped, R4-C2 held` classified as `blocked`, so the check reported a disagreement between
    two rows that say the same thing. A predicate that fires on a correct use is a detector
    defect whatever it is aimed at, and three of that run's four flags were this one bug.

    None is returned rather than guessed, and the caller counts and names every None. An
    unclassifiable cell is a cell this check did not read, and a check that treats what it
    could not read as agreement reports clean over a subset — the same denominator failure
    check H's skip list exists to prevent one file lower down.
    """
    head = re.split(r"[—(;,]", cell.replace("**", "").strip(), maxsplit=1)[0].lower()
    for pat, state in STATES:
        if re.search(pat, head):
            return state
    return None


def content_words(text: str) -> set[str]:
    text = QUOTED.sub(" ", text).replace("~~", " ").replace("**", " ")
    words = re.findall(r"[A-Za-z][A-Za-z'-]+", text.lower())
    return {w for w in words if w not in FILLER and len(w) > 2}

def named_ids(text: str) -> set[str]:
    """Every id the file names anywhere — table, prose, changelog."""
    return {m.group(1) for m in ID.finditer(text)} - NOT_ALLOCATIONS


# An allocation note is prose asserting that ids are free or taken. Only those ranges
# make a claim a later allocator acts on; `spec-R4.md's prose D-table lists only D1-D7`
# is a sentence about a different table and must not be read as one.
# Only a claim that ids are FREE misleads an allocator. A note saying ids are *taken* is
# consistent with their having rows, and an earlier version of this pattern fired on both
# — reporting `M15-M22 were allocated together` as a defect the moment those rows landed.
# A predicate that fires on a correct use is a detector defect, whatever it is aimed at.
QUOTED = re.compile(r"\u201c[^\u201d]*\u201d|\"[^\"]*\"|`[^`]*`")

CLAIMS_FREE = re.compile(
    r"unused|never allocated|not allocated|are free|jumps from|filling the gap",
    re.IGNORECASE,
)


def expand_range(text: str) -> set[str]:
    """Every id `M9-M12` notation reaches.

    A commit range and a two-series pair are not ranges; a span wider than 40 is a
    count or a line reference rather than an allocation.
    """
    found = set()
    for m in RANGE.finditer(text):
        prefix, low, other, high = m.group(1), int(m.group(2)), m.group(3), int(m.group(4))
        if other and other != prefix:
            continue
        if high < low or high - low > 40:
            continue
        found |= {f"{prefix}{n}" for n in range(low, high + 1)}
    return found - NOT_ALLOCATIONS


def range_ids(text: str) -> set[str]:
    """Ids a range reaches anywhere in the file."""
    return expand_range(text)


def allocation_claim_ids(text: str) -> set[str]:
    """Ids covered by a range inside a sentence claiming they are free.

    This is the M11 case: `M9-M12 are unused` covers an id merged at `2a434b9`, and
    every membership check reads it as reconciled because the range absorbed it.
    """
    # A note that quotes the false claim it is correcting must not trip the check that found
    # it. `ShellDetailWidthTests` records the same trap the other way round — a source grep
    # satisfied by the doc comment three lines above it — and the fix is the same: match the
    # assertion, not the explanation of a withdrawn one.
    #
    # Stripped over the WHOLE text rather than line by line, because the quote that caused
    # this opens on one line and closes on the next, and a per-line strip cannot close it.
    # The cost is that an unbalanced quote pairs with the next one and over-strips, which
    # hides findings rather than inventing them — the dangerous direction. `quote_balance`
    # below reports it rather than letting it pass silently.
    found = set()
    for line in QUOTED.sub(" ", text).split("\n"):
        if CLAIMS_FREE.search(line):
            found |= expand_range(line)
    return found


def quote_balance(text: str) -> list[str]:
    """Unbalanced quote characters, which make `allocation_claim_ids` strip too much."""
    problems = []
    for name, ch in (("straight double", '"'), ("backtick", "`")):
        if text.count(ch) % 2:
            problems.append(f"odd number of {name} quotes ({text.count(ch)}) — "
                            "check D may be stripping more than one quoted span")
    if text.count("\u201c") != text.count("\u201d"):
        problems.append("curly quotes do not pair — check D may be stripping too much")
    return problems


def merged_branches(root: Path) -> dict[str, str]:
    """id -> branch, for `ai/*` branches that are ancestors of main.

    A merged branch is the hardest evidence an id is taken: it survives both files
    being wrong, which is the case this script exists for.
    """
    try:
        out = subprocess.run(
            ["git", "-C", str(root), "branch", "--merged", "main", "--list", "ai/*",
             "--format=%(refname:short)"],
            capture_output=True, text=True, timeout=30,
        )
    except (OSError, subprocess.SubprocessError):
        return {}
    if out.returncode != 0:
        return {}
    found = {}
    for branch in out.stdout.split():
        stem = branch.split("/", 1)[1]
        m = re.fullmatch(r"([a-z]+)(\d+)([a-z]\d*)?", stem)
        if m:
            key = f"{m.group(1).upper()}{m.group(2)}"
            if m.group(3):
                key += f"-{m.group(3).upper()}"
            found[key] = branch
    return found


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    ledger_path = root / "planning" / "features-to-triage" / "LEDGER.md"
    orch_path = root / "ORCHESTRATOR.md"
    for p in (ledger_path, orch_path):
        if not p.is_file():
            print(f"usage error: {p} does not exist", file=sys.stderr)
            return 2

    ledger = ledger_path.read_text(encoding="utf-8", errors="replace")
    orch = orch_path.read_text(encoding="utf-8", errors="replace")

    l_table, o_table = table_ids(ledger), table_ids(orch)
    l_named, o_named = named_ids(ledger), named_ids(orch)
    l_range, o_range = range_ids(ledger), range_ids(orch)
    branches = merged_branches(root)

    findings: list[tuple[str, str, list[str]]] = []

    a = sorted(o_table - l_named)
    if a:
        findings.append(("A", "in ORCHESTRATOR's table, LEDGER never names it "
                              "(a triage run can re-allocate a shipped id)", a))

    b = sorted(l_table - o_named - o_range)
    if b:
        findings.append(("B", "in LEDGER's table, ORCHESTRATOR never names it at all "
                              "(a resuming fleet re-plans merged work)", b))

    b_range = sorted((l_table & o_range) - o_named)
    if b_range:
        findings.append(("B-range", "in LEDGER's table; ORCHESTRATOR reaches it only "
                                    "inside a range row, so it has no status of its own", b_range))

    c = sorted((l_named - l_table) & o_table)
    if c:
        findings.append(("C", "named only in LEDGER's prose, never a row "
                              "(an allocator scans rows, so prose does not protect it)", c))

    live = o_table | set(branches)
    d = sorted(allocation_claim_ids(ledger) & live)
    if d:
        findings.append(("D", "an allocation note's range calls an id free while it is "
                              "recorded live elsewhere (reads clean in A, B and C)",
                         [f"{i} ({branches.get(i, 'ORCHESTRATOR row')})" for i in d]))

    e = sorted(k for k in branches if k not in l_table and k not in o_table)
    if e:
        findings.append(("E", "a branch merged into main with no row in either file "
                              "(the id is spent and both files say it is free)",
                         [f"{k} ({branches[k]})" for k in e]))

    print(f"LEDGER        {len(l_table):3d} rows, {len(l_named):3d} named")
    print(f"ORCHESTRATOR  {len(o_table):3d} rows, {len(o_named):3d} named")
    print(f"merged ai/*   {len(branches):3d} branches")
    for problem in quote_balance(ledger):
        print(f"  warning: LEDGER.md {problem}")
    print()
    # F — one id, two different items. Reported only when the two description cells share
    # NO content word at all. A legitimately reworded row almost always keeps its subject
    # noun, so demanding zero overlap is what stops this firing on a correct use; the cost
    # is that it misses a collision between two items that happen to share a word, which
    # is the safe direction for a check whose remedy is renumbering someone's id.
    rows: dict[str, list[tuple[str, str]]] = describes(ledger, "LEDGER")
    for i, rs in describes(orch, "ORCHESTRATOR").items():
        rows.setdefault(i, []).extend(rs)
    f = []
    for i in sorted(rows):
        seen = [(src, d, content_words(d)) for src, d in rows[i] if content_words(d)]
        clash = next(
            (
                (a, b)
                for x, a in enumerate(seen)
                for b in seen[x + 1:]
                if not (a[2] & b[2])
            ),
            None,
        )
        if clash:
            (s1, d1, _), (s2, d2, _) = clash
            f.append(f"{i} ({s1}: {d1[:58]!r} / {s2}: {d2[:58]!r})")
    if f:
        findings.append(("F", "one id carrying two different items — both files have a row, "
                              "so checks A and B reconcile clean while an allocator reads "
                              "whichever file it opened", f))

    # G — LEDGER carries a row, ORCHESTRATOR only a passing mention. Check B clears on any
    # mention anywhere, which is the right bar for "does the other file know this id exists"
    # and the wrong one for "can a fleet resume from that file". This found R7: its only
    # appearance in ORCHESTRATOR was inside another row's prose, explaining that a colliding
    # deferred child had been renumbered off it.
    g = sorted(l_table - o_table)
    if g:
        findings.append(("G", "in LEDGER's table but ORCHESTRATOR has no row for it — only a "
                              "mention, which check B accepts. A fleet resumes from the "
                              "ORCHESTRATOR table, so an id with no row there is unscheduled", g))

    # H — two rows for one id, disagreeing about its status. Checks A and B test membership,
    # F tests identity, G tests resumability; none tests CURRENCY. A row is only as bound as
    # the weakest key any check uses, so a present, plausible, stale duplicate satisfies every
    # one of them — and it is worse than a missing row, because a missing row fails membership
    # while a stale duplicate fails nothing and gets scheduled. Found by dev-09 over a file
    # this script cleared at exit 0 with five such pairs in it.
    o_status, o_skipped = status_rows(orch)
    h = []
    for i, rs in sorted(o_status.items()):
        seen = {st.replace("**", "").strip(): n for n, st in rs}
        if len(seen) > 1:
            h.append(f"{i} (" + " / ".join(f"line {n}: {st[:44]!r}" for st, n in seen.items()) + ")")
    if h:
        findings.append(("H", "two ORCHESTRATOR rows for one id disagreeing on status — a "
                              "fleet slot filled from the stale one re-plans work that is "
                              "already built", h))

    # The denominator H stands on. Printed on every run, pass or fail: "no findings" over an
    # unstated subset is the failure this line exists to make impossible to report by accident.
    examined = sum(len(v) for v in o_status.values())
    print(f"H examined {examined} rows with a status cell; "
          f"skipped {len(o_skipped)} with fewer cells than their header"
          + (f" ({', '.join(sorted({i for _, i in o_skipped if i}))})" if o_skipped else ""))
    if examined == 0:
        print("usage error: check H examined 0 rows — the table shape changed and H measured "
              "nothing. A gate that never ran is not a gate that passed.", file=sys.stderr)
        return 2
    print()

    # I — LEDGER and ORCHESTRATOR disagree about whether an item has shipped. H is this check
    # inside one file; nothing was comparing ACROSS the two. dev-09's framing is that a row is
    # only as bound as the weakest key any check uses, and currency was bound in neither
    # direction here: A and B test membership, F identity, G resumability, H intra-file
    # currency. Found on P7 and P8, which LEDGER recorded Done and merged — d7f41f7 and
    # 1e36144, both on main, the OAuth client and the stamped-stimulus lane both present in
    # the tree — while ORCHESTRATOR still read **Ready for AI**. That is the expensive
    # direction: a fleet fills its slots from ORCHESTRATOR, so a stale row there dispatches a
    # runner to rebuild work that shipped days ago, and the runner has no way to find out.
    l_status, l_skipped = status_rows(ledger)
    i_findings, i_unread, i_examined = [], [], 0
    for ident in sorted(set(o_status) & set(l_status)):
        o_cells = {st for _, st in o_status[ident]}
        l_cells = {st for _, st in l_status[ident]}
        o_states = {lifecycle(c) for c in o_cells}
        l_states = {lifecycle(c) for c in l_cells}
        if None in o_states or None in l_states:
            i_unread.append(ident)
            continue
        i_examined += 1
        if o_states != l_states:
            i_findings.append(
                f"{ident} (ORCHESTRATOR {'/'.join(sorted(o_states))}, "
                f"LEDGER {'/'.join(sorted(l_states))})"
            )
    if i_findings:
        findings.append(("I", "LEDGER and ORCHESTRATOR disagree about an item's lifecycle "
                              "state — the fleet schedules from ORCHESTRATOR, so a row stale "
                              "there dispatches a runner to rebuild shipped work", i_findings))

    # I's denominator, on the same rule as H's: an id whose status cell no pattern matched is
    # named rather than counted as agreement.
    print(f"I examined {i_examined} ids present in both files"
          + (f"; {len(i_unread)} unread ({', '.join(i_unread)})" if i_unread else "")
          + f"; LEDGER skipped {len(l_skipped)} rows with fewer cells than their header")
    if i_examined == 0:
        print("usage error: check I examined 0 ids — either the tables stopped overlapping or "
              "the status vocabulary moved past STATES. A gate that never ran is not a gate "
              "that passed.", file=sys.stderr)
        return 2
    # ---- J: a row that parses to more cells than its header ------------------------------
    #
    # Named for exactly what it reads, because the two causes it catches are different and
    # both are real. A literal `|` inside a cell renders correctly in GFM and splits every
    # naive reader — the RULE this file carries was written after `D-r7-k` did it, and then
    # broken again by the next long note authored here, which is why this is a check and not
    # a habit. The other cause is a row of one table's shape filed inside another's.
    #
    # H skips rows with FEWER cells than their header and names them. Nothing read the other
    # direction, so a note carrying a pipe passed every check while parsing wrong.
    j_findings: list[str] = []
    j_examined = 0
    for label, text in (("ORCHESTRATOR", orch), ("LEDGER", ledger)):
        header: int | None = None
        for n, line in enumerate(text.splitlines(), 1):
            if not line.startswith("|"):
                header = None
                continue
            cells = line.strip().strip("|").split(" | ")
            if header is None:
                header = len(cells)
                continue
            if not set(line.replace("|", "").replace("-", "").replace(":", "").strip()):
                continue
            j_examined += 1
            if len(cells) > header:
                j_findings.append(f"{label}:{n} parses to {len(cells)} cells against a "
                                  f"{header}-cell header — {cells[0].strip()[:40]}")
    if j_findings:
        findings.append(("J", "a table row parses to more cells than its header, so it renders "
                              "correctly and every reader splitting on the pipe reads it wrong",
                         j_findings))
    print(f"J examined {j_examined} table rows in both files")
    if j_examined == 0:
        print("usage error: check J examined 0 rows — the table reader stopped matching. "
              "A gate that never ran is not a gate that passed.", file=sys.stderr)
        return 2

    print()

    if not findings:
        print("reconciled — no findings across A, B, B-range, C, D, E, F, G, H, I, J")
        return 0
    for code, why, ids in findings:
        print(f"{code}. {why}")
        print(f"   {' '.join(ids)}")
        print()
    print(f"{len(findings)} of 10 checks found something. "
          "Which file is right is a judgement about what shipped; fix it by hand.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
