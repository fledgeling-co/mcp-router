# Arming transcripts for the Settings board's out-of-process arms

A predicate nobody has watched fail is indistinguishable from one that cannot fail. These files are
the runs where `scripts/windows/uia/shell-lane.ps1` went red under a defect planted on purpose, and
they are what `armed: true` on the Settings board's effect rows stands on.

Every plant here is a defect the product could genuinely have, not a synthetic one, and each was
reverted immediately afterwards.

## `unbind-supervisor-lane.txt`

**Planted:** the call in `SettingsBoardModel.UpdateToggle` that carries `LaunchAtLogin` to
`ILaunchAtLoginAgent` was removed, leaving the toggle to move the boolean and the store and nothing
else — which is exactly the state DEF-087 was filed against.

**Broke:** `settings.launchAtLogin.effect` and `settings.persistence`. **Two arms, not one**, and
the cascade is worth keeping rather than engineering away: after the fix, the sign-in switch is
seeded from the Windows task scheduler, so a switch that never reached the scheduler cannot survive
a restart either. Both failures describe the same planted defect from different sides.

**Held:** `settings.launchAtLogin.baseline`, `settings.persistence.store`,
`settings.copyEndpoint`, `settings.launchAtLogin.silence`, and every naming row above them. That
`settings.persistence.store` held is the useful part — the file arm did not follow the task arm
down.

## `store-writes-nothing-lane.txt`

**Planted:** `SettingsStore.Save` returned `true` without writing the file — a save path that
reports success it does not have.

**Broke:** `settings.persistence.store`, alone.

**Held:** everything else, `settings.persistence` included, because the sign-in switch's value came
back from the scheduler rather than from the store.

Taken together the two runs separate the two recorders: the task arm and the store arm can each go
red without the other, so neither is riding on the other's evidence.

## `icon-inert-and-no-confirmation-lane.txt` (DEF-101, DEF-102)

**Planted:** two defects at once, each the one its row was filed against. `NotificationAreaIcon.Apply(true)`
returned success without calling `Shell_NotifyIcon`, so the switch moved and the notification area
never heard about it. `ServersBoard.RemoveSelectedAsync` stopped reading
`RequireConfirmationOnDestructive` and never raised a confirmation, so the destructive button acted
straight away.

**Broke:** `settings.ambientIcon.effect` — "INERT BEYOND THE PROCESS: the switch reads On through
the plane and the notification area reports no icon". `settings.requireConfirmation.effect` — "with
the setting On, pressing Remove did not produce a confirmation this lane could decline".
`settings.requireConfirmation.accepted`, as a consequence: the server the accept arm would have
removed had already gone in the arm above it.

**Also observed, and kept rather than engineered away:** `settings.ambientIcon.silence` reported
`unoracled` — "the switch could not be driven back to Off (stuck at On)". With no icon in place,
`NIM_DELETE` fails, `UpdateToggle` refuses to move the state, and the switch snaps back. The arm
declined to call that either a pass or a failure of removal, which is the correct answer.

**Held:** `settings.ambientIcon.baseline`, `settings.requireConfirmation.baseline` and
`settings.requireConfirmation.silence` — the silence arm passes under this plant precisely because
the plant removes the prompt, which is what that arm is looking for.

## `icon-never-removed-and-answer-ignored-lane.txt` (DEF-101, DEF-102)

**Planted:** the mirror of the first, and the subtler direction in both cases.
`NotificationAreaIcon.Apply(false)` returned success without removing the icon. `RemoveSelectedAsync`
raised the confirmation unconditionally and then threw the answer away.

**Broke:** `settings.ambientIcon.baseline` — "the switch reads Off and the notification area still
holds the icon, so the arms below would be about a leftover", which is the leftover guard doing the
only job it has. `settings.ambientIcon.silence` — "Turning the setting off told the user something
untrue". `settings.requireConfirmation.effect` — "the confirmation was declined and the router no
longer lists lane-witness-alpha. The dialog was a decoration over an operation that had already been
decided". `settings.requireConfirmation.silence` — "with the setting Off, pressing Remove still
produced a confirmation. The switch is not being read".

**Held:** `settings.ambientIcon.effect` passed here over an icon the plant had left behind rather
than one the run placed, which is exactly what the baseline arm exists to catch and did.

Between the two runs every arm added for DEF-101 and DEF-102 has been watched red except
`settings.requireConfirmation.baseline`, which is a precondition guard over the lane's own router;
it was watched report `unoracled` on 2026-09-02T16:06Z when a router that had answered correctly
with an empty list came back as no answer at all.

## `def-301-unit-plant.txt` (DEF-301, the unit half)

**Planted:** `AmbientSurfaceModel.State` initialised to `AtRest` again, and
`AmbientStatusMapping.FromStatusJson` made to return `AtRest` on a body it cannot parse — the
defect as filed, plus the reading of it one layer down.

**Broke:** `BeforeAnyReading_TheSurfaceDoesNotClaimTheRouterIsReady`,
`Apply_ReportsWhetherTheRenderedStateMoved`, and both parameterisations of
`AnUnreadableAnswer_IsNeverAtRest` that carry a body. 4 failed of 692.

**Held:** everything else, including `DefaultOfTheEnum_IsUnknown` — the enum member was not part
of that plant, so the test that asserts its position says nothing about it and is not counted as
having been armed by this run.

## `def-301-planted-lane.txt` and `def-301-planted-lane-2.txt` (DEF-301, DEF-300)

**Planted, in both runs:** `AmbientSurfaceModel`'s default put back to `AtRest`, the ambient poll
never started and its first read never taken — DEF-301 exactly as it was filed, a surface with no
reader in the build at all. In the same build, `NotificationAreaIcon.StartWatchdog` was emptied, so
nothing in the process could notice an Explorer restart — DEF-300 exactly as it was filed.

**Broke:** `ambient.routerStopped`, `ambient.workInFlight`, `ambient.signInWaiting` and
`ambient.silence`. Three of the four report the pane frozen at `'Router ready' / 'All systems quiet.
No active calls or queued items.'` while this script had stopped the router and confirmed over the
loopback port that nothing answered `/status`, or while a stand-in was answering it with three calls
in flight. That sentence is the whole of DEF-301, printed by the instrument.

**Held, and it is recorded because it matters:** `ambient.routerRunning` PASSED under the plant. A
surface frozen at `'Router ready'` satisfies an arm that expects `'Router ready'`, so that row can
never be armed by this defect and stays `armed: false`. It is why the section takes the router away
first and why the other four exist.

**Never reached:** `settings.ambientIcon.survivesExplorerRestart` read `unoracled` in both runs —
"the icon was not in the notification area before Explorer was restarted". The planted build's shell
did not survive the ambient section (`ambient.shellSurvivedRouterLoss` failed with one death in the
first run and three in the second), so there was no icon for Explorer to be restarted under. **That
predicate has therefore never been watched to fail**, which is why DEF-300 is `answered` rather than
`fixed` and why CASE-0477 is `armed: false`. On an earlier planted run the same day — before the
baseline arm existed, and whose `lane.log` was overwritten by the clean run that followed — the icon
WAS found again 73 seconds after the restart with the watchdog removed. That observation has no
surviving artifact and is carried on DEF-300's resolution as an observation, not as evidence.
It is also no longer the most useful thing known about that arm: see
`def-300-oracle-unreliable-lane.txt` below, where the reader behind it was caught answering
wrongly in both directions inside one run.

**Also observed:** the planted build's shell terminated during the ambient arms in both runs, and
the shipping build's did not in any of the three runs it was measured in. Nothing here explains why,
and no claim is made about it beyond what `ambient.shellSurvivedRouterLoss` records on the day.

## `def-300-oracle-unreliable-lane.txt` (DEF-300 — the run where the READER failed)

Not a planted defect. This is the run that caught the instrument, and it is kept for the same
reason the plants are: an arm whose oracle has been seen unable to say no cannot have its greens
read as unqualified.

**What happened:** `settings.ambientIcon.explorerRestart.baseline` — the row that exists to prove
`Shell_NotifyIconGetRect` can answer "no icon" across an Explorer restart — answered **S_OK with no
instance of MCPRouter.Shell running at all** and the GUID's record deleted beforehand. In the same
run, twenty seconds later and with the application running and the icon confirmed present, the same
reader answered `0x80004005` for two full minutes after the second restart. The reader was wrong in
both directions inside one run, under conditions identical to the three runs either side of it in
which it behaved.

**What it changed:**

- The baseline is graded `unoracled` rather than `fail` when it says yes. There is no product
  running while it is read, so a yes is the reader failing, not the shell — and
  `settings.ambientIcon.survivesExplorerRestart` degrades to `unoracled` behind it rather than
  passing on a reading nothing supports.
- `NotificationAreaIcon`'s watchdog stopped asking that question. It called `IsPlaced()` and
  re-added on a false, which inherits both errors and demonstrably did — the shipping build sat
  still for two minutes here while the tray answered S_OK over an icon that was not there. It now
  re-asserts with `NIM_MODIFY` and treats the shell's refusal as the signal to add.

**Kept as evidence for:** CASE-0476 and CASE-0477, both of which cite it. Neither is `armed`.
