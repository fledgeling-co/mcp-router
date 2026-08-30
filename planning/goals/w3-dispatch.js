export const meta = {
  name: 'mcp-router-windows-w3',
  description: 'Windows parity fleet, wave 3: the thirteen surfaces, five at a time',
  phases: [{ title: 'W3', detail: 'WIN4-WIN11, WIN13-WIN16 in batches of five' }],
}

// Staged, not launched. W3 needs WIN3 (shell) and WIN2 (floor) MERGED, not merely finished.
// Launch: Workflow({scriptPath: 'planning/goals/w3-dispatch.js'})
//
// Thirteen items against a hard cap of FIVE concurrent agents. That five is a correctness limit,
// not a throughput preference: beyond it agents die silently at 180.0s leaving no error row, and
// this fleet has already lost a whole wave to silent death. So the items run in batches of five
// rather than as one thirteen-wide fan-out, and each batch is asserted for losses before the next.

const FACTS = `
REPO: C:\\Dev\\mcp-router (Windows 11).

MEASURED — use these, do not re-derive:
- \`make\`, \`swift\`, \`swiftlint\`, \`swiftformat\`, \`xcodebuild\`, \`gh\` are ABSENT. \`make lint\`
  and \`make test\` CANNOT RUN and must never be reported green.
- The Windows lane is \`scripts/windows/verify.ps1\`, or \`python3 planning/goals/win-gates.py lane\`.
- \`python3.exe\` is an 87-BYTE STUB: fine from Git Bash, fails from PowerShell with
  NativeCommandFailed and an EMPTY \$LASTEXITCODE. In PowerShell use \`python\`.
- \`bash\` from a Python subprocess reaches WSL, which cannot start here. Use
  "C:\\Program Files\\Git\\bin\\bash.exe".
- WinUI builds ONLY via
  "C:\\Program Files (x86)\\Microsoft Visual Studio\\2022\\BuildTools\\MSBuild\\Current\\Bin\\MSBuild.exe" <proj> -t:Restore,Build
  \`dotnet build\` fails MSB4062 forever.
- \`core.fileMode\` is false; without it 226 files read as modified and every merge aborts.
- PYTHONIOENCODING=utf-8 before any repo Python gate.
- Cross-family review is UNAVAILABLE. Record not-run, NEVER a pass.

RULES:
- Your own worktree: \`git worktree add .worktrees/<ID> -b ai/<id> main\`.
- \`main\` refuses direct commits. STOP before verify AND before merge. Do NOT push.
- NEVER \`git add -A\`. Named paths only.
- A gate that cannot run on Windows is NOT-RUN, never passed. Never raise or waive a ratchet.
- Tests verify correctness and are NEVER edited to pass.
- Never print or log a credential; servers.json holds live bearer tokens.

DESIGN AUTHORITY: read DESIGN.md in full. Sections 11 and 12 are the WINDOWS floor and are what
you are judged against; sections 1, 2, 5, 6 and 9 are shared. Section 3 is the macOS floor and is
NOT yours. The mock decides WHAT is on the surface; Windows 11 decides HOW it is drawn.
`

const S = [
  ['WIN4',  'Servers board and the Signal Path', `The board the product exists for, and the only loud surface in it.
A table of declared servers with live state - awake, dormant, held, tripped, needs sign-in - awake rows counting down idle time.
Above it the SIGNAL PATH: a lane of jacks reading "5 harnesses -> 1 endpoint -> 11 upstreams". DESIGN.md calls it the signature element.
It is DRAWN, not a stock control, so this is the one surface where "use the system control" is not available. Restate its geometry in effective pixels rather than eyeballing the macOS points.
A jack lights on a real call and darkens when the child is reaped. "Reap idle" acts; "Add server..." opens a further view - the ellipsis is load-bearing and shared with Windows.`],
  ['WIN5',  'Activity board', `"Every tool call every harness made, as it happens" - the only place that answers "which of my agents did that".
Columns Time, Harness, Tool, Duration, Result. Pause, Export..., filters (All, Errors, Slow > 2 s, Held), per-harness tallies.
LIVE via GET /usage/stream, not polling - polling misses calls between polls. Pause must not drop calls that arrive while paused.
Densest reading surface in the product, so it is the real test of the Windows palette. Tool names are paste-into-a-terminal strings: monospace.`],
  ['WIN6',  'Skills board', `"One skill can be live in two harnesses and absent from three; the slots say which."
Columns Skill, Marketplace, Version, Installed into, Auto-update - where "Installed into" is per-harness SLOTS, not a single value. That compression is the board's whole idea.
HELD-FOR-REVIEW IS A SECURITY GUARANTEE, not decoration: a version asking for more permission than the installed one does not go live, it waits, and it says what it now asks for. Getting that wrong is a security regression, not a visual defect.`],
  ['WIN7',  'Discover board', `Two properties are guarantees, not layout:
TWO BANDS, never one ranked list - editorial and measured are different claims. A trending row carries a window AND a signed delta, or it is not drawn as trending.
NO INSTALL AFFORDANCE ON A ROW - one tap from a gameable ranking to executing someone's code is the affordance an adversary wants. You open a row, and install from the detail. Windows card idioms invite an inline primary action; resist it.
A rate-limited or unreachable registry draws as itself, distinctly from "nothing found".`],
  ['WIN8',  'Checks board', `"A result belongs to the version it ran against and is thrown away when that version moves - a green tick carried forward is worse than no tick."
Every result stamped with its version. When a capability's version moves, the previous result is DROPPED and the row reads stale; it is never re-shown against the new code. The invalidation notice names what was dropped and why.
"No model-graded evaluation exists in this product" - keep it that way. A failing check opens to the exchange that failed, not to a count.
This is the board most likely to be silently regressed, because carrying a stale green tick forward is the easy implementation and it looks better.`],
  ['WIN9',  'Cleanup board', `"Nothing is removed automatically and nothing is called rubbish."
States the window it judges over, because "never used" across four days of history is not evidence. Every row carries WHY IT MIGHT STILL MATTER - a rarely-used migration skill is not a cull candidate.
Re-checks the upstream before offering removal, because a dormant capability is the one nothing else re-examines.
It also corrects the user's likely reason for being there: under the router an unused server costs cached schema and nothing else, so the reason to remove is tool-list clutter or lost trust, not disk space.
Removal is destructive: confirmed, never the default action, and it says exactly what goes.`],
  ['WIN10', 'Inbox board and review sheet', `THE PHONE QUEUES, IT NEVER INSTALLS. That sentence is the feature and the whole pairing design exists to provide it.
Groups by decision state with counts. Each undecided item shows its provenance and restates that nothing has happened yet.
The review sheet heading is "What it would be able to do", followed by plain-language capability lines in the CONDITIONAL - it has been granted nothing. Not a permission manifest.
Nothing is downloaded or written to any harness before approval, and the surface says so truthfully.`],
  ['WIN11', 'Ambient surface (the menu-bar popover has no Windows twin)', `The Mac has a menu-bar popover: ambient router state without foregrounding the app, plus the inbox band.
WINDOWS HAS NO MENU BAR, so this is a design decision rather than a port. Notification-area icon with a flyout is the leading candidate but Windows 11 HIDES such icons behind the overflow chevron by default - an ambient surface the user must first unhide is not ambient. Decide, implement, and record what the alternatives would have been better at.
Must distinguish at rest, working, something waiting, and cannot-reach-the-router. Keyboard reachable and exposed to assistive technology.`],
  ['WIN13', 'Settings board', `Seven panes: Router, Harnesses, Session analyst, Updates, Security, Menu bar, Advanced. Six transfer; the seventh is named for an affordance Windows lacks and becomes the settings for whatever WIN11 built - rename it.
The biggest control-vocabulary gap in the product: DESIGN.md rule 6 pins macOS controls (checkbox for an independent setting), Windows 11 uses toggle switches for most binary settings. Follow the WINDOWS floor and record the mapping.
Security settings must not be weaker by default than the Mac's; any difference is deliberate and recorded. The update policy governs WIN6's held-for-review guarantee.`],
  ['WIN14', 'Harnesses board', `"Pointing a harness at the endpoint is the easy half; the half that saves anything is noticing it still spawns its own copies."
DETECTING DOUBLE-RUNNING is the feature - a harness routing through the router AND spawning its own servers, with the overlap counted. A reimplementation that only checks whether a config line exists has missed the point.
THE MOST WINDOWS-SPECIFIC OF THE THIRTEEN: everything it reads is a path. ~/.claude.json is %USERPROFILE%\\.claude.json; every harness has its own Windows location; and the Windows harness inventory is UNMEASURED - establishing it is part of this work, not an input to it.
Reads configs, does not write them. "Open config" reveals in Explorer rather than editing in place.`],
  ['WIN15', 'Insights board', `"Every number here is counted from calls this router served - none of it is modelled."
NO FIGURE WITHOUT ITS DENOMINATOR. A percentage carries numerator and denominator and names its dominant contributor; memory says it was measured; a zero is EXPLAINED rather than left bare. Bare stat tiles would lose the property that makes the board trustworthy.
Resident memory across child processes is read differently on Windows - "measured, not modelled" must stay true of however you obtain it. src/platform.ts (WIN17) already has residentKb.
Figures come from GET /usage/summary, not computed in the client, so a client-side number cannot diverge from the router's.`],
  ['WIN12', 'Pairing an iPhone to the Windows client', `WIN10's value depends on a paired phone: the phone discovers and queues, the desktop decides. Without this, WIN10 degrades to analyst findings only and the existing iOS app has no Windows counterpart to pair with.
The phone side already exists and does NOT change - you are building the other end of a protocol that is already specified. Do not propose a new scheme.
THE SECRET GOES TO WINDOWS CREDENTIAL MANAGER, never a config file. DPAPI encrypts per user. Never display, log or copy the value. This is a security-relevant substitution, not a styling one.
Discovery and reachability need a Windows answer, and Windows Defender Firewall WILL prompt on first bind - a pairing flow that silently fails behind a firewall prompt reads to the user as a broken product. Handle it and say what to do.
Distinct failure states: wrong code, expired code, unreachable phone, already paired.`],
  ['WIN16', 'Capability document panel and the update gate', `The detail surface every other board hands off to: three tabs over one package - Capabilities, Changelog, Flags worth knowing - across versions.
It carries THE UPDATE GATE, "the heart of the product": a new version lands as a shadow copy, evals re-run, and it promotes only if the capability diff is empty. Most updates are empty and promote silently with NO notification.
CAPABILITY DIFF BEFORE CONTENT DIFF - the ordering IS the guarantee, "because a 400-line diff gets click-through-approved and a four-line capability delta does not". Leading with the content diff, or showing both with equal weight, loses the property even though every element is present.
Reached from Discover, Skills and Inbox: ONE surface, not three near-copies. Shares capability-rendering with WIN10's review sheet, since divergence is how the plain-language guarantee rots.`],
]

const BATCH = 5
const results = []
phase('W3')
for (let i = 0; i < S.length; i += BATCH) {
  const batch = S.slice(i, i + BATCH)
  log(`W3 batch ${i / BATCH + 1}: ${batch.map(b => b[0]).join(', ')}`)
  const out = await parallel(batch.map(([id, title, what]) => () =>
    agent(
      `${FACTS}
You are a ship-feature runner. Invoke \`ship-feature:ship-feature\` - a BARE skill name never
resolves here, always \`plugin:skill\`, and check the Skill result rather than assuming it loaded.

ITEM: ${id} - ${title}
BRIEF (read in full): planning/features-to-triage/${id}-*.md
WORKTREE: .worktrees/${id}    BRANCH: ai/${id.toLowerCase()}
Layout, information architecture and vocabulary come from design/mcp-router-console.html.
Your shell is WIN3's, already merged - build inside it rather than a window of your own.

${what}

Every surface owes its empty, loading, disconnected and error states - DESIGN.md section 5 holds
that the states ARE the design. Controls must be addressable in the UI Automation tree with names
matching the on-screen vocabulary (WIN20), or the surface cannot be measured at all.

STOP BEFORE VERIFY and STOP BEFORE MERGE. Report ready-to-verify with the exact gate commands and
their real exit codes, and what you could not run and why.`,
      { label: `${id} ${title.split(' ')[0]}`, phase: 'W3', model: 'opus', effort: 'high' }
    ).then(r => ({ id, report: r }))
  ))
  const got = out.filter(Boolean)
  const lost = batch.map(b => b[0]).filter(id => !got.some(r => r.id === id))
  if (lost.length) log(`  LOST ${lost.length}: ${lost.join(', ')} - derived from started minus returned, not from an error field`)
  results.push(...got)
}

log(`W3 returned ${results.length} of ${S.length}`)
return {
  wave: 'W3',
  returned: results.map(r => r.id),
  lost: S.map(x => x[0]).filter(id => !results.some(r => r.id === id)),
  reports: results,
}
