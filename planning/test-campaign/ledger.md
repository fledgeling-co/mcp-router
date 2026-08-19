# mcp-router — campaign ledger

Lanes: macos-glass, ios-glass, swiftui, router-daemon, parity-wire

**Sample:** pairwise floor; 3-way on theme×viewport×surface (Mac boards) and role×state×network (honesty); oversample honesty-guardrails; drop high-contrast (no authored tokens); drop RTL (no localisation); pairing-transport cells blocked (I5: unimplemented)

17 surfaces · 5 flows · 8 components · 47 cases
33 pass · 4 fail · 0 skip · 10 n/a · 0 open · armed 33/33

| Case | Surface | State | Lane | Status | Armed | Evidence |
|---|---|---|---|---|---|---|
| CASE-0001 | SURF-001  |  | macos-glass | pass | yes | 5 |
| CASE-0002 | SURF-001  |  | macos-glass | n/a: posting Cmd+1–7 to a background pid does not change SwiftUI's focused scene (measured: title stayed Inbox then Activity); proving the shortcuts requires the window frontmost, which this campaign refuses |  | 1 |
| CASE-0008 | SURF-001  |  | swiftui | pass | yes | 3 |
| CASE-0101 | SURF-001  |  | macos-glass | pass | yes | 1 |
| CASE-0003 | SURF-002  |  | macos-glass | pass | yes | 3 |
| CASE-0041 | SURF-002  |  | macos-glass | pass | yes | 3 |
| CASE-0042 | SURF-002  |  | macos-glass | pass | yes | 3 |
| CASE-0102 | SURF-002  |  | macos-glass | pass | yes | 1 |
| CASE-0011 | SURF-003  |  | macos-glass | pass | yes | 3 |
| CASE-0103 | SURF-003  |  | macos-glass | pass | yes | 1 |
| CASE-0012 | SURF-004  |  | macos-glass | pass | yes | 3 |
| CASE-0104 | SURF-004  |  | macos-glass | pass | yes | 1 |
| CASE-0013 | SURF-005  |  | macos-glass | pass | yes | 3 |
| CASE-0105 | SURF-005  |  | macos-glass | pass | yes | 1 |
| CASE-0014 | SURF-006  |  | macos-glass | pass | yes | 5 |
| CASE-0106 | SURF-006  |  | macos-glass | pass | yes | 2 |
| CASE-0015 | SURF-007  |  | macos-glass | pass | yes | 3 |
| CASE-0107 | SURF-007  |  | macos-glass | pass | yes | 1 |
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
| CASE-0009 | SURF-011  |  | swiftui | pass | yes | 3 |
| CASE-0016 | SURF-011  |  | macos-glass | pass | yes | 3 |
| CASE-0111 | SURF-011  |  | macos-glass | pass | yes | 1 |
| CASE-0020 | SURF-012  |  | ios-glass | n/a: Simulator has no Mac accessibility tree; MCPRouterIOS ships no URL scheme; simctl screenshot of the default Settings tab cannot be attributed to Discover; activating Simulator.app is refused |  | 1 |
| CASE-0120 | SURF-012  |  | ios-glass | n/a: only Settings boot PNG exists; Discover tab not reached. simctl frame has no SCFrameStatus and is untrustworthy by construction |  | 1 |
| CASE-0021 | SURF-013  |  | ios-glass | n/a: same Simulator/AX/URL-scheme ceiling as CASE-0020; Triage/Queue/Library tab never reached without activating Simulator.app |  | 1 |
| CASE-0023 | SURF-013  |  | ios-glass | pass | yes | 3 |
| CASE-0121 | SURF-013  |  | ios-glass | n/a: Triage/Queue/Library not photographed; attaching the Settings boot PNG would be a duplicate SHA standing in for a different surface |  | 1 |
| CASE-0022 | SURF-014  |  | ios-glass | n/a: pairing scanner/code field never photographed; no URL scheme, no Mac AX into the sim, campaign refuses activating Simulator.app |  | 1 |
| CASE-0040 | SURF-014  |  | ios-glass | fail | yes | 1 |
| CASE-0122 | SURF-014  |  | ios-glass | n/a: pairing scanner not photographed; do not attach Settings boot as pairing pixels |  | 1 |
| CASE-0030 | SURF-015  |  | router-daemon | pass | yes | 3 |
| CASE-0031 | SURF-015  |  | router-daemon | pass | yes | 3 |
| CASE-0032 | SURF-015  |  | router-daemon | pass | yes | 3 |
| CASE-0034 | SURF-015  |  | router-daemon | pass | yes | 3 |
| CASE-0033 | SURF-016  |  | router-daemon | pass | yes | 3 |
| CASE-0035 | SURF-016  |  | router-daemon | pass | yes | 3 |
| CASE-0037 | SURF-016  |  | router-daemon | pass | yes | 3 |
| CASE-0036 | SURF-017  |  | parity-wire | fail |  | 7 |
