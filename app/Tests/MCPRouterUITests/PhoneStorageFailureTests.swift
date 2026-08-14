import Foundation
import MCPRouterKit
import Testing
@testable import MCPRouterUI

/// A store whose writes fail, so the failing half of `save`/`clear` has a way to be exercised.
///
/// `InMemoryPairingStore` cannot express it — both of its writes are infallible — which is exactly
/// why the two swallowed errors this suite covers survived the first pass: nothing in the test kit
/// could produce the failure, so no test could notice it was being discarded.
actor FailingWritePairingStore: PairingRecordStore {
    /// The thrown error **carries the secrets on purpose**.
    ///
    /// A payload-free error would make the A24 guard below vacuous: `\(error)` on an empty struct
    /// renders `"WriteRefused()"`, so the "no fingerprint reached a log line" assertions would hold
    /// even if production logged the entire record. This is the hostile conformance A24 has to
    /// survive — a `PairingRecordStore` this module does not own, throwing an error whose
    /// description is a credential.
    struct WriteRefused: Error, CustomStringConvertible {
        let mac: PairedMac
        var description: String {
            "refused for \(mac.name) fp=\(mac.fingerprint) host=\(mac.host) port=\(mac.port)"
        }
    }

    private var state: PairingRecordLoad

    init(_ initial: PairingRecordLoad = .missing) {
        state = initial
    }

    func load() async -> PairingRecordLoad {
        state
    }

    func save(_: PairedMac) async throws {
        throw WriteRefused(mac: FixturePairingService.specimenMac)
    }

    func clear() async throws {
        throw WriteRefused(mac: FixturePairingService.specimenMac)
    }
}

/// What happens when the Keychain refuses the write.
///
/// The bug these cover: `try? await store.save(mac)` let the success surface render over a write
/// that never happened, so the pairing was gone at the next launch with nothing having said so —
/// the failure mode `SWIFT_PRACTICES.md` §2 calls the worst available, reached here through §3's
/// "never swallow an error to keep a UI tidy".
@MainActor
@Suite("Pairing storage failures")
struct PairingStorageFailureTests {
    @Test("a refused Keychain write does not render as paired")
    func refusedSaveIsNotSuccess() async {
        let model = PairingFlowModel(
            pairing: FixturePairingService(.paired),
            camera: FixtureCameraAuthorization(.authorized),
            store: FailingWritePairingStore()
        )
        model.entry = PairingCodeEntry("K7QN4FMB")
        await model.submitTyped()

        guard case let .pairedNotStored(mac) = model.step else {
            Issue.record("a failed write rendered as \(model.step) rather than as its own state")
            return
        }
        // It really did pair at the Mac, so the Mac it names is the one that answered.
        #expect(mac == FixturePairingService.specimenMac)
    }

    @Test("a Keychain write that succeeds still reaches the paired state")
    func successfulSaveIsStillSuccess() async {
        let model = PairingFlowModel(
            pairing: FixturePairingService(.paired),
            camera: FixtureCameraAuthorization(.authorized),
            store: InMemoryPairingStore()
        )
        model.entry = PairingCodeEntry("K7QN4FMB")
        await model.submitTyped()

        guard case .paired = model.step else {
            Issue.record("a successful write rendered as \(model.step)")
            return
        }
    }

    /// The copy is neither the success copy nor a failure-pane copy, and that is the point: the
    /// pairing happened, and a code is one-use, so "pairing failed" would send the user to spend a
    /// second code for a problem that is on this phone.
    @Test("the not-stored copy says the pairing worked and that a new code is needed")
    func notStoredCopyIsHonest() {
        let entry = PairingCopy.entry(.pairedNotStored).resolved(macName: "Luke's MacBook Pro")
        #expect(entry.headline == "Paired, but this phone couldn't save it")
        #expect(entry.body.contains("Luke's MacBook Pro accepted the pairing"))
        #expect(entry.body.contains("won't survive closing the app"))
        #expect(entry.body.contains("Ask your Mac for a new code"))
        #expect(entry.actionLabel == "Pair again")
        #expect(
            entry.body != PairingCopy.entry(.pairedSuccess).body,
            "the not-stored state reuses the success sentence"
        )
    }

    @Test("a refused clear reports failure rather than reporting nothing")
    func refusedClearIsReported() async {
        let failing = FailingWritePairingStore(.loaded(FixturePairingService.specimenMac))
        #expect(await failing.unpair() == .failed)

        let working = InMemoryPairingStore(.loaded(FixturePairingService.specimenMac))
        #expect(await working.unpair() == .cleared)
    }

    @Test("the failed-unpair copy states the Mac is still paired and guesses no cause")
    func unpairFailedCopyIsHonest() {
        let entry = PairingCopy.entry(.unpairFailed).resolved(macName: "Luke's MacBook Pro")
        #expect(entry.headline == "Couldn't unpair Luke's MacBook Pro")
        #expect(entry.body.contains("still paired"))
        #expect(entry.body.contains("Nothing changed"))
        // No cause is named, because none was observed — the same rule the Error state follows.
        for guess in ["backup", "restor", "network", "locked"] {
            #expect(!entry.body.lowercased().contains(guess), "the copy guesses at '\(guess)'")
        }
    }

    /// The recovery from `pairedNotStored` is "pair again", and a denied camera must not turn that
    /// into a scanner that can never see anything (A16).
    @Test("pairing again after a refused write re-asks the camera")
    func restartRechecksTheCamera() async {
        let model = PairingFlowModel(
            pairing: FixturePairingService(.paired),
            camera: FixtureCameraAuthorization(.denied),
            store: FailingWritePairingStore()
        )
        model.entry = PairingCodeEntry("K7QN4FMB")
        await model.submitTyped()
        guard case .pairedNotStored = model.step else {
            Issue.record("expected pairedNotStored, got \(model.step)")
            return
        }

        await model.restart()
        #expect(
            model.step == .cameraBlocked(.denied),
            "restart dropped a denied-camera user onto a dead scanner: \(model.step)"
        )
        #expect(model.entry.characters.isEmpty, "restart kept the spent code")
    }

    /// A24 reaches the flow model's own log, not just the store's.
    ///
    /// The store throws an error whose *description is a credential*, so this is a real test of the
    /// bound in `PairingWriteFailure.logSafe` rather than of an error that had nothing to leak.
    @Test("a refused write logs its shape and never the record")
    func refusedWriteLogsNoSecret() async {
        let sink = CollectingLogSink()
        let model = PairingFlowModel(
            pairing: FixturePairingService(.paired),
            camera: FixtureCameraAuthorization(.authorized),
            store: FailingWritePairingStore(),
            log: ControlLog(sink: sink)
        )
        model.entry = PairingCodeEntry("K7QN4FMB")
        await model.submitTyped()

        // Awaited rather than slept through: a fixed delay fails under load for a reason that has
        // nothing to do with logging, and the `!isEmpty` assertion below is what it would fail on.
        var written = await sink.joined()
        for _ in 0 ..< 100 where written.isEmpty {
            try? await Task.sleep(for: .milliseconds(10))
            written = await sink.joined()
        }
        #expect(!written.isEmpty, "the sink recorded nothing, so this check proved nothing")

        let mac = FixturePairingService.specimenMac
        for secret in [mac.fingerprint, mac.host, "\(mac.port)", mac.name, "K7QN4FMB"] {
            #expect(!written.contains(secret), "'\(secret)' reached a log line: \(written)")
        }
    }
}
