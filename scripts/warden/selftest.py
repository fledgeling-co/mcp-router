"""Migration regressions on temporary synthetic files, with an injected runtime verdict."""
import contextlib
import importlib.util
import io
import hashlib
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
    config.write_text(json.dumps({'mcpServers': {'scratch': {'credentialProject': root, 'env': {'TEST_KEY': literal, 'PATH': '/usr/bin'}}}}))
    config.chmod(0o600)
    row = {'upstream': 'scratch', 'block': 'env', 'key': 'TEST_KEY', 'is_secret': True, 'uri': '<CHOOSE>'}
    def run(uri, output, *, trusted=True, extra=()):
        row['uri'] = uri
        plan.write_text(json.dumps({'config': str(config), 'configSha256': hashlib.sha256(config.read_bytes()).hexdigest(), 'rows': [row]}))
        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout):
            rc = migration.main(['--out', str(output), *extra], plan_path=str(plan), runtime_check=lambda *_: trusted)
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
    rollbacks = list(directory.glob('servers.json.pre-warden-*'))
    assert len(rollbacks) == 1
    rollback = rollbacks[0]
    assert literal in rollback.read_text() and rollback.stat().st_mode & 0o777 == 0o600
    assert run('warden://new-key', out, extra=['--in-place', '--backup']) == 0
    assert len(list(directory.glob('servers.json.pre-warden-*'))) == 2
    assert literal in rollback.read_text()
    print('ok in-place retains independent private rollback snapshots')
    row['uri'] = 'warden://different'
    plan.write_text(json.dumps({'config': str(config), 'configSha256': hashlib.sha256(config.read_bytes()).hexdigest(), 'rows': [row]}))
    changed = json.loads(config.read_text())
    changed['mcpServers']['scratch']['env']['TEST_KEY'] = 'owner-rotated-synthetic-key'
    config.write_text(json.dumps(changed))
    post_rotation = config.read_bytes()
    stale_out = directory / 'stale.json'
    with contextlib.redirect_stdout(io.StringIO()):
        assert migration.main(['--out', str(stale_out)], plan_path=str(plan), runtime_check=lambda *_: True) == 1
    assert not stale_out.exists() and config.read_bytes() == post_rotation
    print('ok stale plans refuse before writing even an output copy')
    unscoped = json.loads(config.read_text())
    del unscoped['mcpServers']['scratch']['credentialProject']
    config.write_text(json.dumps(unscoped))
    assert run('warden://key', directory / 'unscoped.json') == 1
    assert not (directory / 'unscoped.json').exists()
    print('ok missing credential project refuses without output')

    scope_spec = importlib.util.spec_from_file_location('planner', Path(__file__).with_name('plan-migration.py'))
    planner = importlib.util.module_from_spec(scope_spec)
    scope_spec.loader.exec_module(planner)
    http_config = {'mcpServers': {'scratch': {'url':'https://fixture.invalid/mcp','headers':{'Authorization':literal}}}}
    config.write_text(json.dumps(http_config))
    planned_rows = planner.plan(http_config)
    projects = planner.project_scopes(http_config, planned_rows)
    assert projects == {'scratch':'<CHOOSE>'}
    planned_rows[0]['uri']='Bearer warden://scratch-key'
    projects['scratch']=root
    plan.write_text(json.dumps({'config':str(config),'configSha256':hashlib.sha256(config.read_bytes()).hexdigest(), 'projects':projects,'rows':planned_rows}))
    chosen_out = directory/'chosen-scope.json'
    with contextlib.redirect_stdout(io.StringIO()):
        assert migration.main(['--out',str(chosen_out)], plan_path=str(plan), runtime_check=lambda *_: True) == 0
    chosen=json.loads(chosen_out.read_text())['mcpServers']['scratch']
    assert chosen['credentialProject']==root and chosen['headers']['Authorization']=='Bearer warden://scratch-key'
    assert json.loads(config.read_text())==http_config
    print('ok explicit project selection applies from the plan without editing or invalidating source')
print('warden-migration selftest: 13 groups passed; live configuration was not opened')
