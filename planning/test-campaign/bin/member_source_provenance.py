#!/usr/bin/env python3
"""Typed production-source bindings, counted separately from control actuation.

Legacy design declarations remain explicitly unverified. Their exact population is pinned;
new members cannot acquire that exception by editing the sidecar alone. A source binding proves
a declaration, never build membership, reachability, handler behavior or a passing UI action.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import tempfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[3]
CAMPAIGN = ROOT / 'planning/test-campaign'
BASELINE_SHA256 = '7f439dfafdd2bde829684d3ed2ec2c41fc15701ac73f6dbe8e06439fabc73015'
REQUIRED_BINDINGS = {
    '["SURF-003","control","Cancel"]', '["SURF-007","control","Cancel"]',
    '["SURF-045","operation","LogonTaskSupervisor.Register"]',
    '["SURF-045","operation","LogonTaskSupervisor.Unregister"]',
}
UI_TYPES = {'Button', 'Toggle', 'Picker', 'TextField', 'SecureField', 'Menu', 'Link'}
XAML_PROPERTIES = {
    'Button': ('Content', 'AutomationProperties.Name'),
    'ToggleButton': ('Content', 'AutomationProperties.Name'),
    'CheckBox': ('Content', 'AutomationProperties.Name'),
    'RadioButton': ('Content', 'AutomationProperties.Name'),
    'ToggleSwitch': ('Header', 'AutomationProperties.Name'),
    'ComboBox': ('Header', 'AutomationProperties.Name'),
    'TextBox': ('Header', 'AutomationProperties.Name'),
    'PasswordBox': ('Header', 'AutomationProperties.Name'),
    'MenuFlyoutItem': ('Text', 'AutomationProperties.Name'),
    'MenuBarItem': ('Title', 'AutomationProperties.Name'),
}
XAML_UI_NAMESPACE = 'http://schemas.microsoft.com/winfx/2006/xaml/presentation'
TOKEN = re.compile(r'''//[^\n]*|/\*|@"(?:[^"]|"")*"|"""[\s\S]*?"""|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])' ''', re.VERBOSE)


def key(surface: str, kind: str, member: str) -> str:
    return json.dumps([surface, kind, member], ensure_ascii=False, separators=(',', ':'))


def population(inventory: dict) -> set[str]:
    result: set[str] = set()
    for surface in inventory.get('surface', []):
        for kind in ['control', 'operation']:
            for member in surface.get(kind + 's', []):
                result.add(key(surface['id'], kind, member))
    return result


def conditional_source(source: str, platform: str, configuration: str) -> str:
    """Unknown conditional branches cannot establish a binding; keep line positions stable."""
    result = []
    stack: list[tuple[bool, bool, bool]] = []
    active = True
    for line in source.splitlines(keepends=True):
        match = re.match(r'\s*#(if|elseif|else|endif)\b\s*(.*)', line)
        if not match:
            result.append(line if active else '\n' * line.count('\n'))
            continue
        directive, expression = match.groups()
        expression = expression.strip()
        value = {'os(macOS)': platform == 'macos', 'os(iOS)': platform == 'ios',
                 'DEBUG': configuration == 'debug', '!DEBUG': configuration == 'release'}.get(expression)
        if directive == 'if':
            stack.append((active, value is True, value is None))
            active = active and value is True
        elif directive == 'elseif' and stack:
            parent, taken, unknown = stack[-1]
            active = parent and not taken and not unknown and value is True
            stack[-1] = (parent, taken or value is True, unknown or value is None)
        elif directive == 'else' and stack:
            parent, taken, unknown = stack[-1]
            active = parent and not taken and not unknown
            stack[-1] = (parent, True, unknown)
        elif directive == 'endif' and stack:
            active = stack.pop()[0]
        else:
            raise ValueError('unbalanced conditional compilation directives')
        result.append('\n' * line.count('\n'))
    if stack:
        raise ValueError('unterminated conditional compilation directive')
    return ''.join(result)


def code_and_strings(source: str) -> tuple[str, list[str | None]]:
    """Mask comments/strings before matching declarations. Swift block comments nest."""
    pieces: list[str] = []
    strings: list[str | None] = []
    cursor = 0
    while match := TOKEN.search(source, cursor):
        gap = source[cursor:match.start()]
        if '"' in gap or "'" in gap:
            raise ValueError('unsupported or unterminated source literal')
        pieces.append(gap)
        token = match.group()
        end = match.end()
        if token == '/*':
            depth = 1
            while depth and end < len(source):
                next_open, next_close = source.find('/*', end), source.find('*/', end)
                if next_close < 0:
                    raise ValueError('unterminated block comment')
                if 0 <= next_open < next_close:
                    depth += 1
                    end = next_open + 2
                else:
                    depth -= 1
                    end = next_close + 2
            if depth:
                raise ValueError('unterminated block comment')
            pieces.append(' ')
        elif token.startswith('//'):
            pieces.append(' ')
        else:
            try:
                value = json.loads(token) if not token.startswith(('"""', '@')) else None
            except json.JSONDecodeError:
                value = None  # interpolation/raw/verbatim labels need an explicit richer adapter
            strings.append(value)
            pieces.append('__LITERAL_%d__' % (len(strings) - 1))
        cursor = end
    tail = source[cursor:]
    if '"' in tail or "'" in tail:
        raise ValueError('unsupported or unterminated source literal')
    pieces.append(tail)
    return ''.join(pieces), strings


def declaration_body(code: str, owner: str) -> str:
    matches = list(re.finditer(r'\b(?:struct|class|record|enum)\s+' + re.escape(owner)
                               + r'\b[^{};]*\{', code))
    if len(matches) != 1:
        raise ValueError('enclosing declaration missing or ambiguous: ' + owner)
    start = matches[0].end()
    depth = 1
    for offset in range(start, len(code)):
        depth += (code[offset] == '{') - (code[offset] == '}')
        if depth == 0:
            return code[start:offset]
    raise ValueError('enclosing declaration is not balanced: ' + owner)


def without_nested_types(body: str) -> str:
    """A control on another nested type cannot satisfy its parent's binding."""
    spans: list[tuple[int, int]] = []
    covered = 0
    for match in re.finditer(r'\b(?:struct|class|record|enum)\s+[A-Za-z_]\w*\b[^{};]*\{', body):
        if match.start() < covered:
            continue
        depth = 1
        end = match.end()
        while depth and end < len(body):
            depth += (body[end] == '{') - (body[end] == '}')
            end += 1
        if depth:
            raise ValueError('nested declaration is not balanced')
        spans.append((match.start(), end))
        covered = end
    for start, end in reversed(spans):
        body = body[:start] + ' ' * (end - start) + body[end:]
    return body


def validate_binding(root: Path, member_key: str, binding: dict) -> None:
    _surface, kind, member = json.loads(member_key)
    path = binding.get('path', '')
    relative = Path(path)
    allowed = ('app/Sources/', 'app/MCPRouterIOS/', 'app/Windows/')
    if relative.is_absolute() or '..' in relative.parts or not path.startswith(allowed):
        raise ValueError('binding must name contained production source, not a mock/test')
    source_path = root / relative
    resolved = source_path.resolve()
    if not resolved.is_relative_to(root.resolve()):
        raise ValueError('source escapes its repository')
    if not resolved.relative_to(root.resolve()).as_posix().startswith(allowed):
        raise ValueError('source resolves outside production roots')
    parent = root
    for part in relative.parts:
        parent = parent / part
        if parent.is_symlink():
            raise ValueError('source path uses a symlink; name the canonical production path')
    if not source_path.is_file():
        raise ValueError('source file is missing: ' + path)
    source = source_path.read_text(encoding='utf-8-sig')
    adapter = binding.get('adapter')
    owner = binding.get('declaration', '')
    if not owner:
        raise ValueError('binding needs an enclosing declaration')
    if adapter == 'xaml-control-label':
        if kind != 'control' or relative.suffix != '.xaml':
            raise ValueError('a XAML control cannot establish an operation')
        if '<!DOCTYPE' in source:
            raise ValueError('DTD-backed XAML is outside this adapter')
        document = ET.fromstring(source)
        if document.get('{http://schemas.microsoft.com/winfx/2006/xaml}Class') != owner:
            raise ValueError('XAML enclosing class does not match')
        hits = 0
        for element in document.iter():
            if not element.tag.startswith('{' + XAML_UI_NAMESPACE + '}'):
                continue
            properties = XAML_PROPERTIES.get(element.tag.split('}')[-1], ())
            if any(element.get(prop) == member for prop in properties):
                hits += 1
    else:
        platform, configuration = binding.get('platform'), binding.get('configuration')
        if platform not in ['macos', 'ios', 'windows'] or configuration not in ['debug', 'release']:
            raise ValueError('binding needs explicit platform and configuration')
        code, literals = code_and_strings(source)
        code = conditional_source(code, platform, configuration)
        body = without_nested_types(declaration_body(code, owner))
        if adapter == 'swift-control-label':
            if kind != 'control' or relative.suffix != '.swift':
                raise ValueError('a Swift UI control cannot establish an operation')
            if not re.search(r'\bimport\s+SwiftUI\b', code):
                raise ValueError('Swift UI source does not import SwiftUI')
            if not re.search(r'\b(?:struct|class)\s+' + re.escape(owner) + r'\b[^{};]*:\s*[^{};]*\bView\b', code):
                raise ValueError('Swift enclosing declaration does not declare View conformance')
            for control in UI_TYPES:
                if re.search(r'\b(?:struct|class|enum|func|typealias|let|var)\s+' + control + r'\b', code):
                    raise ValueError('Swift UI type is shadowed in this source: ' + control)
            hits = sum(literals[int(match.group(2))] == member for match in re.finditer(
                r'(?<![A-Za-z0-9_])(' + '|'.join(sorted(UI_TYPES)) + r')\s*\(\s*__LITERAL_(\d+)__\s*[,)]', body))
        elif adapter == 'csharp-method':
            symbol = binding.get('symbol', '')
            if kind != 'operation' or relative.suffix != '.cs' or member != owner + '.' + symbol:
                raise ValueError('a C# method cannot establish a UI control or unrelated member')
            pattern = (r'\b(?:public|internal|protected|private)\s+(?:(?:static|async|virtual|override|sealed)\s+)*'
                       r'[A-Za-z_][A-Za-z0-9_<>,?.\[\] ]*\s+' + re.escape(symbol)
                       + r'\s*\([^{};]*\)\s*(?:\{|=>)')
            hits = len(list(re.finditer(pattern, body)))
        else:
            raise ValueError('unsupported typed adapter')
    if hits != 1:
        raise ValueError('typed anchor missing or ambiguous (%d matches)' % hits)


def audit(root: Path, inventory: dict, bindings: dict, legacy: set[str]) -> dict:
    declared = population(inventory)
    findings: list[str] = []
    valid: list[str] = []
    unverified: list[str] = []
    for member_key in sorted(declared):
        binding = bindings.get(member_key)
        if binding is None:
            if member_key in legacy:
                unverified.append(member_key)
            else:
                findings.append(member_key + ': new member has no typed source binding')
            continue
        try:
            validate_binding(root, member_key, binding)
            valid.append(member_key)
        except (ValueError, OSError, ET.ParseError) as error:
            findings.append(member_key + ': ' + str(error))
    for orphan in sorted(bindings.keys() - declared):
        findings.append(orphan + ': binding names no declared member')
    counts = {}
    for kind in ['control', 'operation']:
        mine = {value for value in declared if json.loads(value)[1] == kind}
        counts[kind] = {'declared': len(mine), 'source_bound': len(mine & set(valid)),
                        'legacy_unverified': len(mine & set(unverified))}
    return {'declared': len(declared), 'source_bound': len(valid), 'legacy_unverified': len(unverified), 'counts': counts,
            'valid': valid, 'unverified': unverified, 'findings': findings,
            'limits': 'Source declarations only. Build membership, reachability and actuation are separate.'}


def audit_files(root: Path, campaign: Path) -> dict:
    baseline = json.loads((campaign / 'member-source-baseline.json').read_text(encoding='utf-8'))
    canonical = json.dumps(baseline['members'], ensure_ascii=False, separators=(',', ':')).encode()
    if hashlib.sha256(canonical).hexdigest() != BASELINE_SHA256:
        raise ValueError('legacy unverified population differs from its immutable source pin')
    bindings = json.loads((campaign / 'member-source-bindings.json').read_text(encoding='utf-8'))['bindings']
    if not REQUIRED_BINDINGS <= bindings.keys():
        raise ValueError('a previously checked typed binding disappeared')
    return audit(root, json.loads((campaign / 'inventory.json').read_text(encoding='utf-8-sig')),
                 bindings, set(baseline['members']))


def selftest() -> None:
    checks: list[str] = []
    def expect(condition: bool, name: str) -> None:
        if not condition:
            raise AssertionError(name)
        checks.append(name)
    with tempfile.TemporaryDirectory(prefix='member-source-controls-') as directory:
        root = Path(directory)
        swift = root / 'app/Sources/Demo.swift'
        swift.parent.mkdir(parents=True)
        swift.write_text('import SwiftUI\n#if os(macOS)\nstruct Demo: View { var body: some View { Button("Foo.Bar") {} } }\n#endif\n')
        cs = root / 'app/Windows/Worker.cs'
        cs.parent.mkdir(parents=True)
        cs.write_text('public class Worker { public void Run() {} }')
        ck, ok = key('S', 'control', 'Foo.Bar'), key('S', 'operation', 'Worker.Run')
        inventory = {'surface': [{'id': 'S', 'plane': 'mixed', 'controls': ['Foo.Bar'], 'operations': ['Worker.Run']}]}
        bindings = {ck: {'adapter': 'swift-control-label', 'path': 'app/Sources/Demo.swift', 'declaration': 'Demo', 'platform': 'macos', 'configuration': 'debug'},
                    ok: {'adapter': 'csharp-method', 'path': 'app/Windows/Worker.cs', 'declaration': 'Worker', 'symbol': 'Run', 'platform': 'windows', 'configuration': 'release'}}
        def findings() -> list[str]: return audit(root, inventory, bindings, set())['findings']
        expect(not findings(), 'dotted label and mixed control/operation bind independently')
        original = swift.read_text()
        for name, body in [
            ('unrelated literal', 'struct Demo: View { let note = "Foo.Bar" }'),
            ('comment only', 'struct Demo: View { /* Button("Foo.Bar") {} */ }'),
            ('string containing code', 'struct Demo: View { let note = "Button(\\"Foo.Bar\\") {}" }'),
            ('wrong platform', '#if os(iOS)\nstruct Demo: View { var body: some View { Button("Foo.Bar") {} } }\n#endif'),
            ('other nested declaration', 'struct Demo: View { struct Other { var body: some View { Button("Foo.Bar") {} } } }'),
            ('unknown conditional', '#if canImport(Unknown)\nstruct Demo: View { var body: some View { Button("Foo.Bar") {} } }\n#endif'),
        ]:
            swift.write_text('import SwiftUI\n' + body)
            expect(bool(findings()), name + ' cannot establish a control')
        swift.write_text(original)
        swift.rename(swift.with_suffix('.moved'))
        expect(bool(findings()), 'moved source refused')
        swift.with_suffix('.moved').rename(swift)
        saved = bindings.pop(ck)
        expect(bool(findings()), 'missing new-member binding refused')
        bindings[ck] = dict(bindings[ok])
        expect(bool(findings()), 'method cannot be laundered into controls')
        bindings[ck] = dict(saved, path='design/mocks/prototype.html')
        expect(bool(findings()), 'design mock is not production source')
        bindings[ck] = saved
        for body in ['public class Worker { public class Other { public void Run() {} } }',
                     'public class Worker { /* public void Run() {} */ }',
                     'public class Worker { private string note = "public void Run() {}"; }']:
            cs.write_text(body)
            expect(bool(findings()), 'method must belong to its named declaration, not text')
        cs.write_text('public class Worker { public void Run() {} }')
        xaml = root / 'app/Windows/Demo.xaml'
        xaml.write_text('<Page xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" x:Class="Demo"><Button Content="Foo.Bar"/><!-- Button Content="Foo.Bar" --></Page>')
        bindings[ck] = {'adapter': 'xaml-control-label', 'path': 'app/Windows/Demo.xaml', 'declaration': 'Demo'}
        expect(not findings(), 'XAML typed label accepts punctuation and excludes comments')
        xaml.write_text('<Page xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" x:Class="Demo"><TextBlock Content="Foo.Bar"/></Page>')
        expect(bool(findings()), 'unrelated XAML text is not a control')
        bindings[ck] = saved
        expect(not findings(), 'restoration silent')
        legacy = audit(root, inventory, {}, {ck, ok})
        expect(legacy['source_bound'] == 0 and legacy['legacy_unverified'] == 2
               and legacy['declared'] == 2 and not legacy['findings'], 'legacy declarations remain unverified, not source evidence')
        camp = root / 'planning/test-campaign'
        camp.mkdir(parents=True)
        baseline_bytes = (CAMPAIGN / 'member-source-baseline.json').read_bytes()
        (camp / 'member-source-baseline.json').write_bytes(baseline_bytes)
        (camp / 'member-source-bindings.json').write_text('{"bindings": {}}')
        try:
            audit_files(root, camp)
            expect(False, 'missing previously bound member refused')
        except ValueError as error:
            expect('previously checked' in str(error), 'missing previously bound member refused')
        tampered = json.loads(baseline_bytes)
        tampered['members'].append(key('S', 'control', 'Unreviewed legacy addition'))
        (camp / 'member-source-baseline.json').write_text(json.dumps(tampered))
        try:
            audit_files(root, camp)
            expect(False, 'baseline expansion refused')
        except ValueError as error:
            expect('immutable' in str(error), 'baseline expansion refused')
    print('member-source selftest: %d controls passed; zero actuation changes' % len(checks))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--selftest', action='store_true')
    parser.add_argument('--json', action='store_true')
    args = parser.parse_args()
    if args.selftest:
        selftest()
    try:
        report = audit_files(ROOT, CAMPAIGN)
    except (ValueError, OSError, KeyError) as error:
        print('member-source: not compared: ' + str(error))
        return 2
    if args.json:
        print(json.dumps(report, indent=2, ensure_ascii=False))
    else:
        for kind, count in report['counts'].items():
            print('Member source %ss: %d/%d typed bindings; %d legacy UNVERIFIED (not build or actuation evidence).'
                  % (kind, count['source_bound'], count['declared'], count['legacy_unverified']))
        for finding in report['findings']:
            print('  ' + finding)
    return 1 if report['findings'] else 0


if __name__ == '__main__':
    raise SystemExit(main())
