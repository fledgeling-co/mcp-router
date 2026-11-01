#!/usr/bin/env python3
"""Measure Claude's target binding using only a disposable local marketplace."""

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--claude', default=shutil.which('claude'))
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    if not args.claude:
        parser.error('Claude CLI is unavailable')
    records = []
    with tempfile.TemporaryDirectory(prefix='router-plugin-binding-') as scratch:
        root = Path(scratch)
        env = {
            'PATH': os.environ.get('PATH', '/usr/bin:/bin'),
            'HOME': str(root / 'home'),
            'CLAUDE_CONFIG_DIR': str(root / 'config'),
            'TMPDIR': str(root / 'tmp'),
            'DISABLE_AUTOUPDATER': '1',
            'CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC': '1',
        }
        for key in ('HOME', 'CLAUDE_CONFIG_DIR', 'TMPDIR'):
            Path(env[key]).mkdir()

        def run(*argv):
            result = subprocess.run(
                [args.claude, *argv], env=env, cwd=root,
                stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=45,
            )
            record = dict(argv=list(argv), exit=result.returncode,
                          stdout=result.stdout, stderr=result.stderr)
            records.append(record)
            return record

        market = root / 'market'
        plugin = market / 'plugins' / 'fixture'
        (market / '.claude-plugin').mkdir(parents=True)
        (plugin / '.claude-plugin').mkdir(parents=True)
        (plugin / 'skills' / 'fixture').mkdir(parents=True)

        def version(number):
            (market / '.claude-plugin' / 'marketplace.json').write_text(json.dumps({
                'name': 'router-binding-probe', 'owner': {'name': 'Local verification'},
                'plugins': [{'name': 'fixture', 'source': './plugins/fixture',
                             'version': number, 'description': 'Isolated fixture'}],
            }))
            (plugin / '.claude-plugin' / 'plugin.json').write_text(json.dumps({
                'name': 'fixture', 'version': number, 'description': 'Isolated fixture',
            }))
            (plugin / 'skills' / 'fixture' / 'SKILL.md').write_text(
                '---\nname: fixture\ndescription: Isolated fixture\n---\n'
                f'Local fixture {number}.\n'
            )

        version('1.0.0')
        assert run('plugin', 'marketplace', 'add', str(market), '--json')['exit'] == 0
        identity = 'fixture@router-binding-probe'
        assert run('plugin', 'install', identity, '--json', '--scope', 'user')['exit'] == 0
        before = json.loads(run('plugin', 'list', '--json')['stdout'])
        assert before[0]['version'] == '1.0.0', before
        # Move the offer after the supposed review. A generic command hash is not a target lock.
        version('2.0.0')
        updated = run('plugin', 'update', identity, '--json', '--scope', 'user',
                      '--accept-command', '0' * 64)
        after = json.loads(run('plugin', 'list', '--json')['stdout'])
        suffixed = run('plugin', 'update', identity + '@1.0.0', '--json', '--scope', 'user')
        pinned = run('plugin', 'update', identity, '--version', '1.0.0', '--json', '--scope', 'user')
        final = json.loads(run('plugin', 'list', '--json')['stdout'])
        measured = (
            updated['exit'] == 0 and after[0]['version'] == '2.0.0'
            and suffixed['exit'] == 0 and final[0]['version'] == '2.0.0'
            and pinned['exit'] != 0 and "unknown option '--version'" in pinned['stderr']
        )
        report = {
            'scope': 'Disposable local source; no owner plugin tree or provider used',
            'observedLatestOnly': measured,
            'installedBefore': before[0]['version'],
            'installedAfterCatalogueMoved': after[0]['version'],
            'records': records,
            'limitation': 'This measures a directory source, not all CLI source types or future versions.',
        }
        Path(args.output).write_text(json.dumps(report, indent=2) + '\n')
        print(json.dumps({key: report[key] for key in (
            'observedLatestOnly', 'installedBefore', 'installedAfterCatalogueMoved',
        )}))
        if not measured:
            raise SystemExit('CLI behavior changed; inspect evidence before choosing an adapter')


if __name__ == '__main__':
    main()
