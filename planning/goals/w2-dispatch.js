export const meta = {
  name: 'mcp-router-windows-w2',
  description: 'Windows parity fleet, wave 2: the shell and the automation plane',
  phases: [{ title: 'W2', detail: 'WIN3 app shell, WIN20 UI Automation plane' }],
}

// Staged at iteration 7, NOT launched: W2 is blocked until WIN2, WIN17 and WIN18 have MERGED,
// not merely finished. Launch with Workflow({scriptPath: 'planning/goals/w2-dispatch.js'}).
//
// Unlike W1, every runner here gets its own git worktree. W1 put three agents in one working
// tree on a wrong inference (see ORCHESTRATOR.md, "DISPATCH HAZARD"); nothing was corrupted,
// but only because the named-paths rule held. Measured on this clone: `git worktree add` exits
// 0 and checks out all 2,348 files.

const COMMON = `
REPO: C:\\Dev\\mcp-router (Windows 11). You are a ship-feature runner in a fleet.
Invoke \`ship-feature:ship-feature\` on your item. A BARE skill name never resolves here — always
\`plugin:skill\`. Check the Skill tool's result rather than assuming it loaded.

YOUR WORKTREE — create it first, and do all work inside it:
  git worktree add .worktrees/<ID> -b ai/<id> main
Then cd into it. Do NOT work in the main checkout: other runners are live in this repo and a
shared working tree means a shared index.

READ IN FULL, BY PATH: your brief; DESIGN.md; ORCHESTRATOR.md section "Windows fleet".

CONSTRAINTS — text, not references, because a path is a request and text is a constraint:
1. \`main\` REFUSES direct commits. Commit on ai/<id> and STOP before merging. The conductor
   serializes every merge. Do NOT push — a pre-push hook refuses and it was never granted.
2. STOP BEFORE VERIFY. Run to green, report ready-to-verify. You may not verify your own build.
3. NEVER \`git add -A\`. Add named paths only. A killed gate strands its mutation and -A adopts it.
4. \`make\`, \`swift\`, \`swiftlint\`, \`swiftformat\`, \`xcodebuild\` and \`gh\` are ABSENT.
   \`make lint\` and \`make test\` CANNOT RUN. Never report them green.
5. Cross-family verification is UNAVAILABLE (codex/agy/grok absent; the claude CLI returns
   "your organization has disabled Claude subscription access"). Record it not-run, never a pass.
6. A gate that cannot run on Windows is NOT-RUN, never passed. Do not raise or waive a ratchet.
7. Wrapper exit codes lie here — winget exited 0 over a failed installer, setup.exe over
   "Exit Code: 87". Verify an install by an artifact on disk.
8. Set PYTHONIOENCODING=utf-8 before any repo Python gate or it dies under cp1252.
9. \`bash\` from Python reaches WSL on this machine and WSL2 cannot start. Use
   "C:\\Program Files\\Git\\bin\\bash.exe" explicitly, or write PowerShell.
10. Tests verify correctness and are NEVER edited to pass.
11. Pipeline root is \`planning/\`, NOT \`docs/\` — docs/ is the live GitHub Pages source.
12. Never print or log a credential; servers.json carries live bearer tokens.

BUILD LANE, MEASURED — do not re-derive:
  "C:\\Program Files (x86)\\Microsoft Visual Studio\\2022\\BuildTools\\MSBuild\\Current\\Bin\\MSBuild.exe" <proj> -t:Restore,Build
  succeeds. \`dotnet build\` FAILS with MSB4062 — it resolves MSBuildExtensionsPath to the .NET
  SDK, which has no AppxPackage tasks. WinUI 3 / Windows App SDK is DECIDED (WIN1); do not reopen it.
  Verify the lane with: python3 planning/goals/win-gates.py lane

AFTER ANY COMPACTION re-read your brief, DESIGN.md and the ORCHESTRATOR Windows section.

Report: what changed, the exact gate commands with their real exit codes, what you could NOT run
and why, and your branch. A blocked report is a result; a gate reported green but not run is not.
`

const ITEMS = [
  {
    id: 'WIN3',
    label: 'WIN3 app shell',
    brief: 'planning/features-to-triage/WIN3-windows-app-shell.md',
    extra: `
The shell every board is drawn inside, so W3's thirteen surfaces all inherit your structure.

Nine boards plus Settings: Discover, Skills, Servers, Activity, Harnesses, Checks, Cleanup, Inbox,
Insights, Settings. Take layout, information architecture and vocabulary from
design/mcp-router-console.html; take the visual language from the Windows floor WIN2 added to
DESIGN.md (read it — it merged before you started).

The open question, and it is a real one rather than a detail: DESIGN.md rule 9 makes the menu bar
the complete command surface, and Windows 11 has no menu bar. Every command being reachable from
one surface is a guarantee, not a style. Decide what carries it on Windows, implement that, and
record what the alternatives would have been better at.

Also required: Mica, a custom title bar, the title naming the board rather than the app, keyboard
navigation of the board list, light and dark following the system and updating live, and surviving
a per-monitor DPI change without a restart. A board with nothing behind it draws an empty state
rather than blank.`,
  },
  {
    id: 'WIN20',
    label: 'WIN20 automation plane',
    brief: 'planning/features-to-triage/WIN20-windows-automation-plane-for-the-test-campaign.md',
    extra: `
This decides whether the campaign can measure ANY Windows surface, or whether all thirteen land
permanently in never-measured — which is neither a pass nor a failure and is the class that turns
a partial campaign into a finished-looking product.

Establish that the WinUI 3 shell publishes a UI Automation tree in which controls are individually
addressable, with names matching the vocabulary on screen, and control state (disabled, selected,
held, busy) readable from the automation plane rather than from pixels.

Build the harness that reads it OUT OF PROCESS, without activating or foregrounding the window —
the macOS campaign was constrained by a no-activate rule that left several cases unoracled, and
that constraint does not transfer if the tree is readable without focus.

A surface whose controls are not addressable is reported unoracled WITH THE REASON, following the
existing convention, rather than passing quietly.

Coordinate with WIN3: you need its window to exist to read a real tree. If WIN3 has not merged a
drawable window yet, build the harness against a minimal WinUI probe window of your own and say
plainly that is what you measured.`,
  },
]

phase('W2')
const results = await parallel(ITEMS.map(it => () =>
  agent(
    `${COMMON}
YOUR ITEM: ${it.id}
YOUR BRIEF (read in full): ${it.brief}
YOUR WORKTREE: .worktrees/${it.id}   YOUR BRANCH: ai/${it.id.toLowerCase()}
${it.extra}

Begin by creating your worktree, then invoke ship-feature:ship-feature on this item.`,
    { label: it.label, phase: 'W2', model: 'opus', effort: 'high' }
  ).then(r => ({ id: it.id, report: r }))
))

const ok = results.filter(Boolean)
log(`W2 returned ${ok.length} of ${ITEMS.length}`)
return {
  wave: 'W2',
  dispatched: ITEMS.map(i => i.id),
  returned: ok.map(r => r.id),
  lost: ITEMS.map(i => i.id).filter(id => !ok.some(r => r.id === id)),
  reports: ok,
}
