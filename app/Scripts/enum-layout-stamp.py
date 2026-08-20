#!/usr/bin/env python3
"""Force a clean rebuild when an enum's case list changes.

Swift encodes one enum inside another's spare tag inhabitants — `Choice.live` lives in a
spare inhabitant of `Scenario`'s tag here — so adding or removing a case changes the memory
layout of every type that stores it. SwiftPM does not always rebuild the object files that
depend on that layout, and a stale one compares a value that no longer means what it thinks.

Measured on 2026-08-20 (DEF-008): adding a 14th `Scenario` case produced
`(… → .live) == (.live → .fixture(…cleanupSkills))` on two guards that return `.live`
unconditionally — an assertion failure impossible given the source. The mirror case is the
reason this script exists: a stale build can as easily produce a false green, and a gate that
can be green for the wrong reason is not a gate.

The stamp is the case list of every enum in the package, so it moves when a layout can move
and stays put when ordinary code changes. `switch` cases do not count: a case is only
collected at the brace depth directly inside its own `enum` body, and a switch is always
deeper than that.

Exit 0 always. It prints what it did; the caller decides nothing.
"""
import hashlib
import json
import pathlib
import re
import shutil
import sys

ENUM = re.compile(r'\b(?:indirect\s+)?enum\s+([A-Za-z_][A-Za-z0-9_]*)')
CASE = re.compile(r'^\s*(?:@\w+\s+)*case\s+(.+?)\s*$')
LINE_COMMENT = re.compile(r'//.*$')


def case_lists(path: pathlib.Path) -> dict[str, list[str]]:
    """Every enum in one file, mapped to the ordered case list directly in its body.

    Works on a one-line declaration (`enum E { case a, b }`) as well as a multi-line one:
    the line is split on its braces and each fragment is attributed to whatever enum body
    is open at that point, so a case never depends on sitting on a line of its own.
    """
    found: dict[str, list[str]] = {}
    depth = 0
    stack: list[tuple[str, int]] = []   # (enum name, body depth)
    in_block_comment = False

    for raw in path.read_text(errors='replace').splitlines():
        line = raw
        if in_block_comment:
            if '*/' in line:
                line = line.split('*/', 1)[1]
                in_block_comment = False
            else:
                continue
        if '/*' in line:
            head, _, tail = line.partition('/*')
            if '*/' in tail:
                line = head + tail.split('*/', 1)[1]
            else:
                line, in_block_comment = head, True
        line = LINE_COMMENT.sub('', line)

        # Walk the line brace by brace so a declaration and its cases can share one line.
        for fragment, brace in _fragments(line):
            if stack and depth == stack[-1][1]:
                for case in _cases_in(fragment):
                    found.setdefault(stack[-1][0], []).append(case)
            if brace == '{':
                m = ENUM.search(fragment)
                depth += 1
                if m:
                    stack.append((m.group(1), depth))
            elif brace == '}':
                depth -= 1
                while stack and depth < stack[-1][1]:
                    stack.pop()
    return found


def _fragments(line: str):
    """Split a line into (text, following-brace) pairs; the last brace is None."""
    start = 0
    for i, ch in enumerate(line):
        if ch in '{}':
            yield line[start:i], ch
            start = i + 1
    yield line[start:], None


def _cases_in(fragment: str) -> list[str]:
    """The case declarations in one brace-free fragment, normalised."""
    out = []
    for part in fragment.split(';'):
        m = CASE.match(part)
        if m:
            out.append(' '.join(m.group(1).split()))
    return out


def stamp(root: pathlib.Path) -> tuple[str, int]:
    table: dict[str, list[str]] = {}
    for f in sorted(root.rglob('*.swift')):
        if '.build' in f.parts or '.derived' in f.parts:
            continue
        for name, cases in case_lists(f).items():
            table[f'{f.relative_to(root)}::{name}'] = cases
    blob = json.dumps(table, sort_keys=True)
    return hashlib.sha256(blob.encode()).hexdigest(), len(table)


def main() -> int:
    app = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else 'app').resolve()
    current, count = stamp(app)
    record = app / '.build' / 'enum-layout.stamp'
    previous = record.read_text().strip() if record.is_file() else None

    if previous == current:
        print(f'enum layout unchanged across {count} enums — incremental build is safe')
        return 0

    if previous is not None:
        build = app / '.build'
        print(f'enum layout CHANGED across {count} enums ({previous[:12]} -> {current[:12]})')
        print('removing app/.build: a stale object file compiled against the old case list can')
        print('report a failure that is impossible given the source, or a pass that is not real')
        shutil.rmtree(build, ignore_errors=True)
    else:
        print(f'no previous enum stamp — recording {current[:12]} across {count} enums')

    record.parent.mkdir(parents=True, exist_ok=True)
    record.write_text(current + '\n')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
