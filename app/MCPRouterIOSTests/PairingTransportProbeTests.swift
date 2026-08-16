import Darwin
import Foundation
import MCPRouterKit
import XCTest

/// The phone half of I5's transport experiment, run on a real iPhone simulator.
///
/// ## What is being measured, and why it is measured from here
///
/// I5 asks whether the phone-to-Mac pairing round trip happens. The Mac half of the experiment
/// launches the Mac app and counts its listening sockets. This half does the other side: it takes
/// the phone through a complete pairing attempt aimed at an endpoint that **is** listening, and
/// lets that endpoint testify to what arrived.
///
/// This runs on the simulator rather than on the macOS test host on purpose. The host suites can
/// prove that `FixturePairingService` returns what it returns; they cannot establish that the
/// shipping phone app, in its own process, sends nothing — because on the host there is no separate
/// process and no separate network stack to observe. The claim is about the running product, so it
/// is measured where the running product is.
///
/// ## The calibration, which is what makes the result mean anything
///
/// `probesReachTheTap` runs first and is the reason the rest is admissible. A pairing call that
/// sends nothing and a test that could never have reached the tap produce **identical** evidence:
/// an empty log. So this process opens its own connection to the tap and sends a token, and the
/// harness asserts that token arrived. Only then does the absence of a *third* connection say
/// something about the transport rather than about the simulator's networking, the port, or a typo.
///
/// This is the discipline the fleet paid for elsewhere: a series of agreeing observations bounds an
/// agreement rate and says nothing about what the term measures. The calibration is what pins what
/// the term measures.
///
/// ## What this deliberately does not do
///
/// It does not implement a transport, and it does not change what the phone is allowed to do. The
/// socket opened here belongs to the probe, never to the product: it proves reachability and is
/// then closed. Nothing in this file is reachable from the app.
final class PairingTransportProbeTests: XCTestCase {
    /// The tap's port, handed in by the harness. Absent means "not running under the I5 lane", and
    /// every test here then skips rather than inventing a port — a probe that silently connects
    /// somewhere else is worse than a probe that does not run.
    static var tapPort: UInt16? {
        guard let raw = ProcessInfo.processInfo.environment["I5_TAP_PORT"],
              let port = UInt16(raw), port > 0
        else { return nil }
        return port
    }

    /// Open a TCP connection to the tap and send one line. Returns whether the write succeeded.
    ///
    /// Deliberately raw POSIX rather than `URLSession` or `Network.framework`: this must be the
    /// simplest possible thing that can reach a port, so that a failure here is a fact about
    /// reachability and not about a framework's own policy — `URLSession` would apply ATS, caching
    /// and proxy resolution to a measurement that is supposed to be about a socket.
    @discardableResult
    static func send(_ message: String, toPort port: UInt16) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")

        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { raw in
                Darwin.connect(fd, raw, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connected == 0 else { return false }

        let bytes = Array(message.utf8)
        let written = bytes.withUnsafeBytes { buffer in
            Darwin.send(fd, buffer.baseAddress, buffer.count, 0)
        }
        // Give the tap a moment to read before the socket closes under it.
        Thread.sleep(forTimeInterval: 0.2)
        return written == bytes.count
    }

    // MARK: - 1. Calibration

    /// The probe can reach the tap from inside the simulator.
    ///
    /// If this fails the whole experiment is BLOCKED rather than failed: nothing has been learned
    /// about the transport, because the instrument could not be shown to work from here.
    func testProbesReachTheTap() throws {
        guard let port = Self.tapPort else {
            throw XCTSkip("no I5_TAP_PORT — this suite only runs under scripts/acceptance/i5-pairing-transport.sh")
        }
        XCTAssertTrue(
            Self.send("PHONE-REACHABILITY\n", toPort: port),
            """
            the phone process could not reach the wire tap on 127.0.0.1:\(port).
            Nothing after this measures the product: an unreachable tap and a phone that sends
            nothing produce the same empty log.
            """
        )
    }

    // MARK: - 2. The pairing attempt itself

    /// Drive a complete pairing attempt whose payload points at the live tap, and record what the
    /// phone concludes.
    ///
    /// The payload is built by the **Mac's own encoder** (`MacPairing.issue` then
    /// `MacPairing.payload`), so this is the artifact a phone would really be holding after
    /// scanning a QR — not a hand-assembled struct that happens to typecheck. Its `host` and `port`
    /// are the tap, which is listening and provably reachable from this process.
    ///
    /// The assertion is on the **outcome the phone reports**. That the tap saw nothing is asserted
    /// by the harness, which owns the log; splitting it that way keeps this process from being both
    /// the thing under test and the witness to it.
    func testPairingAttemptAgainstALiveEndpoint() async throws {
        guard let port = Self.tapPort else {
            throw XCTSkip("no I5_TAP_PORT — this suite only runs under scripts/acceptance/i5-pairing-transport.sh")
        }
        let endpoint = try XCTUnwrap(
            PairingEndpoint(host: "127.0.0.1", port: Int(port), fingerprint: "SHA256:i5-probe"),
            "the probe endpoint is malformed, so nothing was attempted"
        )
        let issued = MacPairing.issue(at: Date())
        let payload = MacPairing.payload(for: issued, endpoint: endpoint, macName: "I5 Wire Tap")

        // The service the shipping app composes. `testShippingAppComposesThisExactService` below is
        // what stops that being an assumption.
        let service = FixturePairingService()
        let outcome = await service.pair(using: .scanned(payload))

        // Recorded rather than merely asserted: the harness prints this line beside the tap's log,
        // and the pair of them is the finding.
        print("I5-PROBE-OUTCOME: \(outcome)")

        XCTAssertTrue(
            outcome.isSuccess,
            """
            expected the phone to report success against a fixture, and it did not (\(outcome)).
            That would change I5's finding, so it is asserted rather than assumed.
            """
        )
    }

    // MARK: - 3. What the shipping app actually composes

    /// The shipping iOS app passes `FixturePairingService` — unconditionally, with no build
    /// configuration or environment guard.
    ///
    /// Read off the app's own source with comments and string literals stripped, the method
    /// `PhoneSourceGuardTests` established in this codebase, so the guard cannot be satisfied by
    /// the very prose that documents it.
    ///
    /// This is what makes the behavioural test above a statement about the product rather than
    /// about a type that happens to exist. It goes red the day a live client is wired in — which is
    /// the day I5's finding stops being true, and exactly when someone should be made to look.
    func testShippingAppComposesTheFixtureService() throws {
        let source = try Self.strippedAppSource()
        XCTAssertTrue(
            source.contains("pairing: FixturePairingService()"),
            """
            MCPRouterIOSApp no longer composes FixturePairingService. If a real client has been
            wired in, I5's finding is stale and the transport experiment must be re-run.
            """
        )
        // No conditional compilation around the pairing seam: the fixture is not Debug-only the way
        // the Mac's `ShellPairingFactory` is. That asymmetry is I5's second finding, and it is
        // pinned here so a later change to either side is visible.
        XCTAssertFalse(
            source.contains("#if DEBUG"),
            """
            MCPRouterIOSApp has grown a build-configuration branch. I5 recorded that it had none —
            that the fixture pairing service ships in Release unguarded — so this needs re-reading.
            """
        )
    }

    /// The `@main` app's source, comments and string literals removed.
    static func strippedAppSource() throws -> String {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        var found: URL?
        for _ in 0 ..< 8 {
            let candidate = directory
                .appendingPathComponent("MCPRouterIOS")
                .appendingPathComponent("MCPRouterIOSApp.swift")
            if FileManager.default.fileExists(atPath: candidate.path) {
                found = candidate
                break
            }
            directory = directory.deletingLastPathComponent()
        }
        let url = try XCTUnwrap(found, "could not locate MCPRouterIOSApp.swift to read")
        let raw = try String(contentsOf: url, encoding: .utf8)

        var out = ""
        for line in raw.components(separatedBy: .newlines) {
            let withoutComment = line.components(separatedBy: "//").first ?? ""
            var inString = false
            var kept = ""
            for character in withoutComment {
                if character == "\"" {
                    inString.toggle()
                    continue
                }
                if !inString { kept.append(character) }
            }
            out += kept + "\n"
        }
        return out
    }
}
