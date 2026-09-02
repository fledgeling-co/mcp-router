# The armed state, DEF-089

This directory is the lane's own output from a run taken with the fix DELIBERATELY REVERTED, so
that the arm can be shown to fail on the defect it claims to catch rather than passing vacuously.

`AutomationProperties.Name="Destinations"` was removed from the NavigationView in
`app/windows/MCPRouter.Shell/Shell/ShellWindow.xaml`, the shell was rebuilt, and the lane was run
against that binary. `lane.log` records the result: `shell.navigationPane` FAIL, and every other
row - all ten destinations, the settings census, both Discover row arms and the detail dialog -
still green. Restoring the attribute returned the lane to 0 failures
(`planning/evidence/WIN-SHELL/run/`).

The per-destination `uia-shell-*.json` dumps are NOT kept here. They are several megabytes and say
nothing this run's verdict does not; the tree of the shell at rest lives once, under `run/`.
