#!/bin/bash
# I6 mutation gate.
#
# A series of agreeing observations bounds the AGREEMENT rate; it cannot say what a term MEASURES.
# Each mutation below breaks one behaviour and requires the named clause to go red. A clause that
# stays green under its own mutation is a clause that measures nothing, and this script reports that
# as a failure rather than as a pass.
#
# Every mutation is applied, tested, then reverted with `git checkout` on the one file it touched,
# so an interrupted run leaves the tree recoverable.
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
  git checkout -- "$file"

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

echo
echo "i6 mutations: $pass red, $fail that should have been red and were not"
[ "$fail" -eq 0 ]
