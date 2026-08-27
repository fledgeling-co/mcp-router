---
status: to-triage
found-by: the serialized merge of G15/G16/G17/G19, 2026-08-27, running G18's own gate afterwards
---

# The wave enumerated three surfaces and bound none, so the gate it was measured by got worse

G15, G16 and G17 enumerated the three surfaces the campaign had been missing, wrote cases for
each, and ran them. `make surface-reconcile` — the gate G18 built to measure exactly this — is
**still red, and the three have not moved**:

```
SHIPPED AND UNENUMERATED
  FAIL destination:harnesses
  FAIL destination:insights
  FAIL sheet:readme
UNEXPLAINED ADDRESSLESS SURFACE
  FAIL SURF-025 (Mac Harnesses board)
  FAIL SURF-026 (Mac Insights board)
```

**Enumeration alone cannot clear `SHIPPED-UNENUMERATED`. The gate needs the binding.**
`planning/test-campaign/surface-bindings.json` is **byte-identical** across `fabd028`, `ai/g16`,
`ai/g17`, `ai/g18`, `ai/g19` and `HEAD` — 19 bindings, none of them for the three.

**And the wave moved the count the wrong way.** Each newly enumerated board arrives as a *fresh*
`UNEXPLAINED-ADDRESSLESS` failure, because a surface exists with nothing tying it to an address the
product ships. Measured by running G18's classifier against both trees with the same live oracle:

| | shipped-unenumerated | unexplained-addressless | covered |
|---|---|---|---|
| before (`fabd028`) | harnesses, insights, sheet:readme | SURF-025 | 19 |
| after (all three) | harnesses, insights, sheet:readme | SURF-025, **SURF-026** | 19 |

`SURF-025` became addressless the moment G15 landed, so the baseline was already four rather than
the three the merge brief assumed.

## This is G18's gate working, not failing

The two classes are separate on purpose, and this is the distinction earning its keep on its first
real use: *shipped and nobody enumerated it* and *enumerated and nothing says which shipped thing
it is* have different remedies, and a gate that merged them would have gone green here while three
surfaces still had no address. G18's own delivery note said the gate *"lands red on purpose"*
because writing the bindings there would have turned it green with no case behind them. The cases
now exist; the bindings still do not.

## The remedy is small and the item is not

One binding line each. What makes this worth an item rather than a footnote is that **four
runners, a reconciliation and a merge all passed over it** — each one measured what it was asked
to measure, and none was asked whether the gate that names the gap had actually moved. The wave
was reported as closing three surfaces on the strength of enumeration and cases, which is what a
reader would assume closes them.

## Scope

- Bind `destination:harnesses`, `destination:insights` and `sheet:readme` in
  `surface-bindings.json`, and say what expectation each binding carries — G18 split *address*
  from *expectation* deliberately, so a binding is not merely an address.
- Confirm the three move out of `SHIPPED-UNENUMERATED` **and** that `SURF-025`/`SURF-026` leave
  `UNEXPLAINED-ADDRESSLESS`, rather than one moving and the other staying.
- State whether `make surface-reconcile` reaches exit 0, and if not, what remains and why.
- Consider whether a surface enumerated with no binding should fail the *campaign's* own check as
  well, since a reader of `campaign.py check` currently sees no sign of it.
