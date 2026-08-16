# P6 — the parity gate states the owner's cutover target

The gate printed `The cutover requires 83 of 83. It has 79.` The owner decided the target is
**82 of 83** at `bec9d18` (ORCHESTRATOR.md line 144, "CUTOVER TARGET"), because
`fixture-registry-search` is a standing exclusion and 83 of 83 is unreachable by construction.

This item changes what the gate SAYS about the finish line. It changes no coverage number, and
the section below is the measurement that shows it.

---

## 1. The premises, each checked against the repo rather than taken from the prompt

| Claim the change rests on | How it was checked | Result |
|---|---|---|
| The owner decided 82 of 83 | `git show bec9d18` | Commit "Ledger: cutover target is 82 of 83, decided", 2026-08-16. States "The denominator stays 83." |
| ORCHESTRATOR.md carries it | `grep -n "CUTOVER TARGET"` | Line 144: "82 of 83, decided by the owner 2026-08-16" |
| Exactly one row is excluded | `awk -F'\t' '$5=="accepted-uncomparable"'` over the manifest | One row, `fixture-registry-search`, manifest line 77 |
| The census is 83 | `awk '!/^#/ && NF>1'` + the `# rows: 83` pin | 83 both ways |
| Derived target matches the pin | 83 − 1 | 82 = `PARITY_CUTOVER_TARGET`; no drift |
| The "would RISE" reason is the row's own | the note in manifest line 77 | Verbatim: "deleting the row would leave the numerator alone and shrink the denominator, and the coverage figure would RISE" |

## 2. The arithmetic diff is exactly zero — proved two ways

### 2a. Mechanically, over the statements that can write a coverage number

Every statement assigning `proven`, `total`, `blocked` or `mismatched`, before and after:

```
BEFORE (9)                                AFTER (9)
143:proven=0; blocked=0; mismatched=0; total=0      147:… ; total=0; excluded=0
157:  total=$((total+1)); blocked=$((blocked+1))    163: (identical)
163:  total=$((total + 1))                          169: (identical)
166:  blocked=$((blocked + 1))                      172: (identical)
177:  mismatched=$((mismatched + 1))                197: (identical)
196:  blocked=$((blocked + 1))                      216: (identical)
207:  mismatched=$((mismatched + 1))                228: (identical)
214:  blocked=$((blocked + 1))                      235: (identical)
221:  proven=$((proven + 1))                        243: (identical)
```

The set is unchanged: same nine statements, same expressions, only line numbers shifted and
`excluded=0` appended to the initialiser. **No new write to any coverage variable exists.**
`excluded` is incremented in one place, inside the `blocked` branch, after `blocked` has already
been incremented — a partition of the blocked rows, never a subtraction from them.

### 2b. Empirically, by running the real gate before and after on the identical tree

Same worktree, same build, same manifest, back to back, under a confirmed sole parity lock. The
only difference between the two runs is the version of `parity-gate.sh` on disk.

```
BEFORE  md5 79f1a55ec9d547fd5aca0fbf63752b8f   3m47s   exit 1
AFTER   md5 e3f383ba405cd697e260060dc779263a   3m45s   exit 1
```

The coverage line is **byte-identical**:

```
parity: 79 of 83 rows proven (4 of them by suite only, not by wire comparison), 4 blocked. This is NOT a pass.
```

The blocked list is identical line for line. The whole diff between the two reports is the target
sentence and the new report block:

```
- The cutover requires 83 of 83. It has 79.
+ The cutover target is 82 of 83, decided by the owner on 2026-08-16 (…, bec9d18).
```

79 stays 79. 83 stays 83. Exit code stays 1.

## 3. What the report now says

```
cutover target: 82 of 83, decided by the owner on 2026-08-16 (ORCHESTRATOR.md "CUTOVER TARGET", bec9d18).
This gate REPORTS that target; it does not enact it. Every blocked row still exits 1 below,
and the cutover itself is the owner's call on R4-C's evidence, not this script's.

  1 of the 4 blocked row(s) is a STANDING EXCLUSION, not work — nobody is
  assigned to it and nobody is waiting on it:
    fixture     fixture-registry-search  registry-search

  It stays in the denominator deliberately: deleting it would leave the numerator alone
  and shrink the denominator, so the coverage figure would RISE. …

  3 row(s) stand between 79 proven and the target of 82.
  The blocked rows that are real work, and the item that would unblock each:
    control     control-auth-post-http   D-p1-a
    install     install-launchd-watch    D-p1-e
    install     install-rollback         R4-C
```

The excluded row is **named**, not subtracted. A reader gets the fraction, the target, which row is
excluded and why, and the distance to the target with each remaining row's owning item.
