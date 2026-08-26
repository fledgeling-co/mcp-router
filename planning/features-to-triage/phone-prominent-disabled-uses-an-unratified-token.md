---
status: to-triage
found-by: M31's sweep and gap-fix, 2026-08-26
---

# The phone control ladder dims a disabled primary to a token `DESIGN.md` §3 does not ratify

`DESIGN.md` §3 now states what "dims in place" means for a control whose resting state is an accent
fill: `--t4` on `--f3`, with a `--line` bezel where the control carries one. Every accent-filled
control in the design of record and on the store page draws that triple. `PhoneProminentButtonStyle`
draws a different one, and nothing has yet seen it render.

`.fill(isEnabled ? ColorToken.accent.color : ColorToken.raised.color)`,
`app/Sources/MCPRouterUI/Phone/PhoneButtonStyle.swift:47` at `03c34c3`, is

```swift
.fill(isEnabled ? ColorToken.accent.color : ColorToken.raised.color)
```

so a disabled phone primary lands on `--raised` rather than `--f3`, with the `--t4` label from `:42`
and no bezel. The Mac's `ProminentButtonStyle` reaches `--f3`/`--t4`/`--line` for the same state.
The file's own header comment at `:19-22` describes the phone ladder as "the same tokens" as the
shared treatment, which holds for everything except this fill.

M31's sweep prints thirteen findings across eight phone files, from three causes:

| Cause | Rows | Files |
|---|---|---|
| Disabled fill is `--raised` where §3 ratifies `--f3` | 8 | one per file |
| Dims only if SwiftUI installs `@Environment` on a `ButtonStyle` type | 4 | the files with a `.disabled(` call site |
| `makeBody` invoked directly, so SwiftUI installs nothing | 1 | `PairingResultSurfaces.swift` |

Reproduce with `python3 planning/evidence/M31/sweep-prominent-disabled.py`; the thirteen rows are
the `UNPROVEN` lines.

## Why the sweep reports these rather than failing on them

`PhoneProminentButtonStyle:32` reads `@Environment(\.isEnabled)` on the `ButtonStyle` type itself.
(anchor ``// **A nested `View` rather than `@Environment` on this type.** A `ButtonStyle` is not a``,
`app/Sources/MCPRouterUI/Controls.swift:169` at `03c34c3`) declines to do that on purpose, and
says why: a `ButtonStyle` is not a
`View`, whether SwiftUI installs a style's dynamic properties has changed between releases, and a
disabled button rendering at full strength is a defect no compile catches and no unit test sees. So
the phone's dimming is conditional on a behaviour a source read cannot settle either way.

`PhoneProminentButtonStyle(fillsWidth: fillsWidth).makeBody(configuration: configuration)`,
`app/Sources/MCPRouterUI/Phone/PairingResultSurfaces.swift:23` at `03c34c3`, and `:25` beside it,
remove the condition entirely:

```swift
PhoneProminentButtonStyle(fillsWidth: fillsWidth).makeBody(configuration: configuration)
```

A style constructed and invoked by hand is never installed by SwiftUI, so its `@Environment` property
holds the default at those two sites whatever the surrounding view's enablement is. That is settled
rather than unproven, and it is the strongest of the thirteen.

Pixels would settle the rest, and are unavailable: `make mock-fidelity` exits 3 on an inherited
break — anchor `switch surface {`, `app/Sources/MeasureDump/main.swift:206` at `03c34c3`, a
non-exhaustive switch missing `.readme`. Unblocking that is
a dependency of this item rather than part of it.

## One thing this is not

A disabled phone primary is **not** pixel-identical to an enabled secondary, and an earlier ledger
line said it was. They share the fill and nothing else. `PhoneStandardButtonStyle` enabled draws a
`--t1` label (`:66`) and a `--line-strong` bezel (`:73-76`); the disabled prominent draws `--t4`
(`:42`) and no bezel at all. Both land on `--raised`, which is the whole of the resemblance.

The distinction matters for how this gets triaged. "Disabled prominent is indistinguishable from
enabled secondary" would be the M31 defect again — a state drawn as its own opposite — and would be
urgent. What is actually here is a control dimming to an unratified token, which is a conformance
gap against §3.

## What triage has to settle

- **Whether `--f3` or `--raised` is right for the phone.** §3 was ratified against the Mac and the
  web surfaces, where `--f3` sits on `--ground` or a panel. The phone's disabled control may sit on
  a different ground, and if `--raised` is correct there then §3 needs the exception written into it
  with its measured ratio rather than the code diverging silently.
- **Whether the two hand-invoked `makeBody` sites are refactored or documented.** They defeat the
  environment read regardless of which token wins.
- **Whether the `@Environment`-on-a-`ButtonStyle` construct is replaced** with the nested-`View`
  construct `Controls.swift` uses, which would remove four of the thirteen findings by construction
  rather than by measurement.

Scheduling `MeasureDump/main.swift:206` first would turn the remaining rows from a source read into
a render, which is the only thing that closes them honestly.
