#if os(macOS)
    import Foundation
    import MCPRouterKit

    /// The half of the Inbox board that reaches surfaces outside the window: the menu-bar band, the
    /// arrival notification, and the route back in from either.
    ///
    /// Split from `InboxBoardModel.swift` because that file is at its length budget, and split on
    /// this seam rather than an arbitrary one: everything here is about the board being observed
    /// from somewhere that is not the board.
    public extension InboxBoardModel {
        // MARK: - The menu-bar band

        /// What the popover's inbox area shows, or `nil` when it has nothing to say.
        ///
        /// `nil` for loading as well as for an empty queue, and the two are the same answer for a
        /// good reason: before an answer arrives there is no queue to describe, and a band drawn
        /// then would claim a state nobody has read. The pane says `Reading what is waiting…`
        /// because it has a whole surface to say it on; the popover has a line, and a line that says
        /// nothing every time is one the eye stops reading.
        func bandZone(now: Date = Date()) -> PopoverContent.InboxZone? {
            switch state {
            case .loading:
                return nil
            case let .failed(error):
                return .unreadable(unreadableMessage(error))
            case .loaded, .stale:
                // `.stale` keeps its rows: the last good reading is real, and a refresh that did not
                // complete is not evidence the queue emptied.
                return InboxBand.make(
                    waiting: rows,
                    device: pairedDeviceName,
                    report: bandReport(),
                    now: now
                )
                .map(PopoverContent.InboxZone.band)
            }
        }

        /// The report line under the band.
        ///
        /// A route that landed on an already-handled item outranks a disposition report, because it
        /// is the answer to the press the user just made — and the disposition it is reporting on is
        /// the thing that made the item disappear, so saying both would say the same event twice.
        private func bandReport() -> InboxBand.Report? {
            if let routeReport {
                return InboxBand.Report(sentence: routeReport, isUndoable: false)
            }
            guard let sentence = undoLabel() else { return nil }
            return InboxBand.Report(sentence: sentence, isUndoable: isUndoable)
        }

        /// The failure title, derived from the error rather than fixed.
        ///
        /// M6 shipped a version that rendered `routerOfflineTitle` for *every* read failure, so a
        /// queue file this Mac could not open was announced as "The router isn't running". Same
        /// discipline here.
        private func unreadableMessage(_ error: InboxServiceError) -> PopoverContent.Message {
            switch error {
            case let .unreadable(detail):
                PopoverContent.Message(
                    title: InboxCopy.unreadableTitle,
                    detail: InboxCopy.readFailure(detail: detail)
                )
            case .registryUnreadable:
                PopoverContent.Message(
                    title: InboxCopy.unreadableTitle,
                    detail: InboxCopy.registryFailureDetail
                )
            }
        }

        /// What the status item counts from this board. `0` while loading — no answer is not an
        /// answer of some.
        var waitingForStatusItem: Int { waitingCount ?? 0 }

        // MARK: - Arriving

        /// Announce whatever genuinely arrived in this snapshot, and reconcile delivered banners.
        ///
        /// Called from `load()` on every successful read, which is what makes both halves
        /// unforgettable: neither is a step a call site has to remember.
        ///
        /// **The withdrawal is derived rather than commanded**, and that is the design rather than a
        /// shortcut. A `withdraw()` call placed beside each disposition is a rule a later edit can
        /// drop silently — and the failure would be a banner offering `Decline` for an item that is
        /// already gone. Reconciling against the rows on every read cannot be forgotten, because it
        /// is not a step anybody performs. The cost is that a banner can linger for up to one poll
        /// interval after the window acted on its item, which is why the route for a missing id is a
        /// designed state rather than an error.
        internal func announceArrivals(in snapshot: InboxSnapshot) async {
            await requestAuthorizationIfNewlyPaired(snapshot)

            let arrived = takeArrivals(in: snapshot.items)
            if let announcement = InboxAnnouncement.make(
                arrivals: arrived,
                device: snapshot.pairedDeviceName
            ) {
                await notifier.announce(announcement)
            }

            let waiting = Set(rows.map(\.id))
            let gone = announcedIDs.subtracting(waiting)
            if !gone.isEmpty {
                // The multi-item banner goes with the first withdrawal, and not because it is tidy:
                // it says "3 items are waiting", and the moment one is handled that sentence is
                // false. A banner carrying a stale count is worse than no banner, because the count
                // is the only thing it says.
                await notifier.withdraw(
                    itemIDs: Array(gone).sorted() + [InboxAnnouncement.manyIdentifier]
                )
            }
        }

        /// Ask once, at the first snapshot that reports a paired device.
        ///
        /// Before a phone is paired nothing can ever arrive, so a launch-time prompt would be asking
        /// permission to send notifications the app has no way to generate — the kind of prompt that
        /// gets denied on reflex, after which the feature is absent and believed present. macOS
        /// prompts a user once and answers from its stored decision afterwards, so re-reaching this
        /// on every launch of an already-paired Mac costs nothing.
        private func requestAuthorizationIfNewlyPaired(_ snapshot: InboxSnapshot) async {
            guard snapshot.pairedDeviceName != nil, !hasAskedForAuthorization else { return }
            markAskedForAuthorization()
            notificationsAuthorized = await notifier.requestAuthorization()
        }
    }
#endif
