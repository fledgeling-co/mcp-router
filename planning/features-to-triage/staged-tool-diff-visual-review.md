# Visual Diff Review and Approval for Staged Upstream Tool Changes

- origin: test-campaign and reckoning ideation · 2026-08-25
- audience: Developers reviewing upstream tool definition updates and structure modifications
- platforms: mac, iphone, ipad
- proposed-by-ai: true

## What and why
When an upstream server updates its advertised tools, the desktop and mobile applications present a clear visual diff comparing previous and new tool definitions before approving changes. Upstream servers that modify their tool descriptions or parameter requirements can silently change agent behavior without the user noticing. Providing an explicit visual review interface allows operators to inspect modified descriptions and approve or hold changes before tools are served to AI sessions.

## Acceptance sketch
- Modified tool surfaces appear with an Attention indicator on the server management view.
- Opening the review interface displays a side-by-side comparison highlighting modified descriptions and parameter changes.
- Users can approve all changes in a single action or keep the server held in its previous state.
- Approving promoted tools immediately updates the active catalog served to connected AI clients.
- Mobile companion clients receive notification of pending tool diffs and can review changes remotely.

## Assumptions made writing this
- Assuming pending tool changes remain held until explicit user approval rather than automatically applying after a time delay.
- Assuming visual diffs emphasize parameter description changes because AI models use descriptions directly for tool selection.
