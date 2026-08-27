"""Refuse a campaign-registry edit that drops a case, a requirement or a surface (G30).

`make lint` runs this. It exists because on 2026-08-27 five cases left `cases.json` during a
merge run and every gate in the repository stayed quiet about the departure. CASE-0155..0159 were
the only coverage SURF-021..024 and REQ-021..025 have ever had — three at `effect-witness`, one
`metamorphic`, one `raster-visual`, all passing and armed — and they went without a conflict
marker, because `cases.json` is one hand-edited file that eleven worktrees write and a merge
replaces it whole rather than row by row.

WHY THE EXISTING GATES DID NOT CATCH IT, since each nearly did.

`strict-check.py` ratchets on the checked count, which is exactly the right instrument. Its floor
lives in `planning/test-campaign/strict-ratchet.json`, INSIDE the directory the merge replaces, so
the floor fell from 70 to 58 in the same movement as the coverage and the comparison was made
against the lowered number. It then reported the fall as a rise. A ratchet stored inside the thing
it watches is not a ratchet, so this gate keeps its high-water mark OUTSIDE the campaign directory.

`campaign.py check` did notice, and said so plainly: `4 surface(s) with no case at all`,
`5 requirement(s) no case traces to`. It is in no `make` target, no CI job and no pre-merge hook,
so its verdict was available and nobody was asked to read it. Availability is not a gate.

WHICH BASELINE. A merge is where the rows went, so the baseline is EVERY PARENT of the commit
under test, not one ref. The G15-G19 merges each had a side carrying rows the other did not, and
keeping one side is invisible against that side alone. Where the commit is not a merge the
baseline is its single parent, which catches a plain edit; the working tree is always compared
too, which catches a drop nobody has committed yet.

WHY IT EXITS 2 WHEN IT COMPARED NOTHING. The first version of this file resolved `origin/main`,
found the ref existed, could not read the registry out of it because that ref predates the
directory, printed four NOT COMPARED lines and then `no id dropped ... exit 0`. That is this
repository's own standing rule arriving in the gate written to enforce it: a check that could not
run is not a check that passed. Zero comparable views is now exit 2.

WHY A DIFF AGAINST A BASELINE REF AND NOT A COUNT. A count catches a net fall and misses the
common shape, which is a wave that adds twenty-four rows while dropping five: 109 -> 114 reads as
growth. Ids are compared as sets, so an add and a drop in one edit are two separate findings.

WHY REMOVAL IS PERMITTED WITH A REASON RATHER THAN FORBIDDEN. A case retired on purpose is
legitimate work. What is not legitimate is a row leaving with nobody saying so, which is the whole
of the failure above. A removal declared in `planning/registry-retirements.json` passes and stays
visible; an undeclared one exits 1 and names the ids.

WHAT THIS DOES NOT CATCH, stated rather than implied. The 2026-08-27 rows were never committed:
they lived in the working tree, and `git stash` took them. A diff against commits cannot see a
row that never reached one, so the drop half of this gate would NOT have caught the loss it was
written for. What did notice was `campaign.py check`, which said `4 surface(s) with no case at
all` and `5 requirement(s) no case traces to` while sitting in no make target. So the second half
below is that signal, wired: an enumerated surface or a non-deferred requirement with no case is
a coverage hole however it arrived, committed or not. The first half catches the recurrence shape
— a merge keeping one side — and the second catches the shape that actually happened.

The second half is deliberately narrower than `campaign.py check` as a whole. That command also
exits 1 on capture-lineage findings this repository is carrying on purpose (G21, G29), and a gate
that lands permanently red is a gate somebody switches off within a week.

WHY THE HIGH-WATER MARK IS WRITTEN ONLY WHEN ASKED. The first version wrote it on every successful
run, which made a read-only check a working-tree mutation. Measured 2026-08-27: running this gate
between two merges in a serialized merge sequence left `registry-highwater.json` modified, and the
next `git merge` refused with *"Your local changes to the following files would be overwritten by
merge"*. A gate that cannot be run mid-sequence is a gate that will not be run there, and between
merges is exactly where this one earns its keep. `--set-highwater` now matches `strict-check.py`'s
`--set-ratchet` idiom: checking is read-only, and raising the floor is a deliberate act recorded in
the commit that earns it.

CONTROL, run on every invocation: a synthetic baseline with a planted extra id must be reported as
a drop, and a synthetic baseline identical to the tree must be reported silent. If either arm
misbehaves the gate exits 2 and prints no count, because a count from an instrument that cannot
see the defect is not evidence.

Exit codes: 0 nothing dropped, 1 an undeclared drop, 2 the control failed or the baseline is
unreadable.
"""
from __future__ import annotations
import json, subprocess, sys, os

CAMPAIGN = 'planning/test-campaign'
HIGHWATER = 'planning/registry-highwater.json'
RETIREMENTS = 'planning/registry-retirements.json'
BASE = os.environ.get('REGISTRY_BASE', 'origin/main')

# (label, path relative to the campaign dir, how to pull ids out)
SOURCES = [
    ('case',        'cases.json',     lambda d: [x['id'] for x in d]),
    ('requirement', 'inventory.json', lambda d: [x['id'] for x in d.get('requirement', [])]),
    ('surface',     'inventory.json', lambda d: [x['id'] for x in d.get('surface', [])]),
    ('defect',      'inventory.json', lambda d: [x['id'] for x in d.get('defect', [])]),
]


def read_ref(ref, path):
    """Ids at a git ref, or None when the ref cannot supply the file."""
    r = subprocess.run(['git', 'show', f'{ref}:{path}'], capture_output=True, text=True)
    if r.returncode != 0:
        return None
    try:
        return json.loads(r.stdout)
    except json.JSONDecodeError:
        return None


def read_tree(path):
    with open(path, encoding='utf-8') as fh:
        return json.load(fh)


def ids_for(doc, extract):
    if doc is None:
        return None
    try:
        return set(extract(doc))
    except (KeyError, TypeError):
        return None


def declared_retirements():
    if not os.path.exists(RETIREMENTS):
        return {}
    with open(RETIREMENTS, encoding='utf-8') as fh:
        rows = json.load(fh)
    return {r['id']: r.get('reason', '') for r in rows if r.get('reason')}


def uncovered():
    """Surfaces and requirements the registry enumerates and no case reaches.

    This is `campaign.py check`'s coverage signal, narrowed to the two lines that report a
    coverage hole, so it can be a gate without inheriting findings the repo is carrying.
    """
    inv_path = os.path.join(CAMPAIGN, 'inventory.json')
    cases_path = os.path.join(CAMPAIGN, 'cases.json')
    if not (os.path.exists(inv_path) and os.path.exists(cases_path)):
        return None, None, 0
    inv = read_tree(inv_path)
    cases = read_tree(cases_path)
    on_surface, on_req = set(), set()
    for c in cases:
        if c.get('surface'):
            on_surface.add(c['surface'])
        req = c.get('req')
        for r in ([req] if isinstance(req, str) else (req or [])):
            if r:
                on_req.add(r)
    surfaces = [x['id'] for x in inv.get('surface', [])]
    # `deferred` is the requirement's CLASS, not its evidence word. Reading `evidence` here
    # reported REQ-020 as an uncovered hole on this gate's first run; it is deferred by class,
    # correctly has no case, and `campaign.py check` excludes it for that reason.
    reqs = [x['id'] for x in inv.get('requirement', [])
            if (x.get('class') or '').lower() != 'deferred']
    return ([s for s in surfaces if s not in on_surface],
            [r for r in reqs if r not in on_req],
            len(surfaces) + len(reqs))


def control():
    """Prove both arms before reading anything real."""
    base = {'A', 'B', 'C'}
    same = {'A', 'B', 'C'}
    short = {'A', 'B'}
    if base - short != {'C'}:
        return 'the drop arm did not report a planted removal'
    if base - same != set():
        return 'the silent arm reported a removal over an identical set'
    return None


def baselines():
    """Every ref this commit should not have lost rows against.

    A merge is compared with all of its parents, because keeping one side of a merge is
    invisible against that side. A non-merge is compared with its parent. An explicit
    REGISTRY_BASE overrides both.
    """
    if os.environ.get('REGISTRY_BASE'):
        return [os.environ['REGISTRY_BASE']]
    r = subprocess.run(['git', 'rev-list', '--parents', '-n', '1', 'HEAD'],
                       capture_output=True, text=True)
    if r.returncode != 0 or not r.stdout.split():
        return []
    parts = r.stdout.split()
    return parts[1:]  # drop the commit's own sha, keep the parents


def main():
    bad = control()
    if bad:
        print(f'control FAILED: {bad}')
        print('no count printed — an instrument that cannot see the defect is not evidence')
        return 2
    print('control HELD (a planted removal is reported, an identical set is silent)')

    refs = baselines()
    if not refs:
        print('environment: HEAD has no parent, so there is no earlier state to compare against')
        return 2

    retired = declared_retirements()
    findings, comparisons, unreadable = [], 0, []

    for label, rel, extract in SOURCES:
        path = os.path.join(CAMPAIGN, rel)
        if not os.path.exists(path):
            unreadable.append(f'{label}: {path} absent from the working tree')
            continue
        tree_ids = ids_for(read_tree(path), extract)
        if tree_ids is None:
            unreadable.append(f'{label}: {path} has a shape this gate cannot read')
            continue
        for ref in refs:
            base_ids = ids_for(read_ref(ref, path), extract)
            if base_ids is None:
                unreadable.append(f'{label} vs {ref[:9]}: that ref does not carry {rel}')
                continue
            comparisons += 1
            gone = sorted(base_ids - tree_ids)
            for g in gone:
                if g in retired:
                    print(f'  retired  {label} {g} — {retired[g]}')
            undeclared = [g for g in gone if g not in retired]
            if undeclared:
                findings.append((label, ref, undeclared))

    for note in unreadable:
        print(f'  NOT COMPARED — {note}')

    if comparisons == 0:
        print(f'compared 0 registry view(s) against {len(refs)} baseline(s): {", ".join(r[:9] for r in refs)}')
        print('NOT A PASS — nothing was comparable, so this run measured nothing. A check that '
              'could not run is not a check that passed.')
        return 2

    print(f'compared {comparisons} registry view(s) against {len(refs)} baseline(s): '
          f'{", ".join(r[:9] for r in refs)}')

    if findings:
        print()
        print('DROPPED — an id present at the baseline and absent from the working tree:')
        for label, ref, ids in findings:
            print(f'  {label}, present at {ref[:9]}: {", ".join(ids)}')
        print()
        print(f'Each of these left the registry with nothing recording that it left. Restore it, or')
        print(f'declare it in {RETIREMENTS} as {{"id": "...", "reason": "..."}} so the removal stays')
        print('visible. On 2026-08-27 five cases left this way and the campaign reported a rise.')
        return 1

    # The high-water mark lives here rather than in the campaign directory, because on
    # 2026-08-27 the loss carried the campaign's own ratchet away with the rows it was watching.
    tree_total = 0
    for label, rel, extract in SOURCES:
        path = os.path.join(CAMPAIGN, rel)
        if os.path.exists(path):
            got = ids_for(read_tree(path), extract)
            tree_total += len(got) if got else 0
    bare_surfaces, bare_reqs, census = uncovered()
    if bare_surfaces is None:
        print('  NOT COMPARED — no inventory or cases file, so coverage was not examined')
    else:
        print(f'coverage: examined {census} enumerated surface(s) and non-deferred requirement(s)')
        if bare_surfaces or bare_reqs:
            print()
            print('UNCOVERED — enumerated, and no case reaches it:')
            if bare_surfaces:
                print(f'  surface: {", ".join(sorted(bare_surfaces))}')
            if bare_reqs:
                print(f'  requirement: {", ".join(sorted(bare_reqs))}')
            print()
            print('This is the shape the 2026-08-27 loss took: the rows were never committed, so no')
            print('diff could see them go. Write the case, restore what covered it, or mark the')
            print('requirement deferred with its citation.')
            return 1

    prev = None
    if os.path.exists(HIGHWATER):
        with open(HIGHWATER, encoding='utf-8') as fh:
            prev = json.load(fh).get('ids')
    if '--set-highwater' in sys.argv:
        with open(HIGHWATER, 'w', encoding='utf-8') as fh:
            json.dump({'ids': tree_total, 'baselines': refs}, fh, indent=1)
            fh.write('\n')
        print(f'high-water mark set to {tree_total} (was {prev})')
    elif prev is not None and tree_total > prev:
        print(f'high-water mark is {prev}; the registry now holds {tree_total}. '
              f'Raise it with --set-highwater in the commit that earns it.')
    print(f'no id dropped — registry holds {tree_total} across cases, requirements, surfaces and defects')
    return 0


if __name__ == '__main__':
    sys.exit(main())
