import Foundation
import MCPRouterKit
import Observation

/// Foreground delivery retries without claiming a receipt for an attempted send.
@MainActor
@Observable
public final class InboxDeliveryModel {
    public private(set) var error: String?
    @ObservationIgnored private let queue: any CapabilityQueueReader
    @ObservationIgnored private let submitter: any InboxSubmitting

    public init(queue: any CapabilityQueueReader, submitter: any InboxSubmitting) {
        self.queue = queue
        self.submitter = submitter
    }

    public func run() async {
        var previous: [String: Date] = [:]
        var retryAt = Date.distantPast
        while !Task.isCancelled {
            do {
                let pending = try await queue.all().filter { $0.receiptAt == nil }
                let current = Dictionary(uniqueKeysWithValues: pending.map { ($0.id, $0.queuedAt) })
                if !current.isEmpty, current != previous || Date() >= retryAt {
                    retryAt = Date().addingTimeInterval(60)
                    do {
                        try await submitter.submitPending()
                        error = nil
                    } catch is CancellationError {
                        return
                    } catch let failure as InboxSubmitError {
                        switch failure {
                        case .needsPairing:
                            error = """
                            Pair this phone again in Settings before sending. \
                            Your picks are still queued.
                            """
                        case .refused:
                            error = """
                            Your Mac refused this phone's delivery. \
                            Pair again in Settings; your picks are still queued.
                            """
                        case .malformed:
                            error = """
                            Your Mac sent a receipt this phone couldn't read. \
                            Your picks are still queued; check both app versions.
                            """
                        }
                    } catch {
                        self.error = """
                        Couldn't send your picks. \
                        They remain queued and will retry while the app is open.
                        """
                    }
                }
                previous = current
            } catch {
                self.error = "Couldn't read the saved queue. Nothing was sent or removed."
            }
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
        }
    }
}
