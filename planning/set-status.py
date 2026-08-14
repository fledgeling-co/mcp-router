#!/usr/bin/env python3
"""Set the status dot on orchestrator-hierarchy.html nodes.

The hierarchy is hand-authored SVG, so status lives in one circle per node group and
nothing regenerates it. Refreshing it by hand is how it silently went four merges stale.

    python3 planning/set-status.py merged F1 F2 F3 R1
    python3 planning/set-status.py running M1 R2 R3 I1
    python3 planning/set-status.py todo M6
"""
import re
import sys
from pathlib import Path

HTML = Path(__file__).resolve().parent.parent / "orchestrator-hierarchy.html"

# Deliberately NOT the category hues. The legend already spends #30D158 on "mac" and
# #FF9230 on "router", so a green dot would read as a category rather than a state. The
# fill/ring distinction carries the meaning instead, and survives greyscale.
STYLES = {
    "merged": 'fill="#fff" stroke="#fff"',
    "running": 'fill="none" stroke="#fff" stroke-width="2"',
    "blocked": 'fill="#FF4245" stroke="#FF4245"',
    "todo": 'fill="none" stroke="rgba(255,255,255,.3)"',
}


def main() -> int:
    if len(sys.argv) < 3 or sys.argv[1] not in STYLES:
        sys.exit(f"usage: set-status.py {{{'|'.join(STYLES)}}} <ID>...")
    style, ids = STYLES[sys.argv[1]], set(sys.argv[2:])
    src = HTML.read_text()

    seen, out, cursor = set(), [], 0
    for node in re.finditer(r'data-id="([A-Z0-9]+)"', src):
        ident = node.group(1)
        if ident not in ids:
            continue
        # The node's own circle is the first one after its data-id and before the next group.
        tail = src[node.end():]
        stop = tail.find('<g class="n"')
        circle = re.search(r'<circle[^>]*?/>', tail if stop < 0 else tail[:stop])
        if not circle:
            sys.exit(f"{ident}: no status circle in its group — the SVG shape changed")
        start = node.end() + circle.start()
        out.append(src[cursor:start])
        # Strip any stroke-width a previous state left behind before substituting, so
        # running -> merged does not carry the ring's weight into the filled dot.
        normalised = re.sub(r'\s*stroke-width="[^"]*"', "", circle.group(0))
        out.append(re.sub(r'fill="[^"]*" stroke="[^"]*"', style, normalised))
        cursor = node.end() + circle.end()
        seen.add(ident)

    missing = ids - seen
    if missing:
        sys.exit(f"no such node(s): {', '.join(sorted(missing))}")
    out.append(src[cursor:])
    HTML.write_text("".join(out))
    print(f"{sys.argv[1]}: {' '.join(sorted(seen))}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
