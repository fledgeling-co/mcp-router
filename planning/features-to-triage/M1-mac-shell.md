---
status: completed
shipped-by: 10cad44
---

# M1 — Mac window shell, menu bar commands, keyboard

**Depends on:** F2, F3.

The three-zone window every other Mac surface renders into: 33pt titlebar, 52pt unified
toolbar, 256pt sidebar with inset-rounded selection at radius 8.

- The sidebar's two groups (Running / Library) with live counts, and the at-rest readout
  in its footer — child processes running against servers declared, plus the real
  last-60s trace. **Only numbers the router observes**; no invented memory saving.
- The complete menu bar: MCP Router / File / Edit / View / Window / Help, every command
  reachable, with the shortcut map from DESIGN.md §8 bound and a visible accent focus
  ring.
- Window state restoration, and the scroll-edge effect where content meets the toolbar.

Deep link: `design/mocks/prototype.html?only=mac`.
