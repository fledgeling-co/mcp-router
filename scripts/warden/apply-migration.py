"""Write a Warden URI migration only after the installed TypeScript runtime passes preflight.

The retired Swift resolver does not establish support in the running TypeScript router.
Only exact-name warden:// references are supported; op:// vault/field paths are refused.
Both output copies and in-place changes require a trusted runtime. No secret is printed.
"""
from __future__ import annotations
import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
from urllib.parse import unquote

HERE = os.path.dirname(os.path.abspath(__file__))
PLAN = os.path.join(HERE, 'migration-plan.json')


def is_secret_uri(value: str) -> bool:
    v = value
    if v.lower().startswith('bearer '):
        v = v.split(None, 1)[1] if len(v.split(None, 1)) == 2 else ''
    if not v.lower().startswith('warden://'):
        return False
    try:
        import re
        if re.search(r'%(?![0-9a-fA-F]{2})', v):
            return False
        name = unquote(v[len('warden://'):], errors='strict')
    except (UnicodeError, ValueError):
        return False
    return bool(name) and len(name) <= 256 and name == name.strip() and not any(
        ord(c) < 32 or ord(c) == 127 or c in '?#<>' for c in name)


def runtime_preflight(runtime: str) -> bool:
    entry = os.path.join(runtime, 'dist', 'credential-preflight.js')
    if not os.path.isfile(entry):
        print('REFUSING: installed TypeScript runtime has no credential resolver preflight.')
        return False
    try:
        result = subprocess.run(['node', entry], capture_output=True, text=True, timeout=20)
        evidence = json.loads(result.stdout)
        valid = result.returncode == 0 and evidence == {
            'supported': True, 'scheme': 'warden', 'trusted': True}
    except (OSError, subprocess.SubprocessError, ValueError):
        valid = False
    if not valid:
        print('REFUSING: installed Warden has not passed Gatekeeper and the pinned Developer ID check.')
    return valid


def main(args=None, *, plan_path=PLAN, runtime_check=runtime_preflight) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--out')
    parser.add_argument('--in-place', action='store_true')
    parser.add_argument('--backup', action='store_true')
    parser.add_argument('--runtime', default=os.path.expanduser('~/.local/share/mcp-router'))
    options = parser.parse_args(sys.argv[1:] if args is None else args)
    try:
        with open(plan_path, encoding='utf-8') as file:
            plan = json.load(file)
        config_path, rows = plan['config'], plan['rows']
        credentials = [r for r in rows if r['is_secret']]
        if any(not isinstance(r.get('uri'), str) or not is_secret_uri(r['uri']) for r in credentials):
            print('REFUSING: choose an exact-name warden:// URI for each credential; op:// is unsupported.')
            return 1
        if options.in_place and not options.backup:
            print('REFUSING: --in-place requires --backup.')
            return 1
        # This runs before opening the credential-bearing source or any output, including copies.
        if not runtime_check(options.runtime):
            return 1
        with open(config_path, encoding='utf-8') as file:
            doc = json.load(file)
        for row in credentials:
            block = doc['mcpServers'][row['upstream']][row['block']]
            if row['key'] not in block:
                print('REFUSING: migration plan no longer matches the configured key names.')
                return 1
            block[row['key']] = row['uri']
        if options.in_place:
            backup_path = config_path + '.pre-warden'
            # Preserve a previous rollback copy instead of silently replacing it.
            if os.path.exists(backup_path):
                print('REFUSING: a pre-warden backup already exists; preserve it before retrying.')
                return 1
            descriptor = os.open(backup_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(descriptor, 'wb') as backup_file, open(config_path, 'rb') as source:
                shutil.copyfileobj(source, backup_file)
                backup_file.flush()
                os.fsync(backup_file.fileno())
            target = config_path
        else:
            target = options.out or os.path.join(HERE, 'servers.migrated.json')
        # The temporary file is private from creation and atomically replaces the destination.
        fd, temporary = tempfile.mkstemp(prefix='.warden-migration-', dir=os.path.dirname(os.path.abspath(target)))
        try:
            with os.fdopen(fd, 'w', encoding='utf-8') as file:
                json.dump(doc, file, indent=2)
                file.write('\n')
                file.flush()
                os.fsync(file.fileno())
            os.replace(temporary, target)
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)
        print(f'wrote mode 0600 output; {len(credentials)} credentials now carry exact-name Warden references')
        return 0
    except (OSError, ValueError, KeyError, TypeError):
        print('REFUSING: plan or configuration could not be read safely; no credential value is displayed.')
        return 2


if __name__ == '__main__':
    sys.exit(main())
