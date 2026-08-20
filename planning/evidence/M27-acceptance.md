# M27 — acceptance evidence

`The sidebar foot's loopback readout and the child-process label` · branch `ai/m27` ·
worktree `.worktrees/M27`
Brief `planning/features-to-triage/M27-sidebar-foot-readout.md` ·
Design of record `design/mocks/prototype.html` (amended here) · `DESIGN.md` §2, *The sidebar foot*

Append to this file, never rewrite it. Read it **before** testing anything: if a row exists and
`git diff <that SHA>..HEAD` does not touch the files behind it, that row *is* the evidence, and the
right thing to do is skip the check and say so.

---

## What changed under which screen

Two elements, both in the **shared sidebar wrapper** — so the surface is SURF-001, the shell, and
the predicate has to hold on all eight destinations rather than on one. Nothing on any board's
content zone changed. `SettingsPresentation.RouterFacts.endpoint` was re-pointed at the shared
`LoopbackAddress` composition and its rendered string is unchanged, which the unit lane asserts
(`http://127.0.0.1:9999/mcp` for port 9999).

**Not re-verified, and why.** The eight boards, the menu bar, the keyboard, the window frame and
restoration are M1's, M3's and M8's; this branch touches none of the files behind them. Their
evidence is `planning/evidence/M1-acceptance.md`, `M3-acceptance.md` and `M8-acceptance.md`, and
re-running them against unchanged code has one possible outcome.

## The rendered lane

`scripts/acceptance/mac-shell.sh`, extended rather than duplicated: the two new assertions ride the
**existing** eight-destination walk, so the pass is still one launch, one sweep, quit. The app is
launched with `open -g`, never activated, and every read is an accessibility query by pid.

Two things about the assertion are worth the next runner's attention:

- **It is bound to the sidebar by geometry**, not by presence anywhere in the window. Settings draws
  `127.0.0.1` in its own Endpoint row at x≈942, which is the content zone; the campaign's own
  differential recorded exactly that. A window-wide grep would have reported the foot line present
  on the one board that never had it.
- **The expected port is read out of `Control/Fixtures/servers.json`**, not typed. The line under
  test is the one whose whole defect class is a hard-coded port, so a hard-coded port in its oracle
  would be the same mistake one layer out.

| Screen | How verified | Commit | Result |
|---|---|---|---|
| _to be filled by the acceptance run_ | | | |
