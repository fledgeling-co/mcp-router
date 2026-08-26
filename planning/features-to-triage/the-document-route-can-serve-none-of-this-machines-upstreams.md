# The document route can serve none of this machine's twenty-one upstreams

**Raised by:** M30's gap-fix, 2026-08-27, from a measurement rather than a design idea.
**Depends on:** M30 (shipped). **Blocks:** any claim that the capability panel shows a real user
anything.

## The measurement

`scripts/acceptance/m30-reach.mjs` applies the route's own guard — `!isStdio(u) || !u.cwd`, taken
byte-for-byte from `src/control.ts` — to the developer's live `servers.json`.
`planning/evidence/M30-reach.txt` is the run:

```
upstreams : 21
SERVED 0 of 21
outcomes: {"404 noPackageDirectory":21}
```

Fourteen are stdio and declare no `cwd`; seven are http and carry no local directory at all. Every
one of the twenty-one lands in the same 404. The panel M30 built therefore draws exactly one state
on this machine — the refusal frame in `planning/evidence/M30-look/readme.refused.png` — and the
served frame beside it was produced by a server this repository constructed for the purpose.

## Why this is a decision and not a defect

`spec-M30.md` §1 refuses to derive the package root from anything but `cwd`, and the M30 verifier
judged that refusal **correct**: for `npx -y @scope/pkg` the first argument is a flag, and for
`node /path/dist/index.js` its dirname is the build directory rather than the package. Every
inference that would widen the route is a guess about a packaging convention this router does not
otherwise use, and the route reads files off disk and returns their bytes — so widening it widens a
readable surface on a trust boundary. That is the owner's call, which is why this is a brief and not
a change.

The cost of leaving it is equally plain: a feature that is complete, tested and reachable by nobody.

## The options, with what each would cost

| | Shape | What it buys | What it costs |
|---|---|---|---|
| **A** | Leave it. `cwd` or nothing. | No new surface. The trust boundary is exactly where the spec put it. | The panel is unreachable for every real upstream until somebody hand-edits a config. |
| **B** | An explicit optional `packageRoot` member per server, honoured only when declared. | Reachability without inference: the root is still declared rather than guessed, and the owner opts in per server. | A new config member in both implementations, its own parity vectors, and a second path that must be refused the same way `cwd` is (escape, absolute, unreadable). |
| **C** | Derive from `args[0]`'s dirname when it names an existing file. | Costs the user nothing. | Wrong for both real shapes: a flag for `npx`, the build directory for `node dist/index.js`. Would need a climb to the nearest `package.json`, which is a packaging convention by another name. |
| **D** | Resolve an `npx`/global package specifier to its installed location. | Would cover the eleven `npx` upstreams. | Reads a package manager's cache layout, which is neither observed nor stable, and installs nothing — so it answers for whatever version happens to be cached. |

**Recommendation: B.** It is the only option that makes the route reachable without the router
inferring anything: the root stays a thing a human declared, which is the property §1 was protecting,
and the refusals already written for `cwd` apply unchanged to a second declared path. A is defensible
if the panel is meant for packages the router installed itself, in which case the honest follow-up is
to have the installer record the root it installed to — that is a fifth option and a bigger item.

C and D are recommended against on the evidence above rather than on taste.

## What triage needs to settle

Whether the capability panel is meant to serve **any declared upstream** (B) or only **upstreams this
router installed** (A plus an installer that records its root). The two produce different features;
neither is a widening of M30 so much as a decision about who the panel is for.
