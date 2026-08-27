---
status: completed
shipped-by: 7e7ed70
---

# M14 — a shipped menu tells the user the app is not built

**Source:** found by M13 once A34 stopped masking the check behind it. Confirmed at merge by the
orchestrator against `MenuCommand.swift`.

`scripts/acceptance/mac-shell.sh` fails with:

> every destination has a board, but the Release bundle still contains 'isn't built yet' — the
> scaffold outlived the surface it stood in for

**The cause, precisely.** `MenuCommand.swift:320-321`:

    // Still owned by items that have not shipped.
    case .pairPhone, .exportLibrary:
        return .surfaceAbsent

and `:90` gives `.surfaceAbsent` the headline `"This part of the app isn't built yet."`

**M6 shipped pairing.** So a user hovering **Pair iPhone…** is told the app is not built, while
`ShellCommandRouterTests` already pins that same command to `.openPairing`. M6 fixed the routing half
and left the availability half, and A34 hid the consequence.

**`.exportLibrary` is genuinely unshipped**, so this is not "delete the string". Two things have to be
separated: a command whose *destination* does not exist (none remain, all eight boards shipped) and a
command whose *feature* has not been built (export). The Release gate currently conflates them.

**Done means:** `.pairPhone` reports what is true; `.exportLibrary` still says something honest that
is not the retired scaffold sentence; `mac-shell.sh` exits 0; and the gate distinguishes the two cases
rather than string-matching one sentence. Prove the gate can still fail.

Small. Do not widen it into M9's rename or the board-alignment work.
