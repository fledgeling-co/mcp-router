# UI verification — test what you changed, and only that

Binding on every runner that touches a user-facing surface.

**Only test a screen when you have changed that screen, and test only that screen.**

Not the neighbouring screens, not the menus you happened to pass through, not the full matrix.
A one-line change to a sidebar row does not re-earn a sweep of every screen in the app.

## Why this is a rule and not a preference

Measured across one fleet session: M1 ran four times and I1 four, and every relaunch restarted
UI verification from zero, because nothing on disk recorded what had already been proven. The
Mac lane drives the real UI over the Accessibility API and captures real windows, so each repeat
takes over the user's actual screen. The user's objection was their time, not the tokens.

Repetition also buys nothing. Re-running a passing check against unchanged code has exactly one
possible outcome, and a check whose result you can predict is not evidence.

## What to do

1. **Before testing anything, ask what changed under it.** If the files behind a screen have not
   changed since it was last proven, do not test it. Cite the earlier evidence instead.
2. **Keep an evidence ledger** at `planning/evidence/<ID>-acceptance.md`, committed with your work:

   | Screen | How verified | Commit | Result |
   |---|---|---|---|

   Append; never rewrite. Record the actual command or AX path, not "verified".
3. **Read the ledger before you test.** A row whose commit is untouched by
   `git diff <SHA>..HEAD` for that screen's files *is* the evidence. Skip, and say so in the report.
4. **One launch, one pass.** Never relaunch the app or boot a simulator per screen. Launch once,
   cover what you need in a single sweep, quit.
5. **After a fix, re-verify only the screens the fix touched.**

The ledger is the part that survives you. A relaunched runner reads it and skips what you proved;
without it, your successor repeats every check you ran, and the user watches it happen again.

## What this does not relax

Behavioural claims still need behavioural proof — a build gate is not evidence that a screen
works. The designed states in `DESIGN.md` §5 are still designed and still shown. A screen that has
genuinely never been verified is still verified properly, once, with real evidence.

The target is repetition, not rigour. Verify each thing well, one time, and write it down.
