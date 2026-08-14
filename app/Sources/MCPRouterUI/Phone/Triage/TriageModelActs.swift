import Foundation
import MCPRouterKit

/// Triage's three acts: queue a batch, dismiss a batch, and reverse either one.
///
/// Split from `TriageModel` on a real seam — state and loading there, the acts here — rather than
/// letting one file grow toward the 400-line cap and then be split under a red gate.
@MainActor
public extension TriageModel {
    // MARK: - Queue

    /// Queue every selected entry, then reload.
    ///
    /// **Per item, and the outcome is counted rather than assumed.** `enqueue` is idempotent on
    /// `id`, so a batch containing something already queued produces no second row and does not
    /// double the count. An item whose write is refused stays in Undecided and is named — the batch
    /// never reports success for something it did not save (A14).
    func queueSelected() async {
        let ids = selected
        guard !ids.isEmpty else { return }

        let entries = buckets.undecided.filter { ids.contains($0.id) }
        var saved: [String] = []
        var refused: [String] = []

        for entry in entries {
            do {
                try await queue.enqueue(QueuedCapability(entry: entry))
                saved.append(entry.id)
            } catch {
                refused.append(entry.id)
            }
        }

        writeFailure = refused.isEmpty
            ? nil
            : TriageWriteFailure(saved: saved.count, refused: refused)
        // Undo covers what actually landed. Offering to undo a write that was refused would undo
        // nothing and say it had.
        undo = saved.isEmpty ? nil : .queued(saved)
        selected.removeAll()
        await load()
    }

    // MARK: - Dismiss

    /// Turn down every selected entry, then reload.
    func dismissSelected() async {
        let ids = selected
        guard !ids.isEmpty else { return }

        let entries = buckets.undecided.filter { ids.contains($0.id) }
        var saved: [String] = []
        var refused: [String] = []

        for entry in entries {
            do {
                try await dismissals.dismiss(DismissedCapability(entry: entry))
                saved.append(entry.id)
            } catch {
                refused.append(entry.id)
            }
        }

        writeFailure = refused.isEmpty
            ? nil
            : TriageWriteFailure(saved: saved.count, refused: refused)
        undo = saved.isEmpty ? nil : .dismissed(saved)
        selected.removeAll()
        await load()
    }

    /// Put one dismissed entry back in Undecided. The per-row act in the Not-for-me bucket.
    func restore(_ id: String) async {
        // **Counted, not swallowed.** This is the only path out of the Dismissed bucket, so a
        // refused restore that reported nothing would leave the row where it was with no
        // explanation — and the user's last act was the one that failed.
        do {
            try await dismissals.restore(id)
            writeFailure = nil
        } catch {
            writeFailure = TriageWriteFailure(saved: 0, refused: [id])
        }
        undo = nil
        await load()
    }

    // MARK: - Undo

    /// Reverse the last batch.
    ///
    /// Reverses the *whole* batch, because that is the act the user took — undoing three of five
    /// would leave a state nobody chose.
    func undoLast() async {
        guard let undo else { return }

        // Refusals are counted here the way `queueSelected` counts them. The earlier shape used
        // `try?` and then cleared `writeFailure`, so a wholly refused undo returned the surface to
        // a clean list with nothing said — the app reporting success for the user's last act
        // precisely when that act failed.
        var refused: [String] = []
        var saved = 0

        switch undo {
        case let .queued(ids):
            for id in ids {
                do {
                    try await queue.remove(id)
                    saved += 1
                } catch {
                    refused.append(id)
                }
            }
        case let .dismissed(ids):
            for id in ids {
                do {
                    try await dismissals.restore(id)
                    saved += 1
                } catch {
                    refused.append(id)
                }
            }
        }

        self.undo = nil
        writeFailure = refused.isEmpty ? nil : TriageWriteFailure(saved: saved, refused: refused)
        await load()
    }

    /// Clear the undo offer without acting on it — what a bucket change or a fresh load does.
    func clearUndo() {
        undo = nil
        writeFailure = nil
    }
}
