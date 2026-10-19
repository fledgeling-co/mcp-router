import Foundation
import Testing
@testable import MCPRouterKit

/// The outcome the phone reports for each storage and acknowledgement failure, against the same
/// scripted Mac as `LivePairingServiceTests`. Split out to keep that suite under the body-length limit.
extension LivePairingServiceTests {
    @Test("a key that cannot be stored is reported as not saved, and nothing is sent")
    func keyWriteFailureOutcome() async throws {
        var rig = Rig()
        rig.failsOnKey = true
        rig.reply = try okReply()
        let outcome = try await rig.service().pair(using: .scanned(payload()))

        #expect(outcome == .notSaved(macName: Self.macName))
        #expect(await !(rig.trace.events).contains("connect"))
    }

    @Test("a record that cannot be stored is reported as not saved, and no ack is sent")
    func recordWriteFailureOutcome() async throws {
        var rig = Rig()
        rig.failsOnSave = true
        rig.reply = try okReply()
        let outcome = try await rig.service().pair(using: .scanned(payload()))

        #expect(outcome == .notSaved(macName: Self.macName))
        #expect(await !(rig.trace.events).contains("send ack"))
    }

    @Test("a record that cannot be stored puts back the Mac that was paired before")
    func recordWriteFailureRestoresEarlierPairing() async throws {
        var rig = Rig()
        let earlier = PairedMac(
            name: "Old Mac",
            pairedAt: Date(timeIntervalSince1970: 1_755_000_000),
            lastSeen: nil,
            host: "192.168.1.9",
            port: 7333,
            fingerprint: "SHA256:00000000"
        )
        try await rig.store.save(earlier)
        rig.failsOnSave = true
        rig.reply = try okReply()
        let outcome = try await rig.service().pair(using: .scanned(payload()))

        #expect(outcome == .notSaved(macName: Self.macName))
        #expect(await rig.store.load() == .loaded(earlier))
    }

    @Test("an ack that cannot be sent is unreachable, not a storage failure")
    func ackFailureOutcome() async throws {
        var rig = Rig()
        rig.failsOnAck = true
        rig.reply = try okReply()
        let outcome = try await rig.service().pair(using: .scanned(payload()))

        #expect(outcome == .unreachable(macName: Self.macName))
    }
}
