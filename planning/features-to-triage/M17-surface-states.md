# M17 — four states on every surface, and chrome that follows them

**Depends on:** M1.
**Source:** `design/mcp-router-console.html`, PRD §9.6.

Ten surfaces — nine boards and the Settings window — each carry **ideal, empty, loading and
error**. That is 40 cells, and all 40 are drawn in the mock with copy written for that surface.

The count is the specification. A categorical instruction — "handle all states" — is
satisfiable with one instance, and on one recorded build it was: six named states produced one.
Track this as 40 cells and report the fraction built.

## The copy is per-surface, not per-template

A shared empty state that says "No data" is the same as not having one. Each cell names its own
situation:

| Surface | empty | error |
|---|---|---|
| Servers | No servers adopted yet | Cannot reach the router |
| Activity | Nothing has called a tool yet | The event stream dropped |
| Harnesses | No AI harnesses found | Codex's configuration would not parse |
| Skills | No skills installed | Doctor found 3 broken links |
| Discover | No results for "kubernetes log tailing" | One index answered, the other did not |
| Inbox | Nothing is waiting on you | postgres-mcp failed to install |
| Insights | Not enough history yet | The primary analyst hit its usage limit, so the fallback ran |
| Checks | Nothing here ships a check suite | 2 of 11 checks failed |
| Cleanup | Everything installed has been used | The usage store only goes back 6 days |
| Settings | Settings are unavailable while the router is stopped | The router sent a response this version does not understand |

An error state says what happened, where, and what to do, and shows the evidence — the Servers
error prints the `launchctl` output including the exit code and the log path.

## The chrome follows the state

This is the half that gets missed. A window still counting eleven servers over an "adopted
nothing yet" board is the populated app wearing the first-run screen, and a reader files it as
a bug. Three things are bound to the state on screen:

- the toolbar subtitle,
- the sidebar tallies, which hide rather than showing a count the state does not have,
- the health card, which cannot report "Router serving" over a board that says the router is
  unreachable.

## A loading state is designed, not stubbed

Determinate progress where a count is known (`7 of 11`), a live line naming what is being read,
and skeleton rows matching the shape, size and ground of the content they replace. A skeleton
of the wrong height guarantees a jump when the content lands.

## Two conditional states

**Overflow** is exercised and must stay exercised: eleven upstreams in a 250px jack field, a
seven-column table beside a 340px inspector, eighteen entries in a reconcile diff. **Disabled**
is exercised on eleven rules. **Offline** is `n/a` — the router is loopback-only, so there is no
network for the app to lose.

## Converting this to SwiftUI

Model the state as an enum with an associated payload — `case ideal(Data)`, `empty`,
`loading(Progress)`, `error(Failure)` — and switch on it in one `@ViewBuilder`. An enum makes
the four-way exhaustiveness a compile error rather than a review comment, which is the whole
reason the count is the specification.

- The empty, loading and error bodies are the composable state containers F2 already asks for,
  so a surface cannot ship populated-only by accident.
- The copy lives in a `*Copy` enum per surface, which is what makes it assertable.
  `M7DesignedStateTests` is the pattern: it already rejects short strings and placeholder text.
  Extend that suite to all 40 cells rather than writing a second one.
- Chrome that follows the state is a value read from the same enum — the toolbar subtitle, the
  tally visibility and the health card each derive from it rather than holding their own copy of
  the truth.

Acceptance: a test enumerates 40 cells and fails on any whose copy is absent, shorter than the
usable floor, or matches a placeholder pattern. A structure dump for one non-ideal state shows
the tallies absent from the tree, not merely transparent (M23).
