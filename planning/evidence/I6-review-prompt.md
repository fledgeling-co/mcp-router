You are the out-of-family review gate on a finished feature branch. Read the repo
yourself; do not take this description on trust. Attack the work, not the write-up.

REPO: /Users/lukerhodes/Dev/mcp-router   BRANCH: ai/i6 (worktree .worktrees/I6)
Diff against main: `git diff main...HEAD`

THE ITEM (I6): make Mac-side approval of queued MCP-server installs FAST, without
moving the security boundary. It adds an inbox band to the menu-bar popover and a
notification when something arrives, so approving is a couch action rather than a
walk to the laptop.

THE BOUNDARY IT MUST NOT MOVE, stated as a principle in DESIGN.md:
  "The phone queues; it never installs. Pairing grants a remote party the ability
   to put executable code on a laptop, so the phone's commit bar sends items to
   the Mac's inbox for review. This is narrower than 'remote install' and
   deliberately so."
Nothing in this branch may let an install happen without a human at the Mac acting.

CONTEXT THAT MATTERS: a sibling item (I5) just measured the pairing transport and
found there ISN'T ONE — neither side implements it, so nothing phone-originated
can reach this inbox today. The band and notification are Mac-side and still
correct, but any spec text or test that ASSERTS a phone-originated arrival as a
thing that happens today would be claiming something false.

Read at least: planning/specs/spec-I6.md, app/Sources/MCPRouterKit/Inbox/*.swift,
app/Sources/MCPRouterUI/Shell/MenuBarInboxBand.swift, InboxNotificationDelegate.swift,
ShellModelInbox.swift, and the tests in app/Tests/.

ANSWER THESE, each with a file:line and a verdict, briefly:

1. Does anything here let an install proceed without a human at the Mac acting?
   Include indirect paths: a notification action, a default, a timer, an undo
   window that expires into acceptance, a test helper wired into a release path.

2. Does any shipped copy, spec clause or test assert that a phone-originated
   arrival happens today, when I5 measured that no transport exists?

3. The 26 mutations claim every assertion can go red. Name any assertion you can
   see that CANNOT fail for the right reason — one that would pass against a
   broken implementation. This fleet has twice shipped assertions that could only
   ever block or only ever pass, so treat this as the highest-value question.

4. Notification handling on macOS is easy to get subtly wrong. Anything wrong with
   the delegate, the authorization request, the action identifiers, or what
   happens when the app is not running, is frontmost, or the notification is
   delivered twice?

5. Anything else a careful reviewer would refuse to merge.

If you find nothing in a section, say "nothing found" and say what you checked.
A review that finds nothing everywhere is more likely to be a review that did not
run than a clean branch.
