#if os(macOS)
    import Foundation
    import MCPRouterKit

    /// The merge rule: how a fresh `GET /usage` response is reconciled with what the live feed has
    /// already delivered.
    ///
    /// It sits on its own because it is the densest reasoning on this board and the piece most often
    /// got wrong — the comments below are three separate post-mortems, and every one of them had the
    /// same symptom, a call at row 0 of a newest-first log that was not the newest call held. Beside
    /// `load()` this reads as an implementation detail of a network request; on its own it reads as
    /// what it is, a rule about provenance that a network request happens to invoke.
    ///
    /// Deliberately not a `public extension`. Nothing outside this module merges, and the only
    /// widening the split cost is `merge` and `streamArrivals` going from private to internal — the
    /// six `public private(set)` properties keep their write barrier, which is the only
    /// compiler-enforced one they have in a single-module target.
    extension ActivityModel {
        /// Compares two router timestamps, parsed where they parse.
        ///
        /// The string fallback is not a shrug: both values come from the same endpoint family in the
        /// same fixed format, so lexicographic order is the correct order for them — and a parse
        /// that fails on a format this version does not know should not silently answer "not newer",
        /// which would quietly drop a live record.
        static func isNewer(_ lhs: String, than rhs: String) -> Bool {
            if let left = lhs.asControlAPIDate, let right = rhs.asControlAPIDate {
                return left > right
            }
            return lhs > rhs
        }

        /// Merges a fresh response into whatever is already held, newest first.
        ///
        /// **Order matters, and getting it backwards silently discards the live half.** The
        /// de-duplicating initialiser keeps the *first* `capacity` records it is given, so the list
        /// handed to it must be newest-first. An earlier version passed `response.records +
        /// held.records`: once the router returned a full ring — 500, its `RING_SIZE` — every record
        /// the stream had delivered fell off the end of the concatenation and was truncated away.
        /// A reconnect on a busy router would have thrown away exactly the half it was reloading to
        /// preserve.
        ///
        /// **The fix for that opened its mirror image, and this is where it is closed.** Prepending
        /// *everything* held that the response did not carry rested on "held and not returned means
        /// it arrived after the fetch began". That holds only at the head of the window. `GET /usage`
        /// returns a **contiguous** newest-first slice of the router's ring — `recent()` is
        /// `ring.slice(-limit).reverse()`, and this board passes no `server` or `cwd`, so nothing
        /// punches holes in it — which splits the held-but-not-returned records in two: those *ahead*
        /// of the first shared record arrived on the stream after the snapshot, and those *behind* it
        /// rolled out of the ring while the board was holding them. Prepending the second group put
        /// the oldest calls the board had at the top of a newest-first log, and pushed the genuinely
        /// newest ones off the end. That is what a reader met by pressing Reconnect on a busy router.
        ///
        /// So the boundary is the first held record the response also carries. No timestamp is
        /// compared: the wire promises no total order across the two sources, and the ring's
        /// contiguity is the fact actually known.
        /// Internal rather than private because `load()` — which stays beside the stored state it
        /// writes — is the one caller, and `private` is file-scoped. Nothing else merges.
        func merge(_ response: UsageResponse) -> ActivityRecords {
            guard let held = records, !held.isEmpty else {
                streamArrivals = []
                return ActivityRecords(response)
            }
            let returned = Set(response.records.map(\.id))
            // **Provenance, not position.** Which held records are newer than this response is a
            // fact about where they came from, and the board knows it: `streamArrivals` is exactly
            // the set delivered by the feed since the last response landed. Everything else held
            // came from an older response and is superseded by this one.
            //
            // The positional reading this replaces — "everything before the first shared record" —
            // is right whenever the two windows overlap and silently wrong when they do not. With no
            // shared record it cannot tell a window that rolled out of the ring (held records are
            // OLDER, and must go) from one seeded purely by the stream before the first backfill
            // returned (held records are NEWER, and must stay). Those are opposite answers, and the
            // second is ordinary: `start()` runs both halves concurrently, so on a busy router a
            // record routinely arrives before `GET /usage` comes back. Discarding it there is the
            // exact defect B23 exists to prevent.
            // **Provenance says which records *could* be newer; the timestamp says which are.**
            //
            // Provenance alone was not enough, and the gap is a real defect rather than a nicety.
            // "Held, delivered by the feed, and absent from this response" covers two opposite
            // situations: a record that arrived *after* the snapshot was taken (newer — must stay)
            // and one that rolled *out of the router's ring* while the board held it (older — must
            // go). Promoting the second put a stale call at row 0 of a newest-first log, where
            // `newestTimestamp` reads it and the feed banner announces it as the newest call held.
            //
            // The earlier comment here refused to compare timestamps, on the grounds that "the wire
            // promises no total order across the two sources". That is too cautious about this
            // particular pair: `GET /usage` and `GET /usage/stream` report the *same* `CallRecord`s,
            // stamped by the one router process, so `ts` is comparable between them. What is not
            // comparable is a timestamp against this machine's clock, which nothing here does.
            //
            // A response carrying no records leaves nothing to be newer than, so everything the feed
            // delivered stands.
            let newestReturned = response.records.first?.ts
            let arrivedSince = held.records.filter { record in
                guard streamArrivals.contains(record.id), !returned.contains(record.id) else {
                    return false
                }
                guard let newestReturned else { return true }
                return Self.isNewer(record.ts, than: newestReturned)
            }
            let merged = ActivityRecords(
                records: arrivedSince + response.records,
                since: response.since
            )
            // **Emptied, not pruned, and the difference is a defect.** This read
            // `subtracting(returned).intersection(kept)`, which keeps exactly the ids `arrivedSince`
            // just promoted — they are in `kept` and, by construction, not in `returned`. So the set
            // came to mean "delivered by the feed and never seen in *any* response" rather than
            // "since the last response landed", and a record that had rolled out of the router's
            // ring was promoted to row 0 of a newest-first log, then promoted again by every
            // subsequent reload, for the life of the board. `newestTimestamp` reads index 0, so the
            // feed banner went on to name that stale moment as the newest call the board holds.
            //
            // A record's provenance relative to *this* response says nothing about its relation to
            // the *next* one — which is the same blind spot that retired the positional reading, one
            // merge later. After a response lands, everything held is either in it or is older than
            // it, so nothing is still waiting to be explained.
            streamArrivals = []
            return merged
        }
    }
#endif
