# Arming transcripts for the Settings board's out-of-process arms

A predicate nobody has watched fail is indistinguishable from one that cannot fail. These two files
are the runs where `scripts/windows/uia/shell-lane.ps1` section 3c went red under a defect planted
on purpose, and they are what `armed: true` on CASE-0366..CASE-0371 stands on.

Both plants are defects the product could genuinely have, not synthetic ones, and each was reverted
immediately afterwards.

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
