# The armed state, DEF-084

The same discipline as `../armed`, pointed at the other defect in the pair.

`ContainerContentChanging="OnRowContainerChanging"` was removed from both Discover bands in
`DiscoverBoard.xaml` and `DiscoverRow.ToString()` was reverted, the shell was rebuilt, and the lane
was run against that binary. `lane.log` records `discover.rows.recent` and `discover.rows.used`
both FAIL, each reading `60 of 60 row(s) publish the accessible name
'MCPRouter.Shell.Views.DiscoverRow'` - which is the defect verbatim - while `shell.navigationPane`
and all ten destinations stayed green. Restoring both returned the lane to 0 failures.

That the two arms redden SEPARATELY is the point: each names the fix it is watching, and neither
one covers for the other.

The per-destination `uia-shell-*.json` dumps are not kept here, for the reason `../armed/README.md`
gives.
