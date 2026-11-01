"""Migration regressions on temporary synthetic files, with an injected runtime verdict."""
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import tempfile

spec = importlib.util.spec_from_file_location('migration', Path(__file__).with_name('apply-migration.py'))
migration = importlib.util.module_from_spec(spec)
spec.loader.exec_module(migration)

with tempfile.TemporaryDirectory(prefix='mcpr-migration-') as root:
    directory = Path(root)
    config = directory / 'servers.json'
    plan = directory / 'plan.json'
    literal = 'synthetic-never-a-real-key-0000'
    config.write_text(json.dumps({'mcpServers': {'scratch': {'env': {'TEST_KEY': literal, 'PATH': '/usr/bin'}}}}))
    config.chmod(0o600)
    row = {'upstream': 'scratch', 'block': 'env', 'key': 'TEST_KEY', 'is_secret': True, 'uri': '<CHOOSE>'}
    def run(uri, output, *, trusted=True, extra=()):
        row['uri'] = uri
        plan.write_text(json.dumps({'config': str(config), 'rows': [row]}))
        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout):
            rc = migration.main(['--out', str(output), *extra], plan_path=str(plan), runtime_check=lambda _: trusted)
        assert literal not in stdout.getvalue(), 'a secret escaped to output'
        return rc
    out = directory / 'out.json'
    assert run('<CHOOSE>', out) == 1 and not out.exists()
    print('ok placeholder refuses without output')
    assert run('warden://scratch%2Fapi-key', out) == 0
    assert literal not in out.read_text() and 'warden://scratch%2Fapi-key' in out.read_text()
    print('ok supported exact-name reference replaces synthetic value')
    assert literal in config.read_text()
    print('ok copy leaves source unchanged')
    assert json.loads(out.read_text())['mcpServers']['scratch']['env']['PATH'] == '/usr/bin'
    print('ok ordinary configuration survives')
    assert out.stat().st_mode & 0o777 == 0o600
    print('ok output is private from creation')
    for uri in ['vault:scratch/api-key', 'op://vault/item/field', 'Bearer op://vault/item/field', 'warden://%00', 'warden://%zz']:
        refused = directory / 'refused.json'
        assert run(uri, refused) == 1 and not refused.exists()
    print('ok unsupported or malformed URI refuses without output')
    assert run('warden://key', directory / 'inplace.json', extra=['--in-place']) == 1
    assert literal in config.read_text()
    print('ok in-place requires backup')
    assert run('warden://key', directory / 'untrusted.json', trusted=False) == 1
    assert not (directory / 'untrusted.json').exists()
    print('ok unverifiable runtime refuses even a copy')
    assert not migration.runtime_preflight(str(directory / 'absent-runtime'))
    print('ok unsupported runtime cannot report readiness')
    assert run('warden://key', out, extra=['--in-place', '--backup']) == 0
    rollback = Path(str(config) + '.pre-warden')
    assert literal in rollback.read_text() and rollback.stat().st_mode & 0o777 == 0o600
    assert run('warden://new-key', out, extra=['--in-place', '--backup']) == 1
    assert literal in rollback.read_text()
    print('ok in-place preserves an exclusive private rollback copy')
print('warden-migration selftest: 10 groups passed; live configuration was not opened')
