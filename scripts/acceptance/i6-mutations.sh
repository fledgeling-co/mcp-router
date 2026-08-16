#!/bin/bash
# I6 mutation gate.
#
# A series of agreeing observations bounds the AGREEMENT rate; it cannot say what a term MEASURES.
# Each mutation below breaks one behaviour and requires the named clause to go red. A clause that
# stays green under its own mutation is a clause that measures nothing, and this script reports that
# as a failure rather than as a pass.
#
# Every mutation is applied, tested, then reverted with `git checkout -- app`, so an interrupted run
# leaves the tree recoverable. Commit this script before running it: the revert is scoped to `app`
# precisely so it cannot take an uncommitted edit to this file with it, but a mutation left applied
# by a kill -9 is still recovered by hand.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 2

pass=0
fail=0

mutate() {
  local name="$1" file="$2" filter="$3" snippet="$4"
  local src
  src=$(printf 'import sys\np = sys.argv[1]\ns = open(p).read()\nbefore = s\n%s\nif s == before:\n    sys.exit("the mutation matched nothing — it is not testing what it claims")\nopen(p, "w").write(s)\n' "$snippet")

  if ! python3 -c "$src" "$file"; then
    echo "SKIP  $name  <- the mutation could not be applied"
    fail=$((fail + 1))
    return
  fi

  local out status
  out=$(cd app && swift test --filter "$filter" 2>&1)
  status=$?
  # Reverts `app` rather than the named file, because one mutation below has to touch two files at
  # once: a case added to a closed enum does not compile until the switch over it is handled, and a
  # per-file revert would leave the second file mutated for every run after it.
  #
  # Scoped to `app` rather than `.` deliberately, and the narrower scope was bought with a real
  # failure: `git checkout -- .` reverts THIS SCRIPT too whenever it is uncommitted, so a run
  # executes a half-reverted version of itself and the edit you just made vanishes mid-run.
  # Everything any mutation here touches lives under `app`.
  git checkout -- app

  if [ $status -ne 0 ] && printf '%s' "$out" | grep -q "recorded an issue"; then
    echo "RED   $name"
    printf '%s' "$out" | grep -m2 -oE 'Test "[^"]+" recorded an issue' | sed 's/^/        /'
    pass=$((pass + 1))
  else
    echo "GREEN $name  <- THE CLAUSE DID NOT NOTICE (exit=$status)"
    fail=$((fail + 1))
  fi
}

KIT=app/Sources/MCPRouterKit
UI=app/Sources/MCPRouterUI

mutate "A1  an empty queue produces a band of zero rows" \
  "$KIT/Inbox/InboxBand.swift" InboxBandTests \
  "s = s.replace('guard !waiting.isEmpty else { return nil }', '')"

mutate "A3/A4  rows are ordered newest first, as the pane orders them" \
  "$KIT/Inbox/InboxBand.swift" InboxBandTests \
  "s = s.replace('\$0.envelope.queuedAt < \$1.envelope.queuedAt', '\$0.envelope.queuedAt > \$1.envelope.queuedAt')"

mutate "A2  the cap is removed, so the popover becomes the board" \
  "$KIT/Inbox/InboxBand.swift" InboxBandTests \
  "s = s.replace('ordered.prefix(MenuBarPresentation.inboxBandLimit)', 'ordered[...]')"

mutate "A5  the header line is worded here instead of taken from the pane" \
  "$KIT/Inbox/InboxBand.swift" InboxBandTests \
  's = s.replace("headline: InboxCopy.subtitle(waiting: ordered.count, device: device),", "headline: String(ordered.count) + \" waiting\",")'

mutate "A6  the inbox zone falls below the unbounded attention band" \
  "$KIT/Shell/PopoverContent.swift" InboxBandTests \
  "s = s.replace('if band != nil { order.append(.attention) }', 'if band != nil { order.insert(.attention, at: 1) }')"

mutate "A9  the banner repeats the name the phone sent" \
  "$KIT/Inbox/InboxArrival.swift" InboxBandTests \
  "s = s.replace('title: first.title,', 'title: first.envelope.displayName,')"

mutate "A8  an unrecognised action identifier is treated as a review" \
  "$KIT/Inbox/InboxArrival.swift" InboxBandTests \
  "s = s.replace('return InboxNotificationAction(rawValue: identifier)', 'return InboxNotificationAction(rawValue: identifier) ?? .review')"

mutate "A11 the first snapshot of a session announces its whole queue" \
  "$KIT/Inbox/InboxArrival.swift" InboxBandTests \
  "s = s.replace('guard seeded else {', 'if false {')"

mutate "A13 the announced set is pruned, so an undone decline re-announces" \
  "$KIT/Inbox/InboxArrival.swift" InboxBandTests \
  "s = s.replace('announced.formUnion(new.map(\\\\.id))', 'announced = Set(items.map(\\\\.id))')"

mutate "status  the menu-bar dot ignores the queue" \
  "$KIT/Shell/MenuBarPresentation.swift" InboxBandTests \
  "s = s.replace('waiting > 0 || servers.contains(where: \\\\.needsAttention)', 'servers.contains(where: \\\\.needsAttention)')"

mutate "A7  the arrival path installs what arrived" \
  "$UI/Boards/InboxBoardModel+Arrivals.swift" InboxArrivalTests \
  "s = s.replace('await notifier.announce(announcement)', 'for arrival in arrived { if let acceptable = AcceptableInboxItem(arrival) { await accept(acceptable) } }\n                await notifier.announce(announcement)')"

mutate "A16 permission is asked for before anything is paired" \
  "$UI/Boards/InboxBoardModel+Arrivals.swift" InboxArrivalTests \
  "s = s.replace('guard snapshot.pairedDeviceName != nil, !hasAskedForAuthorization else { return }', 'guard !hasAskedForAuthorization else { return }')"

mutate "A17 nothing withdraws the banner of a handled item" \
  "$UI/Boards/InboxBoardModel+Arrivals.swift" InboxArrivalTests \
  "s = s.replace('let gone = announcedIDs.subtracting(waiting)', 'let gone = Set<String>()')"

mutate "A19 a route for an already-handled item reports nothing" \
  "$UI/Boards/InboxBoardModel.swift" InboxArrivalTests \
  "s = s.replace('routeReport = InboxCopy.alreadyHandled', 'routeReport = nil')"

# ---------------------------------------------------------------------------
# The second block, added on the relaunch.
#
# The fourteen above were aimed at fourteen of the thirty-two clauses. The rest were green and
# unproven, which is a series bounding an agreement rate rather than a measurement of what any term
# reads. These aim at the ones carrying the item's actual guarantees: the boundary, the announcement
# rules, and the claim that the new files are scanned by the floor gates at all.
# ---------------------------------------------------------------------------

TESTS=app/Tests

mutate "A18 the notifier is chosen without a bundle identifier, so the trap is reachable" \
  "$UI/Shell/ArrivalNotifierFactory.swift" ArrivalNotifierFactoryTests \
  "s = s.replace('bundleIdentifier != nil', 'true')"

mutate "A8b macOS is handed a button the delegate has no case for" \
  "$UI/Shell/ArrivalNotifierFactory.swift" ArrivalNotifierFactoryTests \
  "s = s.replace('identifier: InboxNotificationAction.decline.rawValue,', 'identifier: \"install\",')"

mutate "A8c the decline button drags the whole app forward" \
  "$UI/Shell/ArrivalNotifierFactory.swift" ArrivalNotifierFactoryTests \
  "s = s.replace('// through the same single-slot undo the pane uses.\n                        options: []', '// through the same single-slot undo the pane uses.\n                        options: [.foreground]')"

mutate "A14 several arrivals each get their own banner" \
  "$KIT/Inbox/InboxArrival.swift" InboxBandTests \
  "s = s.replace('guard arrivals.count == 1 else {', 'guard arrivals.count >= 1 else {')"

mutate "A15 nothing arriving is announced as an event" \
  "$KIT/Inbox/InboxArrival.swift" InboxBandTests \
  "s = s.replace('guard let first = arrivals.first else { return nil }', 'guard let first = arrivals.first else { return InboxAnnouncement(id: manyIdentifier, title: InboxCopy.Arrival.manyTitle(0), subtitle: InboxCopy.Arrival.subtitle(device: device ?? \"\"), body: InboxCopy.Arrival.manyBody, actions: [.review], itemIDs: []) }')"

mutate "A9b the banner body repeats a string the envelope carried" \
  "$KIT/Inbox/InboxArrival.swift" InboxBandTests \
  "s = s.replace('first.resolved.map { RegistryCapability.statement(for: \$0).headline }', 'first.resolved.map { _ in first.envelope.displayName }')"

mutate "Partial an unreadable entry says nothing rather than saying so" \
  "$KIT/Inbox/InboxArrival.swift" InboxBandTests \
  's = s.replace("?? InboxCopy.Arrival.partialBody", "?? \"\"")'

mutate "A12 every snapshot re-announces its whole queue" \
  "$KIT/Inbox/InboxArrival.swift" InboxBandTests \
  "s = s.replace('let new = items.filter { !announced.contains(\$0.id) }', 'let new = items')"

mutate "A10 the undo leaves the declined item declined" \
  "$UI/Boards/InboxBoardModel.swift" InboxArrivalTests \
  "s = s.replace('dispositioned[item.id] = nil\n            lastDisposition = nil', 'lastDisposition = nil')"

# Filtered to InboxBoardTests, not InboxArrivalTests, and the first aim was wrong rather than the
# clause being blind. `isUndoable` is asserted for an accept by M6's own
# "accepting is reported, offers no undo, and removes nothing" — which lives in InboxBoardTests, so
# a run filtered to I6's suite never executed it and reported GREEN. The band's report line is built
# straight from `isUndoable`, so that assertion is the load-bearing one for both surfaces.
mutate "report an accept offers an undo that cannot undo it" \
  "$UI/Boards/InboxBoardModel.swift" InboxBoardTests \
  "s = s.replace('if case .declined = lastDisposition { return true }', 'if case .declined = lastDisposition { return true }\n            if case .accepted = lastDisposition { return true }')"

mutate "failed-read a read that failed reaches the announce path anyway" \
  "$UI/Boards/InboxBoardModel.swift" InboxArrivalTests \
  "s = s.replace('} else {\n                    state = .failed(error)\n                }', '} else {\n                    state = .failed(error)\n                    await announceArrivals(in: InboxSnapshot(items: [], pairedDeviceName: \"Luke\\'s iPhone\"))\n                }')"

# The two below prove the *enrolment* rather than the code: that I6's files are actually read by the
# floor gates, and that the list naming them is itself checked against the directory. A file added to
# the tree but not to the list would pass every gate in this script while being scanned by none.

mutate "floor  the band applies an uppercasing transform and no gate sees it" \
  "$UI/Shell/MenuBarInboxBand.swift" ShellAppearanceTests \
  "s = s.replace('import SwiftUI', 'import SwiftUI\n// .textCase(.uppercase)')"

mutate "enrol  the band leaves the scanned file list" \
  "$TESTS/MCPRouterUITests/ShellTestSupport.swift" ShellIntegrationTests \
  's = s.replace("\"app/Sources/MCPRouterUI/Shell/MenuBarInboxBand.swift\"", "\"app/Sources/MCPRouterUI/Shell/ShellModel.swift\"")'

# The item's central claim, and the only mutation here that has to edit two files. Adding a third
# case to `InboxNotificationAction` is what "someone adds an Install button" actually looks like in
# this codebase, and it does not compile until the delegate's switch handles it — so the delegate is
# patched in the same breath. Without that second edit the run fails to BUILD, and a build failure
# scores GREEN here, which would have read as "the clause noticed nothing".
mutate "A8d the action enum gains an install case, and the delegate learns to obey it" \
  "$KIT/Inbox/InboxArrival.swift" InboxBandTests \
  "s = s.replace('    case decline\n', '    case decline\n    case install\n')
d = 'app/Sources/MCPRouterUI/Shell/InboxNotificationDelegate.swift'
t = open(d).read().replace('case .decline:', 'case .install: return\n            case .decline:')
open(d, 'w').write(t)"

echo
echo "i6 mutations: $pass red, $fail that should have been red and were not"
[ "$fail" -eq 0 ]
