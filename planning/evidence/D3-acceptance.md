# D3 — the deferred register: phone copy, and the harness limit

Branch `ai/d3`, from `main` @ `bec9d18`. Four children. Two closed by code, one closed as
**not-a-defect** against a measurement that contradicts the register, one carried to the owner as a
concrete proposal rather than a question.

Every row below was reproduced before it was decided. That is the rule this fleet learned by
measuring seven register claims and finding six of them wrong; D-i3-a is the seventh.

---

## The four children

| Child | Premise reproduced? | Outcome |
|---|---|---|
| `M5-d` | **Yes** | **Closed.** `axkit pick` added, proven, mutation-tested |
| `D-i3-a` (the test half) | **No — refuted** | **Closed as not-a-defect**, with the probe that refutes it, plus a permanent guard |
| `D-i3-a` (the product half) | **Yes** | **Left open.** A shared design decision, correctly not taken inside an item |
| `D-i3-g` | **Yes** | **Proposal below.** Exact strings, owner's call |
| `D-i3-h` | **Yes** | **Proposal below.** Exact strings, owner's call |

---

## M5-d — an `axkit` verb that can press a non-`AXButton` role · CLOSED

### The premise, reproduced

`scripts/acceptance/axkit.swift`'s `press` matches `AXRole == "AXButton"` only, so no rendered pass
could drive a segmented filter. Confirmed at source, and the restriction is deliberate: a **menu
item**'s `AXPress` returns `.success` and does nothing to a background app, because its action
reaches the window through `@FocusedValue`. Widening `press` would reopen that silent false green,
so the fix had to be a second, narrower verb.

### The measurement that told me what to build

Launched Debug `MCPRouter.app` with `open -g`, read by pid, **load 18, Ghostty frontmost at start
and at end** — the app never took the screen.

```
role=AXRadioButton subrole=AXSegment title=[] value=[1] desc=[Best match]
role=AXRadioButton subrole=AXSegment title=[] value=[0] desc=[Most used on Smithery]
role=AXRadioButton subrole=AXSegment title=[] value=[0] desc=[Recently added to Smithery]
role=AXRadioGroup  subrole=       title=[] value=[]  desc=[]
```

Three facts, none of them assumed: a segment is `AXRadioButton` / subrole `AXSegment` inside an
`AXRadioGroup`; its label lands in `AXDescription` and its title is empty; and **`AXValue` reads
`1` for the chosen segment and `0` for the others**. That last one is the whole reason the verb can
be honest — it is an observable, where `AXPress`'s return code is only an acceptance.

Cleanup's pane vends the same shape (`All 3` / `Servers 3` / `Skills`). Evals' pane vended no radio
group under the `populated` scenario.

### What was built

`axkit pick <pid> <segment description substring>`. It presses the segment, **re-walks the tree**,
and requires that exactly one segment in the target's own radio group reads `AXValue == 1` and that
it is the one named. Exit codes are the contract, because every call site in these scripts is
`>/dev/null || fail` and a distinction that lives only in printed text is one the caller cannot see:

| exit | meaning |
|---|---|
| `0` | the named segment was not chosen before and is chosen now — this call switched it |
| `3` | it was already chosen, so this call **drove nothing** |
| `1` | not chosen now, or the substring named more than one segment, or none |

`3` rather than `0` is the point: a gate that cannot tell "I switched the filter" from "the filter
was already there" can drive nothing and still pass. Under `|| fail` that now fails by default.

### Proven against the running app · load 49 · never frontmost

```
BEFORE: Best match=1 Most used on Smithery=0 Recently added to Smithery=0
switch to 'Recently added'  -> OK Recently added to Smithery                    (exit 0)
AFTER:  Best match=0 Most used on Smithery=0 Recently added to Smithery=1
same again (drove nothing)  -> ALREADY Recently added to Smithery               (exit 3)
AMBIGUOUS 'Smithery'        -> 'Smithery' is ambiguous in this window — it names
                               Most used on Smithery | Recently added to Smithery (exit 1)
no match 'nonesuch'         -> no segment matching 'nonesuch' — offered: …      (exit 1)
empty needle                -> an empty substring matches every segment         (exit 2)
back to 'Best match'        -> OK Best match                                    (exit 0)
FINAL:  Best match=1 Most used on Smithery=0 Recently added to Smithery=0
front at start=Google Chrome · front at end=Google Chrome
```

### Mutations

| # | Mutation | Result |
|---|---|---|
| A | press removed, `accepted` faked `true` | **CAUGHT** — `ERR 'Recently added to Smithery' is not the chosen segment — group of 3 reports chosen: Best match` (exit 1) |
| B | exclusivity weakened to `!chosen.isEmpty` | **SURVIVED**, and it is reported rather than hidden |

Mutation A proves the load-bearing half: the verb keys on the observable, not the return code, and
the label-equality check fires. Mutation B removed the `chosen.count == 1` clause and survived,
because a SwiftUI `Picker` is genuinely exclusive and no live input makes a group report two
selections. **That clause is therefore a defensive guard against a broken read and is not proven by
any measurement here.** Saying so is more useful than a mutation aimed to pass.

### What was deliberately NOT done

The verb is not wired into `m5-discover.sh` or `m7-evals-cleanup.sh`. Doing so changes M5's and
M7's acceptance surfaces and re-runs their gates, which is their work, not D3's. Both scripts'
comments — which said the verb "does not exist" — were corrected to state that it now does, what
its exit codes mean, and that wiring it in is registered follow-on work. Comment-only: no assertion
in either script changed, so neither gate needed re-running.

---

## D-i3-a — Dynamic Type · SPLIT, and half of it is refuted

The register makes two claims. They have different answers.

### Claim 1 — "no phone surface scales with Dynamic Type" · TRUE · left open

`TypeToken.font` is `.system(size: size, weight: weight)` — a fixed size, no `@ScaledMetric`, no
`relativeTo`. `DESIGN.md` §2 fixes the eight sizes deliberately. Changing it is a change to a
merged shared surface and to the design authority, so it is correctly not taken inside an item and
stays open.

### Claim 2 — "I1's Dynamic Type test overrides a UIKit trait that measurably never reaches the SwiftUI view" · **FALSE**

Reproduced with a probe that reports the environment the SwiftUI view actually sees, through the
same `host(_:contentSize:)` helper the test under suspicion uses:

```
dts=large          sizeCategory=large                          trait(view)=UICTContentSizeCategoryL
dts=accessibility5 sizeCategory=accessibilityExtraExtraExtraLarge
                                                   trait(view)=UICTContentSizeCategoryAccessibilityXXXL
```

The override reaches the SwiftUI environment, and it varies with the argument. **The register's
claim is false**, and its instruction — *"do not copy that pattern"* — was steering future runners
away from a helper that works. `testTextIsNotClippedAtAccessibilitySizes` also **passes** on a
healthy simulator.

**Closed as not-a-defect.** The probe was converted into a permanent guard,
`testHostPropagatesContentSizeIntoTheSwiftUIEnvironment`, so that if a future UIKit stops honouring
`setOverrideTraitCollection` the A7 loop cannot quietly become three identical runs of one
assertion — this fails first, and says why.

---

## The iOS lane is red on `main`, and 43 of its 45 failures are the simulator

Found while measuring D-i3-a, inherited rather than caused. Recorded because it blocks anyone
gating on `make test-ios`.

| Tree | Simulator | Result |
|---|---|---|
| clean `bec9d18` | iPhone 16 Pro (booted for days) | exit 2 — **28 tests, 45 failures** |
| `ai/d3` | same | exit 2 — **29 tests, 45 failures** (identical set) |
| clean `bec9d18` | iPhone 17 Pro Max (fresh boot) | exit 65 — **28 tests, 2 failures** |
| `ai/d3` | same | exit 65 — **29 tests, 2 failures**, and D3's new test passes |

I3's evidence records this suite at exit 0, 28 tests, `TEST SUCCEEDED`.

The 43 extra failures split on an exact line: **every one of the 10 passing tests reads the UIView
tree** (bounds, `UITabBar`, the generated `Info.plist`), and **every one of the 18 failing tests
reads the accessibility tree** — all of them failing with an empty result (`"looked for … in: "`,
`"no controls were measured, so this proved nothing"`). No product change can empty the
accessibility tree across three independent suites while leaving layout intact. The long-booted
simulator's accessibility bridge was returning nothing.

This is not a re-run-until-green: the second run used a **different device to test a stated
hypothesis**, and it would have been equally reportable had it stayed red.

**Two failures are real and pre-existing on `main`,** on a healthy simulator, unrelated to D3:

```
PhoneSurfaceTests testRowHeightIsIndependentOfNameLength — no row was found in either render,
                                                            so nothing was compared
PhoneSurfaceTests testSkeletonMatchesTheRowItReplaces    — same
```

Both are I1 surfaces and both fail honestly (they refuse to compare two empty sets rather than
passing vacuously). Not D3's to fix; registered for the orchestrator.

---

## Gates

| Gate | Exit | Output |
|---|---|---|
| `make lint` | **0** | swiftformat clean · swiftlint `0 violations, 0 serious in 449 files` · `no-raw-design-values: clean` (107 files, 69 under the rules) · `no-wire-codable: clean`, 1 exemption |
| `make build-mac` | **0** | `** BUILD SUCCEEDED **` |
| iOS suite, fresh simulator | 65 | 29 executed, 2 failures — **both pre-existing on `main` on the same simulator**; D3's own test passes |
| `axkit` compile | 0 | no warnings |
| grok `grok-4.6` review | ran | 4 findings, all 4 fixed — see below |
| `make parity` | **not run** | P5 owns the parity lock this wave; a second concurrent run is refused by design |

### The grok gate

Briefed to refute, and told that finding nothing is a failed review. It returned substantive
content citing real line numbers, so the lane genuinely ran rather than exiting 0 on a dead session.

| # | Finding | Disposition |
|---|---|---|
| 1 | `ALREADY` exited 0, and every call site is `>/dev/null \|\| fail`, so the distinction the comment called load-bearing was invisible to callers | **Fixed** — `ALREADY` now exits 3 |
| 2 | `first(where: contains:)` silently takes the first of several matches; `Smithery` names two of Discover's three segments and `1` matches `All 16` | **Fixed** — more than one match is an error naming them; an empty needle is refused |
| 3 | The element is held across the press, so the re-read can hit a dead or cached identifier — a false red or a false green | **Fixed** — the tree is re-walked after the press |
| 4 | The `segments` walker had no depth cap, unlike every other walker in the file | **Fixed** — capped at 24, matching `dump` |

It also noted the M5/M7 comments would not survive a follow-on that ignored the exit status. Both
comments now state the exit-code contract explicitly.
