export const meta = {
  name: 'mcp-router-win17-gapfix',
  description: 'WIN17 gap-fix: close the four defects its verifier found',
  phases: [{ title: 'GapFix', detail: 'WIN17 D1, D2, G1 and acceptance item 7' }],
}

// A gap-fix handed the FINDINGS converges; one handed a bare verdict rebuilds. So every finding
// below carries the measurement that produced it, and the runner is told not to re-derive them.
// D3 is already closed by the conductor and is listed so it is not fixed twice.

const PROMPT = `
REPO: C:\\Dev\\mcp-router (Windows 11). ITEM: WIN17 gap-fix.
Brief: planning/features-to-triage/WIN17-router-daemon-is-macos-shaped-on-windows.md
WORKTREE: git worktree add .worktrees/WIN17-gapfix -b ai/win17-gapfix main

WIN17 is MERGED and was verified NEEDS-WORK. Five of six acceptance items were confirmed by a
verifier that exercised the router rather than reading it. You are closing what it found. Do NOT
rebuild the item, do NOT re-derive the measurements below, and do NOT repair anything it confirmed.

D1 - A ROUNDING ASYMMETRY THIS ITEM INTRODUCED.
\`parseProcStart\` FLOORS the FILETIME (\`BigInt(text) / 10_000_000n\`) while the Windows probe casts
\`[int64](....TotalSeconds)\` in PowerShell, which ROUNDS TO NEAREST ([int64]1.6 = 2, [int64]1.5 = 2).
Across all 10 rows of this machine's live registry, 5 OF 10 DISAGREE BY EXACTLY ONE SECOND, and
\`sessions.ts:228\` treats \`> 1\` as recycled. So half of all Windows sessions sit exactly on the
boundary, deterministically rather than through clock drift - any real drift tips a live session
into \`recycled\` and its message lands nowhere. \`platform.ts:326\` records that the two "agreed to
within one second, which is inside the tolerance": the author saw the symptom and read their own
asymmetry as headroom. Floor both sides.

D2 - THE WINDOWS LANES BLOCK THE EVENT LOOP, INSIDE FUNCTIONS DECLARED async.
\`platform.ts\` uses \`execFileSync\` for both netstat and PowerShell. Measured: \`peerOfLocalPort\`
93 ms wall / 83 ms event-loop lag; \`residentKb\` 433 ms / 423 ms lag; a bare synchronous
\`powershell Get-Process\` 372 ms. \`peerOfLocalPort\` runs on every accepted connection
(\`router.ts:486\`) and is awaited on the request path (\`router.ts:175\`, \`202\`, \`357\`), so the
first request from each new client STALLS THE WHOLE ROUTER for roughly 0.45 s, serving nobody. The
macOS path it replaced was fully async \`execFile\`. The header quotes netstat at "23 ms" where the
verifier measures 83-93 ms from node. Make them genuinely async, and correct the quoted figure.

G1 - THE launchd FINDING IS HALF-CLOSED.
Supervision is restated honestly; the CONFIG WATCHER is not. Nothing fires \`mcpr watch\` on Windows,
so a server added to ~/.claude.json is never adopted. \`watch.ts:5\` still says "launchd fires this on
the file change" unconditionally, and \`index.ts:58\` prints "(run by launchd on file change)" in the
usage text ON WINDOWS. A user gets no signal the auto-adoption path does not exist on this host.
Either implement the watcher or say plainly, in the product's own output, that it does not exist
here - do not leave text asserting a macOS mechanism to a Windows user.

ITEM 7 - REJECTED, UNTOUCHED.
"The TypeScript reference parity harness position is stated: whether Windows behaviour is in its
corpus, or deliberately out." Nothing states it. \`grep -rni "windows|win32" scripts/parity/\` returns
only unrelated comments. State the position.

MINOR, worth closing while you are here: \`processStartSeconds\`'s degenerate per-pid retry spawns one
372 ms PowerShell per pid (~3.7 s synchronously at this registry's size) where macOS \`ps\` costs
milliseconds - bounded, but the asymmetry is unstated. And \`scripts/e2e-platform.mjs\` imports
\`spawnSync\` and never uses it.

ALREADY CLOSED - DO NOT REDO: D3, the e2e being enrolled in nothing. \`scripts/e2e-platform.mjs\` now
runs inside \`scripts/windows/verify.ps1\` and the lane reports 9 passed / 0 failed / 5 not-run.

MEASURED FACTS FOR THIS MACHINE - do not re-derive:
- \`make\`, \`swift\`, \`swiftlint\`, \`xcodebuild\`, \`gh\` ABSENT. \`make lint\`/\`make test\` CANNOT
  RUN and must never be reported green.
- Windows lane: \`powershell -File scripts\\windows\\verify.ps1\`, or
  \`python3 planning/goals/win-gates.py lane\`. It must still exit 0 when you are done.
- \`python3.exe\` is an 87-BYTE STUB - fine from Git Bash, fails from PowerShell with
  NativeCommandFailed and an EMPTY \$LASTEXITCODE. Use \`python\` there, and \`sys.executable\`
  wherever Python spawns Python.
- \`bash\` from a Python subprocess reaches WSL, which cannot start here. Use
  "C:\\Program Files\\Git\\bin\\bash.exe".
- \`core.fileMode\` is false; without it 226 files read as modified and every merge aborts.
- PYTHONIOENCODING=utf-8 before any repo Python gate.
- Cross-family review is UNAVAILABLE. Record not-run, NEVER a pass.

RULES: \`main\` refuses direct commits - branch and STOP before merge; do NOT push. NEVER
\`git add -A\`, named paths only. Tests verify correctness and are NEVER edited to pass. A gate that
cannot run on Windows is NOT-RUN, never passed. Never print or log a credential - \`servers.json\`
holds live bearer tokens, and the verifier ran against an isolated MCP_ROUTER_HOME fixture for
exactly that reason; do the same.

Extend \`scripts/e2e-platform.mjs\` so each fix has a check that would have caught it - D1 especially,
where the failing case is a one-second disagreement that looked like headroom.

STOP BEFORE VERIFY and STOP BEFORE MERGE. Report what you changed, the exact commands and their real
exit codes, and what you could not run and why.`

phase('GapFix')
const r = await agent(PROMPT, { label: 'WIN17 gap-fix', phase: 'GapFix', model: 'opus', effort: 'high' })
log(r ? 'gap-fix returned' : 'gap-fix LOST - derive from started minus returned, not from an error field')
return { item: 'WIN17', report: r }
