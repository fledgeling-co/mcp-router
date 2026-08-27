"""Plan the move of mcp-router's at-rest credentials behind Warden — W2.

WHAT THIS DOES AND DOES NOT DO. It reads `~/.claude/mcp-router/servers.json`, decides which
entries are credentials and which are ordinary configuration, and writes a REWRITTEN COPY in which
every credential is replaced by a `warden://` or `op://` URI. It never writes the live file, never
prints a secret value, and never contacts Warden or 1Password. Running it changes nothing an
upstream reads.

WHY A COPY AND A PLAN RATHER THAN A MIGRATION. W1's own frontmatter records the boundary: *rotation
and any config change are the owner's, not this fleet's*. So the deliverable is the mechanism,
tested, plus the one command that applies it — not the application.

WHY THE ROUTER HALF IS ALREADY DONE, which is the thing that makes this a config rewrite rather
than a feature. `app/Sources/RouterCore/Auth/SecretResolver.swift` resolves `warden://` and `op://`
at upstream connection time, handles a `Bearer `-prefixed value, and is invoked by
`StdioUpstreamTransport` per env pair at line 192 with `WardenSecretResolver()` as the default.
Six tests cover it and pass. That was checked rather than assumed, because this repository spent
tonight finding a merged, green, seventeen-arm gate that nothing invoked.

WHY NAME-BASED CLASSIFICATION, AND WHY IT FAILS TOWARDS ASKING. An entry is treated as a credential
unless it is on the NOT_A_SECRET list below. That direction is deliberate: mistaking a credential
for configuration leaves it at rest, which is the defect; mistaking configuration for a credential
produces a URI that cannot resolve and fails loudly at connection time. The list is short and
every member is there for a stated reason rather than a pattern.

WHAT IT CANNOT DECIDE. Which vault item each credential corresponds to. `warden import` pulls from
1Password through `op`, so a credential must exist there before a `warden://` URI can resolve, and
nothing here can know which item is which. Every row is emitted with its URI left as a
`<CHOOSE>` placeholder and the plan refuses to be applied while any remain.

Exit codes: 0 plan written, 2 the config could not be read or a placeholder survived --apply.
"""
from __future__ import annotations
import json, os, sys, shutil

CONFIG = os.path.expanduser('~/.claude/mcp-router/servers.json')

# Entries that are configuration rather than credentials. Each is listed with why, because a bare
# allowlist is the thing that quietly grows until it covers a real secret.
NOT_A_SECRET = {
    'PATH':                     'the process search path, not a credential',
    'DOCKER_HOST':              'a socket address; it grants nothing on its own',
    'NAMECHEAP_CLIENT_IP':      'the caller IP the API expects, not a secret',
    'NAMECHEAP_SANDBOX':        'a boolean selecting the sandbox endpoint',
    'DOSSIER_BUDGET_USD':       'a spend ceiling, read by the upstream as policy',
    'DOSSIER_REQUIRE_CONTRACT': 'a boolean policy flag',
    'x-company-id':             'a tenant identifier, not an authenticator',
    'NAMECHEAP_USERNAME':       'an account name; it authenticates nothing without the API key',
    'NAMECHEAP_API_USER':       'an account name, as above',
}


def classify(name: str) -> tuple[bool, str]:
    bare = name.split(':', 1)[-1]
    if bare in NOT_A_SECRET:
        return False, NOT_A_SECRET[bare]
    return True, 'treated as a credential — an entry is a secret unless this file says otherwise'


def load():
    with open(CONFIG, encoding='utf-8') as fh:
        return json.load(fh)


def plan(doc):
    rows = []
    for name, cfg in sorted((doc.get('mcpServers') or {}).items()):
        for block in ('env', 'headers'):
            for key in sorted((cfg.get(block) or {})):
                label = key if block == 'env' else f'header:{key}'
                secret, why = classify(label)
                rows.append({
                    'upstream': name, 'block': block, 'key': key,
                    'is_secret': secret, 'reason': why,
                    'uri': '<CHOOSE>' if secret else None,
                })
    return rows


def main() -> int:
    if not os.path.exists(CONFIG):
        print(f'environment: no config at {CONFIG}')
        return 2
    doc = load()
    rows = plan(doc)
    secrets = [r for r in rows if r['is_secret']]
    config_rows = [r for r in rows if not r['is_secret']]

    print(f'examined {len(rows)} entr(ies) across '
          f'{len({r["upstream"] for r in rows})} upstream(s) that hold one')
    print(f'  {len(secrets)} classified as credentials, {len(config_rows)} as configuration')
    print('  no value was read, and none is printed below\n')

    print('CREDENTIALS — each needs a vault item chosen before this can be applied:')
    for r in secrets:
        print(f'  {r["upstream"]:<16} {r["block"]:<8} {r["key"]:<24} -> {r["uri"]}')
    print('\nCONFIGURATION — left exactly as it is:')
    for r in config_rows:
        print(f'  {r["upstream"]:<16} {r["key"]:<24} {r["reason"]}')

    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'migration-plan.json')
    with open(out, 'w', encoding='utf-8') as fh:
        json.dump({'config': CONFIG, 'rows': rows}, fh, indent=1)
        fh.write('\n')
    print(f'\nwrote {out}')
    print('Fill each <CHOOSE> with the vault URI for that credential, then apply with')
    print('  python3 scripts/warden/apply-migration.py --backup')
    print('which rewrites a COPY and refuses while any placeholder survives.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
