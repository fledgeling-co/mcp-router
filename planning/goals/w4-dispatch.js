export const meta = {
  name: 'mcp-router-windows-w4',
  description: 'Windows parity fleet, wave 4: packaging, keyboard, notifications, router lifecycle',
  phases: [{ title: 'W4', detail: 'WIN19, WIN21, WIN22, WIN23' }],
}

// Staged, not launched. Each item needs its named surface merged first.
// Launch: Workflow({scriptPath: 'planning/goals/w4-dispatch.js'})
//
// All four are proposed-by-ai rather than asked for. If the owner deleted one of these briefs to
// veto it, the runner must report that and stop rather than rebuild it from this prompt - the
// brief on disk is the authority, not this file.

const FACTS = `
REPO: C:\\Dev\\mcp-router (Windows 11).

MEASURED — use these, do not re-derive:
- \`make\`, \`swift\`, \`swiftlint\`, \`swiftformat\`, \`xcodebuild\`, \`gh\` are ABSENT. \`make lint\`
  and \`make test\` CANNOT RUN and must never be reported green.
- The Windows lane is \`scripts/windows/verify.ps1\`, or \`python3 planning/goals/win-gates.py lane\`.
- \`python3.exe\` is an 87-BYTE STUB: fine from Git Bash, fails from PowerShell with
  NativeCommandFailed and an EMPTY \$LASTEXITCODE. In PowerShell use \`python\`.
- \`bash\` from a Python subprocess reaches WSL, which cannot start here (virtualisation off in
  firmware). Use "C:\\Program Files\\Git\\bin\\bash.exe".
- WinUI builds ONLY via Visual Studio MSBuild.exe with -t:Restore,Build. \`dotnet build\` fails
  MSB4062 forever - it resolves MSBuildExtensionsPath to the .NET SDK, which has no AppxPackage tasks.
- \`core.fileMode\` is false; without it 226 files read as modified and every merge aborts.
- PYTHONIOENCODING=utf-8 before any repo Python gate.
- Cross-family review is UNAVAILABLE. Record not-run, NEVER a pass.
- A wrapper's exit code is not evidence an install happened: winget exited 0 over "Installer
  failed with exit code: 1", and setup.exe over "Exit Code: 87". Judge by an artifact on disk.

RULES:
- Your own worktree: \`git worktree add .worktrees/<ID> -b ai/<id> main\`.
- \`main\` refuses direct commits. STOP before verify AND before merge. Do NOT push.
- NEVER \`git add -A\`. Named paths only.
- A gate that cannot run on Windows is NOT-RUN, never passed. Never raise or waive a ratchet.
- Never print, log or copy a credential; servers.json holds live bearer tokens.
- If your brief no longer exists on disk, the owner vetoed it. Report that and STOP.
`

const S = [
  ['WIN19', 'Windows packaging and distribution', `How the client reaches a machine that did not build it. The Mac has an entire blocked brief about signing; Windows has the same problem in a different shape and had none.
An unsigned Windows executable triggers SmartScreen's "Windows protected your PC", which users read as malware - a distribution blocker the way notarisation is on macOS. Note that a signature can verify under Get-AuthenticodeSignature and SmartScreen can STILL warn, because it weighs reputation as well as validity, and a fresh certificate has none. The check that reassures is not the check that decides.
DO NOT BUY A CERTIFICATE and do not ask for one. Decide the shape, make the unsigned path honest about exactly what a user sees, and record what is signed and what is not.
winget is present and is the idiomatic channel for a developer tool. MSIX gives clean install/uninstall; a plain installer is simpler and gives that up. Choose, and say what the loser was better at.
Uninstall must state what it leaves behind - router state and credentials especially. The daemon's install and update path on Windows is part of this, and connects to WIN23.`],
  ['WIN21', 'Windows keyboard model', `DESIGN.md section 8 is a macOS keyboard: Command-based, and its completeness guarantee leans on rule 9's menu bar, which Windows does not have. So the Windows keyboard is currently UNSPECIFIED, and an unspecified keyboard becomes whatever the framework's defaults happen to be.
The substitutions are not mechanical. Command maps to Control for most shortcuts but not all - combinations free on macOS are already taken on Windows and vice versa. Windows also has two affordances macOS lacks: ACCESS KEYS (Alt plus an underlined letter) and F6 for pane cycling. A Windows app without them reads as unfinished to a keyboard user.
Add a Windows keyboard section to the design authority alongside sections 11-12, with the same force of language, each shortcut traceable to Windows convention rather than transliterated.
One measured reason this matters: the macOS shortcut case is recorded n/a because posting Cmd-1..7 to a background process does not change SwiftUI's focused scene, so the Mac keyboard is largely UNPROVEN. With WIN20's automation plane the Windows keyboard is testable in a way the Mac's is not - EXERCISE the shortcuts rather than asserting them.`],
  ['WIN22', 'Toasts for waiting decisions', `The Inbox depends on the user finding out something is waiting. WIN11's ambient surface is weaker than a menu bar because Windows 11 hides notification-area icons behind the overflow chevron by default.
Windows has a channel macOS's menu bar does not: toast notifications through the Action Center, plus taskbar badging.
THE RESTRAINT MATTERS MORE THAN THE MECHANISM, and it comes from the product's own behaviour: the update gate is explicit that most updates "promote silently with no notification at all". A notification means a decision is genuinely required. Toasting every event would break that discipline while appearing to add a feature.
ONE HARD RULE: a toast action may open the review sheet. NO TOAST ACTION MAY INSTALL, APPROVE OR GRANT ANYTHING. That would move an irreversible decision into a transient surface a user might dismiss by reflex - precisely the affordance WIN10's phone-queues-never-installs design exists to prevent.
Honour the system notification setting and Focus Assist. Several items arriving together do not produce several toasts. Badge reflects the undecided count.`],
  ['WIN23', 'Router lifecycle on Windows', `On macOS launchd starts the router at login, restarts it under KeepAlive, and watches the config file. WIN17 records that the source reasons about launchd in four files, including a deliberate non-zero exit whose only purpose is to make launchd restart the job. Windows has no launchd.
DECIDE THE PRODUCT QUESTION FIRST, because it is wearing an infrastructure question's clothes: DOES THE WINDOWS ROUTER RUN WHEN THE CLIENT IS CLOSED? On macOS it does. If it does not on Windows, that is a parity gap no surface brief would reveal, and it must be recorded as one rather than discovered later.
Candidates, each losing something real: a Windows Service gives true restart-on-failure but needs admin rights and runs outside the user session - wrong for a daemon that must open a browser for OAuth and read per-user harness configs. A Scheduled Task at logon runs in-session and needs no elevation, but restart-on-failure is weaker and its stdout is LOST. A startup entry or client-supervised process is simplest and ties the router's life to the client's, which changes the product.
Whatever replaces the launchd file watcher must notice a config change without a manual restart. Logs must go somewhere findable. Installation must not silently require administrator rights.
State the restart guarantee HONESTLY, including if it is weaker than launchd's.`],
]

phase('W4')
const out = await parallel(S.map(([id, title, what]) => () =>
  agent(
    `${FACTS}
You are a ship-feature runner. Invoke \`ship-feature:ship-feature\` - a BARE skill name never
resolves here, always \`plugin:skill\`, and check the Skill result rather than assuming it loaded.

ITEM: ${id} - ${title}
BRIEF (read in full): planning/features-to-triage/${id}-*.md
WORKTREE: .worktrees/${id}    BRANCH: ai/${id.toLowerCase()}
Read DESIGN.md in full. Sections 11 and 12 are the Windows floor and are what you are judged
against; section 3 is the macOS floor and is NOT yours.

${what}

STOP BEFORE VERIFY and STOP BEFORE MERGE. Report ready-to-verify with the exact gate commands and
their real exit codes, and what you could not run and why. A blocked report is a result; a gate
reported green but not run is not.`,
    { label: `${id} ${title.split(' ')[1] || title.split(' ')[0]}`, phase: 'W4', model: 'opus', effort: 'high' }
  ).then(r => ({ id, report: r }))
))

const got = out.filter(Boolean)
log(`W4 returned ${got.length} of ${S.length}`)
return {
  wave: 'W4',
  returned: got.map(r => r.id),
  lost: S.map(x => x[0]).filter(id => !got.some(r => r.id === id)),
  reports: got,
}
