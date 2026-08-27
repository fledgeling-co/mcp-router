# mcp-router — campaign ledger

Lanes: macos-glass, ios-glass, swiftui, router-daemon, parity-wire

**Sample:** pairwise floor; 3-way on theme×viewport×surface (Mac boards) and role×state×network (honesty); oversample honesty-guardrails; drop high-contrast (no authored tokens); drop RTL (no localisation); pairing-transport cells blocked (I5: unimplemented)

20 surfaces · 5 flows · 8 components · 70 cases
63 pass · 3 fail · 0 skip · 4 n/a · 0 open · armed 63/63

> **The counts line above is stale, and G17 is not the item that gets to rewrite it.** It reads
> `20 surfaces · 5 flows · 8 components · 70 cases`; `inventory.json` and `cases.json` hold 26
> surfaces, 6 flows, 8 components and 87 cases as of 2026-08-27. It was already stale before this
> item (24 surfaces / 76 cases at `aab9190`), which is `D-g5-c` in `planning/progress/G5-gapfix*.md`
> and the campaign owner's to close together with `strict-ratchet.json`'s `58`. Correcting the
> figure here would fold a known open defect into a passing header. G17 added SURF-025, SURF-026,
> FLOW-006, REQ-026, DEF-058 and CASE-0151-CASE-0161, all listed above and all run.

| Case | Surface | State | Lane | Status | Armed | Evidence |
|---|---|---|---|---|---|---|
| CASE-0001 | SURF-001  |  | macos-glass | pass | yes | 5 |
| CASE-0002 | SURF-001  |  | macos-glass | n/a: posting Cmd+1–7 to a background pid does not change SwiftUI's focused scene (measured: title stayed Inbox then Activity); proving the shortcuts requires the window frontmost, which this campaign refuses |  | 3 |
| CASE-0008 | SURF-001  |  | swiftui | pass | yes | 3 |
| CASE-0101 | SURF-001  |  | macos-glass | pass | yes | 1 |
| CASE-0132 | SURF-001  |  | swiftui | pass | yes | 3 |
| CASE-0133 | SURF-001  |  | macos-glass | pass | yes | 2 |
| CASE-0003 | SURF-002  |  | macos-glass | pass | yes | 3 |
| CASE-0041 | SURF-002  |  | macos-glass | pass | yes | 3 |
| CASE-0042 | SURF-002  |  | macos-glass | pass | yes | 3 |
| CASE-0102 | SURF-002  |  | macos-glass | pass | yes | 1 |
| CASE-0011 | SURF-003  |  | macos-glass | pass | yes | 3 |
| CASE-0103 | SURF-003  |  | macos-glass | pass | yes | 1 |
| CASE-0127 | SURF-003  |  | swiftui | pass | yes | 1 |
| CASE-0128 | SURF-003  |  | swiftui | pass | yes | 1 |
| CASE-0012 | SURF-004  |  | macos-glass | pass | yes | 3 |
| CASE-0104 | SURF-004  |  | macos-glass | pass | yes | 1 |
| CASE-0129 | SURF-004  |  | swiftui | pass | yes | 1 |
| CASE-0013 | SURF-005  |  | macos-glass | pass | yes | 3 |
| CASE-0105 | SURF-005  |  | macos-glass | pass | yes | 1 |
| CASE-0134 | SURF-005  |  | macos-glass | pass | yes | 1 |
| CASE-0014 | SURF-006  |  | macos-glass | pass | yes | 5 |
| CASE-0106 | SURF-006  |  | macos-glass | pass | yes | 2 |
| CASE-0015 | SURF-007  |  | macos-glass | pass | yes | 3 |
| CASE-0107 | SURF-007  |  | macos-glass | pass | yes | 1 |
| CASE-0130 | SURF-007  |  | swiftui | pass | yes | 1 |
| CASE-0131 | SURF-007  |  | swiftui | pass | yes | 1 |
| CASE-0135 | SURF-007  |  | swiftui | pass | yes | 1 |
| CASE-0136 | SURF-007  |  | swiftui | pass | yes | 1 |
| CASE-0137 | SURF-007  |  | swiftui | pass | yes | 1 |
| CASE-0138 | SURF-007  |  | macos-glass | pass | yes | 2 |
| CASE-0139 | SURF-007  |  | macos-glass | pass | yes | 1 |
| CASE-0140 | SURF-007  |  | macos-glass | pass | yes | 2 |
| CASE-0141 | SURF-007  |  | macos-glass | pass | yes | 1 |
| CASE-0144 | SURF-007  |  | swiftui | pass | yes | 2 |
| CASE-0005 | SURF-008  |  | macos-glass | pass | yes | 4 |
| CASE-0007 | SURF-008  |  | macos-glass | pass | yes | 3 |
| CASE-0017 | SURF-008  |  | swiftui | pass | yes | 3 |
| CASE-0018 | SURF-008  |  | swiftui | pass | yes | 3 |
| CASE-0108 | SURF-008  |  | macos-glass | pass | yes | 1 |
| CASE-0004 | SURF-009  |  | macos-glass | n/a: NSStatusItem is not an AXPress target while MCPRouter is backgrounded; this campaign never activates, so the popover cannot be opened or photographed |  | 1 |
| CASE-0006 | SURF-009  |  | macos-glass | n/a: NSStatusItem is not an AXPress target while MCPRouter is backgrounded; inbox band never opened |  | 1 |
| CASE-0109 | SURF-009  |  | macos-glass | n/a: status item not pressable in background; SURF-009 popover uncaptured. Raster-visual of the popover is unreachable under the no-activate constraint |  | 1 |
| CASE-0010 | SURF-010  |  | macos-glass | fail |  | 2 |
| CASE-0110 | SURF-010  |  | macos-glass | fail |  | 1 |
| CASE-0142 | SURF-010  |  | macos-glass | pass | yes | 2 |
| CASE-0143 | SURF-010  |  | macos-glass | pass | yes | 1 |
| CASE-0009 | SURF-011  |  | swiftui | pass | yes | 3 |
| CASE-0016 | SURF-011  |  | macos-glass | pass | yes | 3 |
| CASE-0111 | SURF-011  |  | macos-glass | pass | yes | 1 |
| CASE-0020 | SURF-012  |  | ios-glass | pass | yes | 1 |
| CASE-0120 | SURF-012  |  | ios-glass | pass | yes | 1 |
| CASE-0021 | SURF-013  |  | ios-glass | pass | yes | 3 |
| CASE-0023 | SURF-013  |  | ios-glass | pass | yes | 3 |
| CASE-0121 | SURF-013  |  | ios-glass | pass | yes | 1 |
| CASE-0022 | SURF-014  |  | ios-glass | pass | yes | 1 |
| CASE-0040 | SURF-014  |  | ios-glass | fail | yes | 1 |
| CASE-0122 | SURF-014  |  | ios-glass | pass | yes | 1 |
| CASE-0030 | SURF-015  |  | router-daemon | pass | yes | 3 |
| CASE-0031 | SURF-015  |  | router-daemon | pass | yes | 3 |
| CASE-0032 | SURF-015  |  | router-daemon | pass | yes | 3 |
| CASE-0034 | SURF-015  |  | router-daemon | pass | yes | 3 |
| CASE-0033 | SURF-016  |  | router-daemon | pass | yes | 3 |
| CASE-0035 | SURF-016  |  | router-daemon | pass | yes | 3 |
| CASE-0037 | SURF-016  |  | router-daemon | pass | yes | 3 |
| CASE-0036 | SURF-017  |  | parity-wire | pass | yes | 10 |
| CASE-0123 | SURF-018  |  | ios-glass | pass | yes | 1 |
| CASE-0024 | SURF-018  |  | ios-glass | pass | yes | 1 |
| CASE-0126 | SURF-018  |  | swiftui | pass | yes | 1 |
| CASE-0124 | SURF-019  |  | ios-glass | pass | yes | 1 |
| CASE-0125 | SURF-020  |  | ios-glass | pass | yes | 1 |
| CASE-0152 | SURF-025  |  | swiftui | pass | yes | 5 |
| CASE-0153 | SURF-025  |  | swiftui | pass | yes | 5 |
| CASE-0154 | SURF-025  |  | swiftui | pass | yes | 5 |
| CASE-0155 | SURF-025  |  | swiftui | pass | yes | 5 |
| CASE-0156 | SURF-025  |  | swiftui | pass | yes | 5 |
| CASE-0157 | SURF-025  |  | swiftui | pass | yes | 4 |
| CASE-0158 | SURF-025  |  | swiftui | pass | yes | 5 |
| CASE-0159 | SURF-025  |  | swiftui | pass | yes | 5 |
| CASE-0160 | SURF-025  |  | swiftui | pass | yes | 4 |
| CASE-0161 | SURF-025  |  | swiftui | pass | yes | 3 |
| CASE-0151 | SURF-026  |  | router-daemon | pass | yes | 4 |
