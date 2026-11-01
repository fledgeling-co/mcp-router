#!/usr/bin/env python3
"""Check the complete vendored release against its immutable upstream-file manifest."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def check(root: Path, pin: dict) -> list[str]:
    expected = pin['files']
    links = [p.relative_to(root).as_posix() for p in root.rglob('*') if p.is_symlink()]
    actual = {p.relative_to(root).as_posix() for p in root.rglob('*') if p.is_file()
              and not ('__pycache__' in p.parts and p.suffix == '.pyc')}
    findings = [f'symlink outside archived format: {path}' for path in sorted(links)]
    findings += [f'missing archived file: {path}' for path in sorted(expected.keys() - actual)]
    findings += [f'file outside pinned archive: {path}' for path in sorted(actual - expected.keys())]
    for name in sorted(actual & expected.keys()):
        path = root / name
        if path.is_symlink() or hashlib.sha256(path.read_bytes()).hexdigest() != expected[name]:
            findings.append(f'archived file changed: {name}')
    lines = ''.join(sorted(f'{digest}  ./{name}\n' for name, digest in expected.items()))
    if len(expected) != pin['fileCount'] or hashlib.sha256(lines.encode()).hexdigest() != pin['treeSha256']:
        findings.append('pin file count or tree checksum is inconsistent')
    for name in ['plugin.json', '.claude-plugin/plugin.json', '.cursor-plugin/plugin.json']:
        path = root / name
        if path.exists() and json.loads(path.read_text(encoding='utf-8')).get('version') != pin['version']:
            findings.append(f'manifest version disagrees: {name}')
    return findings


def index_population(root: Path, pin: dict) -> list[str]:
    result = subprocess.run(
        ['git', '-C', str(root), 'ls-files', '--cached', '-z', '--', '.'],
        capture_output=True, check=False,
    )
    if result.returncode:
        return ['cannot verify pinned archive population in the Git index']
    tracked = set(result.stdout.decode('utf-8').split('\0'))
    return [f'pinned archive file is not in the Git index: {name}'
            for name in sorted(pin['files'].keys() - tracked)]


def index_selftest(root: Path, pin: dict) -> None:
    with tempfile.TemporaryDirectory(prefix='campaign-pin-index-control-') as directory:
        repository = Path(directory)
        copy = repository / 'plugin'
        shutil.copytree(root, copy, ignore=shutil.ignore_patterns('__pycache__'))
        (repository / '.gitignore').write_text('*.log\n', encoding='utf-8')
        subprocess.run(['git', '-C', str(repository), 'init', '-q'], check=True)
        subprocess.run(['git', '-C', str(repository), 'add', '-f', '--', 'plugin'], check=True)
        assert not check(copy, pin) and not index_population(copy, pin), 'indexed archive must pass'
        name = next(name for name in pin['files'] if name.endswith('.log'))
        subprocess.run(['git', '-C', str(repository), 'rm', '-q', '--cached', '-f', '--', 'plugin/' + name], check=True)
        assert (copy / name).is_file() and not check(copy, pin), 'the filesystem archive remains complete'
        ignored = subprocess.run(
            ['git', '-C', str(repository), 'check-ignore', '-q', '--', 'plugin/' + name], check=False)
        assert ignored.returncode == 0, 'the removed indexed file is actually ignored'
        assert index_population(copy, pin) == [f'pinned archive file is not in the Git index: {name}'], \
            'an untracked ignored pinned file must refuse certification'
        subprocess.run(['git', '-C', str(repository), 'add', '-f', '--', 'plugin/' + name], check=True)
        assert not index_population(copy, pin), 'restored index must pass'
        (copy / name).unlink()
        assert check(copy, pin), 'a tracked file missing from disk must fail the filesystem check'
    print('index selftest: complete but untracked ignored archive refused; indexed restoration passed')


def selftest(root: Path, pin: dict) -> None:
    with tempfile.TemporaryDirectory(prefix='campaign-pin-control-') as directory:
        copy = Path(directory) / 'plugin'
        shutil.copytree(root, copy, ignore=shutil.ignore_patterns('__pycache__'))
        assert not check(copy, pin), 'archived control must pass'
        target = copy / 'skills/test-campaign/scripts/campaign.py'
        before = target.read_bytes()
        target.write_bytes(before + b'\n# pin negative control\n')
        assert any('archived file changed:' in x for x in check(copy, pin)), 'changed script must fail'
        target.write_bytes(before)
        extra = copy / 'unexpected-file.txt'
        extra.write_text('pin negative control', encoding='utf-8')
        assert any('outside pinned archive:' in x for x in check(copy, pin)), 'extra file must fail'
        extra.unlink()
        link = copy / 'unexpected-link'
        link.symlink_to('missing-target')
        assert any('symlink outside archived format:' in x for x in check(copy, pin)), 'broken link must fail'
        link.unlink()
        assert not check(copy, pin), 'restored archive must pass'
    print('pin selftest: clean archive passed; changed script, extra file and broken link refused; restoration passed')


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--selftest', action='store_true')
    args = parser.parse_args()
    root = ROOT / 'vendor/test-campaign'
    pin = json.loads((ROOT / 'vendor/test-campaign.pin.json').read_text(encoding='utf-8'))
    if args.selftest:
        selftest(root, pin)
        index_selftest(root, pin)
    findings = check(root, pin) + index_population(root, pin)
    for finding in findings:
        print('FAIL ' + finding)
    if not findings:
        print(f"test-campaign {pin['version']}: {pin['fileCount']}/{pin['fileCount']} archived files match {pin['commit']}")
    return int(bool(findings))


if __name__ == '__main__':
    raise SystemExit(main())
