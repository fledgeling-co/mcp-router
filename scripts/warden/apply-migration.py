"""Rewrite mcp-router's config so credentials are `warden://` URIs rather than values — W2.

Reads the plan `plan-migration.py` wrote, and produces a config in which every entry the plan
classified as a credential carries its vault URI instead of its value. Configuration entries are
copied through untouched.

WRITES A COPY BY DEFAULT. `--out <path>` names it; without `--in-place` the live config is never
opened for writing. `--in-place` additionally requires `--backup`, which copies the current file
beside itself with its mode preserved before anything is written — the config is mode 0600 and a
rewrite that widened it would be a worse defect than the one this closes.

REFUSES WHILE A PLACEHOLDER SURVIVES. A `<CHOOSE>` means nobody has said which vault item that
credential is, and writing `warden://<CHOOSE>` would produce a config that fails at connection time
for a reason the error will not explain.

NEVER PRINTS A VALUE. It reports key names, upstream names and URIs. The one thing it will not
show is the thing it is moving.

VERIFIES WHAT IT WROTE, against the same predicate the router uses. `SecretResolver.isSecretURI`
accepts a value beginning `warden://` or `op://`, and a `Bearer `-prefixed one is unwrapped first;
this checks every rewritten entry against that rule rather than against its own idea of a URI, so a
config it calls good is one the router will accept.

Exit codes: 0 written, 1 a placeholder or an unresolvable row, 2 the plan or config is unreadable.
"""
from __future__ import annotations
import json, os, shutil, sys

HERE = os.path.dirname(os.path.abspath(__file__))
PLAN = os.path.join(HERE, 'migration-plan.json')


def is_secret_uri(value: str) -> bool:
    """The router's own rule, in `SecretResolver.isSecretURI` plus its Bearer unwrap."""
    v = value[len('Bearer '):].strip() if value.startswith('Bearer ') else value
    return v.startswith('warden://') or v.startswith('op://')


def main() -> int:
    args = sys.argv[1:]
    in_place = '--in-place' in args
    backup = '--backup' in args
    out = None
    if '--out' in args:
        out = args[args.index('--out') + 1]

    if not os.path.exists(PLAN):
        print(f'no plan at {PLAN} — run plan-migration.py first')
        return 2
    plan = json.load(open(PLAN, encoding='utf-8'))
    config_path = plan['config']
    rows = plan['rows']

    pending = [r for r in rows if r['is_secret'] and (not r.get('uri') or r['uri'] == '<CHOOSE>')]
    if pending:
        print(f'REFUSING — {len(pending)} credential(s) have no vault URI chosen:')
        for r in pending:
            print(f'  {r["upstream"]:<16} {r["block"]:<8} {r["key"]}')
        print('\nEach needs the vault item it corresponds to. Nothing here can know which is which:')
        print('`warden import` pulls from 1Password through `op`, so the credential must exist')
        print('there first, and only you can say which item is which.')
        return 1

    if in_place and not backup:
        print('REFUSING — --in-place requires --backup. The config is mode 0600 and holds every')
        print('credential this rewrite touches; a rewrite with no copy beside it is not reversible.')
        return 1

    doc = json.load(open(config_path, encoding='utf-8'))
    changed = 0
    for r in rows:
        if not r['is_secret']:
            continue
        block = (doc['mcpServers'][r['upstream']].get(r['block']) or {})
        block[r['key']] = r['uri']
        changed += 1

    bad = []
    for r in rows:
        if not r['is_secret']:
            continue
        v = doc['mcpServers'][r['upstream']][r['block']][r['key']]
        if not is_secret_uri(v):
            bad.append(f'{r["upstream"]}/{r["key"]}')
    if bad:
        print('REFUSING — these would not be recognised as secret URIs by the router:')
        for b in bad:
            print(f'  {b}')
        return 1

    if in_place:
        mode = os.stat(config_path).st_mode & 0o777
        shutil.copy2(config_path, config_path + '.pre-warden')
        os.chmod(config_path + '.pre-warden', mode)
        print(f'backed up to {config_path}.pre-warden at mode {oct(mode)}')
        target = config_path
    else:
        target = out or os.path.join(HERE, 'servers.migrated.json')

    with open(target, 'w', encoding='utf-8') as fh:
        json.dump(doc, fh, indent=2)
        fh.write('\n')
    os.chmod(target, 0o600)
    print(f'wrote {target} at mode 0600 — {changed} credential(s) now carry a URI, no value')
    if not in_place:
        print('This is a COPY. Nothing the router reads has changed. Review it, then re-run with')
        print('  --in-place --backup')
    return 0


if __name__ == '__main__':
    sys.exit(main())
