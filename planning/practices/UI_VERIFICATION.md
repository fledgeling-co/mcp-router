# UI verification — never take the user's screen, and test what you changed

Binding on every runner that touches a user-facing surface.

## Rule 1 — never steal focus. The developer loop must be invisible.

This is the one that matters most, and it is the one the first version of this file missed.

The complaint that produced it was "the agents are repeatedly testing the same app screens".
The measurement said otherwise: the Mac runner was in an ordinary **build → launch → probe → fix
→ rebuild → relaunch** loop, three cycles deep, and *every cycle was legitimate* — it had changed
the screen each time. So a rule about redundant testing does not bite here at all. What the user
actually experiences is their desktop being taken over, and an honest edit-run loop does that just
as effectively as a wasteful one.

So the fix is not "test less". It is: **the app must never come to the front.**

- **Launch backgrounded**: `open -g -a "$APP"`. Never a bare `open -a`, which activates.
- **Never** `osascript -e 'tell application … to activate'`, and **never**
  `set frontmost to true`. Those two lines are what steal the screen.
- **Read and drive through the accessibility plane by pid.** The AX API answers for a background,
  occluded, or other-Space window. Driving `click menu item …` through System Events works without
  the process being frontmost.
- **Prefer `proctor`** (MCP, already installed and granted on this machine — `proctor_doctor`
  reports ready). It exists for exactly this: `proctor_apps` to attach, `proctor_act` for
  background-safe actions over the accessibility and Apple-Event planes, `proctor_capture` for
  window-scoped screenshots of a window that is not in front. Its synthetic-event step kinds
  (`click`, `hover`, `key`, `dragPath`) *do* require foreground — avoid those, and use the
  process-directed equivalents (`press`, `menu`, `setValue`, `focus`).
- **Never `screencapture -R x,y,w,h`** — it photographs whatever is on top of that screen region,
  not the window you meant. Use `proctor_capture`, or `screencapture -l<CGWindowID>`.
- **Quit the app when the pass ends.** A left-running window is still clutter.

If a check genuinely cannot be done without the window in front, say so in the report and leave it
for a human, rather than taking the screen and hoping nobody is using it.

## Rule 2 — only test a screen when you have changed that screen, and only that screen

Not the neighbouring screens, not the menus you happened to pass through, not the full matrix.
A one-line change to a sidebar row does not re-earn a sweep of every screen in the app.

Measured across one fleet session: M1 ran four times and I1 four, and every relaunch restarted UI
verification from zero, because nothing on disk recorded what had already been proven.
Re-running a passing check against unchanged code has exactly one possible outcome, and a check
whose result you can predict is not evidence.

## What to do

1. **Before testing anything, ask what changed under it.** If the files behind a screen have not
   changed since it was last proven, do not test it. Cite the earlier evidence instead.
2. **Keep an evidence ledger** at `planning/evidence/<ID>-acceptance.md`, committed with your work:

   | Screen | How verified | Commit | Result |
   |---|---|---|---|

   Append; never rewrite. Record the actual command or AX path, not "verified".
3. **Read the ledger before you test.** A row whose commit is untouched by
   `git diff <SHA>..HEAD` for that screen's files *is* the evidence. Skip, and say so in the report.
4. **One launch, one pass.** Never relaunch the app or boot a simulator per screen. Launch once
   (backgrounded), cover what you need in a single sweep, quit.
5. **After a fix, re-verify only the screens the fix touched.**

The ledger is the part that survives you. A relaunched runner reads it and skips what you proved;
without it, your successor repeats every check you ran, and the user watches it happen again.

## What this does not relax

Behavioural claims still need behavioural proof — a build gate is not evidence that a screen
works. The designed states in `DESIGN.md` §5 are still designed and still shown. A screen that has
genuinely never been verified is still verified properly, once, with real evidence.

The target is repetition and stolen focus, not rigour. Verify each thing well, one time, out of
sight, and write it down.

