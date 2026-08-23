#!/usr/bin/env python3
"""Where each sheet's keyboard shortcuts and Cancel button styles are actually written.

The verifier's Finding 2: the shortcut table in `planning/progress/M18.md` put the **`Button(`
declaration line** under columns headed `.cancelAction` and `.defaultAction`, and its
`RemoveServerDialog` row landed on a comment line inside the same commit that wrote the table.
This is the instrument that produces the corrected table, so the next reader can re-derive it
rather than trust it.

Normaliser, stated once.
  * A **sheet view** is a line matching `^\\s*struct <Name>(Sheet|Dialog): View \\{` anywhere under
    `app/Sources` — the whole source tree, not the `MCPRouterUI` subtree the shipped scanner reads.
  * Its **block** runs to the line where brace depth counted from the declaration returns to zero.
  * `//` comments are removed before matching, so a shortcut named in prose is not counted as one
    written in code. String literals are kept, because a Cancel label is a literal.
  * A **shortcut line** is a line whose stripped form contains `.keyboardShortcut(<token>)`.
  * A **style line** is a line whose stripped form contains `.buttonStyle(<Type>())`.

Reports the files read and the two drop counts, per `planning/reader-accounting.py`'s rule that a
reader accounts for its whole input.

Usage: `planning/evidence/M18-gapfix-3/shortcut-lines.py [--self-test]` from the repository root.
"""
import pathlib
import re
import sys

DECL = re.compile(r"^\s*struct ([A-Za-z0-9]+)(?:<[^>]*>)?: View \{")
SHORTCUT = re.compile(r"\.keyboardShortcut\(\s*\.?([A-Za-z0-9_\"]+)")
STYLE = re.compile(r"\.buttonStyle\(\s*\.?([A-Za-z0-9_]+)")
BUTTON_LABEL = re.compile(r'Button\(\s*"([^"]*)"')


def without_comment(line: str) -> str:
    """`//` outside a string literal to end of line, literals kept."""
    kept, in_string, previous = [], False, ""
    for character in line:
        if character == '"':
            in_string = not in_string
        if not in_string and character == "/" and previous == "/":
            kept.pop()
            break
        kept.append(character)
        previous = character
    return "".join(kept)


def scan(root: pathlib.Path):
    sheets, files_read, lines_read, dropped_comment, dropped_plain = [], 0, 0, 0, 0
    for path in sorted(root.rglob("*.swift")):
        files_read += 1
        raw = path.read_text(encoding="utf-8").split("\n")
        lines_read += len(raw)
        stripped = [without_comment(line) for line in raw]
        for index, line in enumerate(stripped):
            match = DECL.match(line)
            if not match:
                continue
            depth, end = 0, len(stripped)
            for cursor in range(index, len(stripped)):
                depth += stripped[cursor].count("{") - stripped[cursor].count("}")
                if depth <= 0 and cursor > index:
                    end = cursor + 1
                    break
            name = match.group(1)
            if not (name.endswith("Sheet") or name.endswith("Dialog")):
                continue
            shortcuts, styles, cancels = {}, [], []
            for cursor in range(index, end):
                for token in SHORTCUT.findall(stripped[cursor]):
                    shortcuts.setdefault(token, []).append(cursor + 1)
                for token in STYLE.findall(stripped[cursor]):
                    styles.append((cursor + 1, token))
                for label in BUTTON_LABEL.findall(stripped[cursor]):
                    if label == "Cancel":
                        cancels.append(cursor + 1)
            sheets.append({
                "name": name,
                "file": str(path.relative_to(root.parent.parent)),
                "line": index + 1,
                "shortcuts": shortcuts,
                "styles": styles,
                "cancels": cancels,
            })
        for line, bare in zip(stripped, raw):
            if line != bare:
                dropped_comment += 1
            elif not line.strip():
                dropped_plain += 1
    return sheets, files_read, lines_read, dropped_comment, dropped_plain


def cancel_style(sheet):
    """The style written on the modifier line immediately after each `Button("Cancel")`."""
    out = []
    for cancel in sheet["cancels"]:
        following = [(line, token) for line, token in sheet["styles"] if line > cancel]
        out.append((cancel, following[0][1] if following else "—", following[0][0] if following else 0))
    return out


def main() -> int:
    root = pathlib.Path.cwd() / "app" / "Sources"
    if not root.is_dir():
        print("run me from the repository root", file=sys.stderr)
        return 2
    sheets, files_read, lines_read, dropped_comment, dropped_plain = scan(root)

    if "--self-test" in sys.argv:
        # Presence control, both directions: a fixture the reader must see, and one it must not.
        fixture = '''
        struct ZZProbeSheet: View {
            var body: some View {
                Button("Cancel") { }
                    .buttonStyle(ProminentButtonStyle())
                    .keyboardShortcut(.cancelAction)
                // .keyboardShortcut(.defaultAction) — prose, not code
            }
        }
        struct ZZProbeHost: View {
            var body: some View { Button("Cancel") { }.keyboardShortcut(.cancelAction) }
        }
        '''
        probe = root / "MCPRouterUI" / "ZZProbe.swift"
        probe.write_text(fixture)
        try:
            armed, *_ = scan(root)
        finally:
            probe.unlink()
        found = {s["name"]: s for s in armed}
        assert "ZZProbeSheet" in found, "the reader missed a planted sheet"
        assert "ZZProbeHost" not in found, "the reader counted a non-sheet view as a sheet"
        assert found["ZZProbeSheet"]["shortcuts"] == {"cancelAction": [6]}, found["ZZProbeSheet"]
        assert cancel_style(found["ZZProbeSheet"]) == [(4, "ProminentButtonStyle", 5)]
        assert len(armed) == len(sheets) + 1, "the population did not move by exactly one"
        print(f"self-test: armed both ways over {files_read} files; population {len(sheets)} -> {len(armed)}")
        return 0

    print(f"files read: {files_read}   lines read: {lines_read}   "
          f"lines carrying a comment: {dropped_comment}   blank lines: {dropped_plain}")
    print(f"sheet views: {len(sheets)}\n")
    header = f"{'sheet view':28} {'file:decl':56} {'.cancelAction':14} {'.defaultAction':14} Cancel style"
    print(header)
    print("-" * len(header))
    for sheet in sorted(sheets, key=lambda s: s["name"]):
        cancel = ",".join(str(n) for n in sheet["shortcuts"].get("cancelAction", [])) or "—"
        default = ",".join(str(n) for n in sheet["shortcuts"].get("defaultAction", [])) or "—"
        styles = cancel_style(sheet)
        drawn = ", ".join(f"{token}@{line}" for _, token, line in styles) or "—"
        print(f"{sheet['name']:28} {sheet['file'] + ':' + str(sheet['line']):56} {cancel:14} {default:14} {drawn}")

    with_escape = [s["name"] for s in sheets if s["shortcuts"].get("cancelAction")]
    print(f"\nESCAPE PATH:    {len(with_escape)} of {len(sheets)}")
    print(f"NO ESCAPE PATH: {len(sheets) - len(with_escape)} of {len(sheets)} -> "
          + ", ".join(sorted(s['name'] for s in sheets if s['name'] not in with_escape)))
    filled = [(s["name"], line, token) for s in sheets for _, token, line in cancel_style(s)
              if token == "ProminentButtonStyle"]
    print(f"ACCENT-FILLED CANCEL: {len(filled)} -> {filled or '(none)'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
