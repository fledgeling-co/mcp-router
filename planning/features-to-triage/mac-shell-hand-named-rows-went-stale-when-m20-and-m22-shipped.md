---
status: to-triage
found-by: G10's gap-fix, 2026-08-26, enumerating every red mac-shell.sh holds rather than the first one
---

# `mac-shell.sh` hand-names two facts the app has since changed, and both are red

`mac-shell.sh` was reached by `make acceptance` for the first time in four days once G10 made the
target run every lane. It fails, and running it with `fail` recording instead of exiting shows it
holds **two independent reds**, not one. Both are hand-written expectations about the product's
intended surface that the product has since moved past. Neither is the app misbehaving.

    FAIL: the window title is 'Insights', which is not a destination name (§3.7 forbids the app's name)
    FAIL: File / Export library… is not in the menu bar at all — §3.4 forbids hiding a disabled command

## 1. The destination allow-list is stale by two

The seven-name allow-list decides whether the window title is a destination name. `M22` shipped the
Harnesses and Insights boards, so the app now has nine. The lane contradicts itself inside one run:
it passes *9 destination rows share one height* and then *all seven destinations are in the
accessibility tree*.

Whether nine is the intended set is `M22`'s question, which is why G10 reported this rather than
extending the list.

## 2. The export row still says File, and the command moved to Library at M20

    EXPORT_LINE="$(awk -F'\t' '$1 == "File" && $2 == "Export library…" …

`MenuCommand.swift` records the move as deliberate — *"Library (M20). `exportLibrary` moved here
from File, which is where the mock draws it"* — and titles it `Export Library…` with a capital L.
So the row is wrong on the menu **and** on the title.

Two of the four reds the survey printed are cascade from this one: `EXPORT_LINE` comes back empty,
and the two checks below it read empty fields and fire on their own messages. One defect, three
lines of output — which is worth knowing before anybody counts reds.

The lane's own comment anticipates a deliberate edit here *when export ships*. What happened instead
is that the command moved menus, which the comment did not anticipate and the hand-written row could
not notice.

## Why this is not simply "update two rows"

The derived A22 block in the same file already checks `Library / Export Library…` correctly and
**passes**, because it builds its expectation from `MenuCommand` rather than restating it. So the
repair on the table is not "change File to Library" — it is that a hand-named row duplicating a fact
the model already carries will go stale again, exactly as this one did and as the lane's hand-picked
`swiftc` file list has now done four times.

That is a change to how `M1`'s evidence lane derives its expectations rather than a repair to it,
which is why G10 left both reds standing and wrote this instead.

## Scope

- Decide whether nine destinations is `M22`'s intended set, and make the title check read the set
  from the same place the app does rather than from a list in the lane.
- Decide whether the `File / Export library…` row should be corrected, or retired in favour of the
  derived A22 coverage that already asserts the same thing and does not go stale.
- Neither is G10's to settle: G10's line throughout was to clear what prevents measurement and
  report what measurement finds.
