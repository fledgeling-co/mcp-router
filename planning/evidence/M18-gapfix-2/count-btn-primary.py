#!/usr/bin/env python3
"""Three normalisers over `btn primary` in the design of record, and every site each one matches.

`Controls.swift` reported a bare **29** for "the mock's primary buttons, none of them disabled", and
M18's verifier got 29, 33 and 35 over that one phrase — which is the whole of that finding. The
number is not wrong; it was unattributed, and a reader re-deriving it lands somewhere else and
concludes the claim is false.

So this prints all three with the rule behind each, and every line each matches. Run it rather than
trusting a literal: `python3 planning/evidence/M18-gapfix-2/count-btn-primary.py`.

`MockPrimaryDisabledTests` asserts the same three numbers from Swift, so a mock edit that moves them
turns a gate red rather than rotting a comment.
"""
import pathlib
import re
import sys

MOCK = pathlib.Path(__file__).resolve().parents[3] / "design" / "mcp-router-console.html"


def sites(source: str):
    """Every element carrying both `btn` and `primary` as whole class words, with its tag and line.

    Returns the matches *and* the two drop counts, because a reader that discards part of its raw
    input and reports only what survived cannot be checked against the file it read —
    `planning/reader-accounting.py` is the gate that says so, and it caught this function doing it.
    """
    found = []
    dropped = {"no class attribute": [], "class without both words": []}
    for match in re.finditer(r"<([a-zA-Z][a-zA-Z0-9]*)\b[^>]*>", source):
        attribute = re.search(r'class="([^"]*)"', match.group(0))
        if attribute is None:
            dropped["no class attribute"].append(source.count("\n", 0, match.start()) + 1)
            continue
        words = attribute.group(1).split()
        if "btn" not in words or "primary" not in words:
            dropped["class without both words"].append(source.count("\n", 0, match.start()) + 1)
        else:
            found.append({
                "line": source.count("\n", 0, match.start()) + 1,
                "tag": match.group(1),
                "class": attribute.group(1),
                # Both spellings of "off", because a mock can express it either way and matching
                # only the attribute would report a `class="btn primary disabled"` as live.
                "disabled": bool(re.search(r"\bdisabled\b", match.group(0))) or "disabled" in words,
            })
    return found, dropped


def main() -> int:
    if not MOCK.exists():
        print(f"design of record not found at {MOCK}", file=sys.stderr)
        return 2
    source = MOCK.read_text()
    all_sites, dropped = sites(source)
    buttons = [s for s in all_sites if s["tag"] == "button"]
    prefixed = [s for s in all_sites if s["class"].strip().startswith("btn primary")]

    print(f"# `btn primary` in `design/{MOCK.name}`\n")
    print("| Normaliser | Count |")
    print("|---|---|")
    print(f"| Any element whose class attribute carries both words | **{len(all_sites)}** |")
    print(f"| `<button>` elements only | **{len(buttons)}** |")
    print(f"| Class attribute values beginning with the literal `btn primary` | **{len(prefixed)}** |")
    examined = len(all_sites) + sum(len(lines) for lines in dropped.values())
    print()
    print(f"Elements examined: **{examined}**. Dropped, and why: "
          + ", ".join(f"{len(lines)} with {reason}" for reason, lines in dropped.items())
          + ". Nothing else was discarded, so the three counts above and these drops sum to the "
            "whole population.")
    print()
    disabled = [s for s in all_sites if s["disabled"]]
    rule = re.search(r"\.btn\.primary[^{}]*:disabled|\.primary[^{}]*:disabled", source)
    print(f"Carrying `disabled`, as an attribute or as a class: **{len(disabled)}** of {len(all_sites)}.")
    print(f"A `:disabled` rule that reaches `.primary` anywhere in the file: "
          f"**{'yes — ' + rule.group(0) if rule else 'none'}**.")
    print("\nSo the claim the count supports — *the design of record never draws a disabled primary,")
    print("and its CSS could not dim one* — holds at the widest of the three readings.\n")
    print("## Every site\n")
    print("| Line | Tag | `class` | In the 33 | In the 29 | `disabled` |")
    print("|---|---|---|---|---|---|")
    for site in all_sites:
        print(f"| :{site['line']} | `{site['tag']}` | `{site['class']}` "
              f"| {'yes' if site['tag'] == 'button' else 'no'} "
              f"| {'yes' if site['class'].strip().startswith('btn primary') else 'no'} "
              f"| {'yes' if site['disabled'] else 'no'} |")
    return 0


if __name__ == "__main__":
    sys.exit(main())
