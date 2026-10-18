---
status: to-triage
found-by: intake divergent pass, from the inbox band having no Windows carrier · 2026-08-30
reckon-sources: [SURF-046, REQ-036]
target-note: SURF-046 `Windows toast notification and its COM activator` records that WIN22 shipped it and REQ-036 states it, and REQ-036 states the toast, its two buttons and what Review opens; neither existed when the `none` was declared on 2026-08-30.
---
# How a waiting decision reaches a Windows user who is not looking at the app

- origin: intake divergent pass, 2026-08-30
- audience: anyone on Windows who queues something from their phone and then does something else
- platforms: windows
- proposed-by-ai: true

## What and why

The Inbox depends on the user finding out that something is waiting. On the Mac that is the menu-bar
popover's inbox band, which is ambient and always on screen. WIN11 decides what the Windows ambient
surface is, but a notification-area icon is weaker than a menu-bar item in one specific way — 
Windows 11 hides such icons behind the overflow chevron by default, so a badge there may never be
seen.

Windows has a native channel macOS's menu bar does not: toast notifications through the Action
Center, plus taskbar badging and progress. A queued item raising a toast is the platform-idiomatic
answer, and the toast can carry actions directly.

The restraint matters more than the mechanism, and it comes from the product's own stated behaviour.
The update gate is explicit that most updates "promote silently with no notification at all" — the
product's discipline is that a notification means a decision is genuinely required. A Windows
implementation that toasted on every event would break that discipline while appearing to add a
feature.

There is one hard rule this brief must respect: WIN10's guarantee that nothing installs before
approval. A toast may carry an action that opens the review sheet. A toast action that installs
directly would move an irreversible decision into a transient surface the user might dismiss by
reflex, which is precisely the affordance the phone-queues-never-installs design exists to prevent.

## Acceptance sketch

- A queued item raises a toast when the app is not in the foreground, and the toast says what is waiting and where it came from.
- Toast actions reach the review sheet; no toast action installs, approves or grants anything directly.
- Events that do not require a decision — a silent successful update, a routine reap — raise no toast.
- Notification frequency is bounded: several items arriving together do not produce several toasts.
- The user can turn notifications off from Settings, and the app honours the Windows system-level setting and Focus Assist.
- A taskbar badge reflects the undecided count and clears when the count reaches zero.

## Assumptions made writing this

- Assuming toasts complement the WIN11 ambient surface rather than replace it, since a toast is transient and the ambient surface is persistent.
- Assuming the undecided count is the right badge value, matching the Inbox board's own grouping.
- Assuming notifications default to on for waiting decisions, since a decision nobody sees blocks the product; the update gate's silence for non-decisions is preserved regardless.
