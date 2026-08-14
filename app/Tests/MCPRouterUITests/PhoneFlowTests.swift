import Foundation
import MCPRouterKit
import SwiftUI
import Testing
@testable import MCPRouterUI

/// The pairing flow's state machine, and the components whose behaviour is the feature's point.
///
/// These run on the macOS host and are deliberately about **logic and wiring**, not geometry. What
/// a 44pt target measures on an iPhone, what the safe area does, and what the generated Info.plist
/// contains are all asserted in `MCPRouterIOSTests`, because asserting them here would be a green
/// light for something nobody measured.
@MainActor
@Suite("Phone flow")
struct PhoneFlowTests {
    static let code = PairingCode("K7QN4FMB")!

    static func model(
        _ scenario: FixturePairingService.Scenario = .paired,
        camera: CameraAuthorization = .authorized
    ) -> PairingFlowModel {
        PairingFlowModel(
            pairing: FixturePairingService(scenario),
            camera: FixtureCameraAuthorization(camera),
            store: InMemoryPairingStore()
        )
    }

    // MARK: The opening step follows the camera, not a default

    @Test("an authorized camera opens on the scanner")
    func opensOnScanner() async {
        let model = Self.model(camera: .authorized)
        await model.start()
        #expect(model.step == .scan)
    }

    @Test("each blocked camera state opens on its own surface")
    func blockedCameraStates() async {
        for state in [CameraAuthorization.notDetermined, .denied, .restricted] {
            let model = Self.model(camera: state)
            await model.start()
            #expect(model.step == .cameraBlocked(state), "\(state) did not reach its own step")
        }
    }

    @Test("granting the camera moves to the scanner; a refusal moves to the denied surface")
    func requestingCamera() async {
        let granting = PairingFlowModel(
            pairing: FixturePairingService(),
            camera: FixtureCameraAuthorization(.notDetermined, grantsOnRequest: true),
            store: InMemoryPairingStore()
        )
        await granting.requestCamera()
        #expect(granting.step == .scan)

        let refusing = PairingFlowModel(
            pairing: FixturePairingService(),
            camera: FixtureCameraAuthorization(.notDetermined, grantsOnRequest: false),
            store: InMemoryPairingStore()
        )
        await refusing.requestCamera()
        #expect(refusing.step == .cameraBlocked(.denied))
    }

    /// Every camera state offers the typed path, so a refusal is never a dead end.
    @Test("the typed path is reachable from every blocked camera state")
    func typedPathAlwaysReachable() async {
        for state in [CameraAuthorization.notDetermined, .denied, .restricted] {
            let model = Self.model(camera: state)
            await model.start()
            model.typeInstead()
            #expect(model.step == .typing, "no typed path from \(state)")
        }
    }

    // MARK: The decode's three failures stay apart all the way to the surface

    @Test("a foreign QR reaches the not-a-pairing-code surface")
    func foreignQR() async {
        let model = Self.model()
        await model.scanned("https://example.com")
        #expect(model.step == .failed(.notAPairingCode))
    }

    @Test("an unknown version reaches the version-mismatch surface, not the malformed one")
    func versionMismatch() async {
        let model = Self.model()
        await model.scanned(#"{"t":"mcp-router-pair","v":99,"code":"K7QN-4FMB","mac":"m","exp":"2099-01-01T00:00:00Z","host":"h","port":1,"fp":"f"}"#)
        #expect(model.step == .failed(.versionMismatch(macName: nil)))
    }

    @Test("a broken body reaches the malformed surface, not the foreign one")
    func malformedBody() async {
        let model = Self.model()
        await model.scanned(#"{"t":"mcp-router-pair","v":1,"code":"K7QN-4FMB","mac":"m"}"#)
        #expect(model.step == .failed(.malformedPayload))
    }

    // MARK: Which failures land beside the field, and which get a pane

    /// The two that a user can fix by typing again belong next to the field. The rest cannot be
    /// fixed that way, so putting them there would invite exactly the retry that cannot work.
    @Test("not-recognised and expired return to the field with the reason beside it")
    func inlineFailures() async {
        for scenario in [FixturePairingService.Scenario.notRecognised, .expired] {
            let model = Self.model(scenario)
            model.entry = PairingCodeEntry("K7QN4FMB")
            await model.submitTyped()
            #expect(model.step == .typing, "\(scenario) left the field")
            #expect(model.inlineFailure != nil, "\(scenario) produced no inline reason")
        }
    }

    @Test("the unfixable-by-retyping failures each get their own pane")
    func paneFailures() async {
        for scenario in [FixturePairingService.Scenario.alreadyUsed, .versionMismatch, .unreachable, .refused] {
            let model = Self.model(scenario)
            model.entry = PairingCodeEntry("K7QN4FMB")
            await model.submitTyped()
            guard case .failed = model.step else {
                Issue.record("\(scenario) did not reach a failure pane; it reached \(model.step)")
                continue
            }
        }
    }

    // MARK: The commit

    @Test("an incomplete code cannot be submitted at all")
    func incompleteCannotSubmit() async {
        let model = Self.model()
        model.entry = PairingCodeEntry("K7QN")
        await model.submitTyped()
        #expect(model.step == .scan, "an incomplete code moved the flow")
    }

    @Test("a successful pairing stores the record and lands on the paired screen")
    func successStores() async {
        let store = InMemoryPairingStore()
        let model = PairingFlowModel(
            pairing: FixturePairingService(.paired),
            camera: FixtureCameraAuthorization(),
            store: store
        )
        model.entry = PairingCodeEntry("K7QN4FMB")
        await model.submitTyped()

        guard case .paired = model.step else {
            Issue.record("expected the paired step, got \(model.step)")
            return
        }
        guard case .loaded = await store.load() else {
            Issue.record("pairing succeeded without storing the record")
            return
        }
    }

    @Test("retrying clears both the failure and the half-typed code")
    func retryClears() async {
        let model = Self.model(.alreadyUsed)
        model.entry = PairingCodeEntry("K7QN4FMB")
        await model.submitTyped()
        model.retry()
        #expect(model.step == .scan)
        #expect(model.entry.characters.isEmpty)
        #expect(model.inlineFailure == nil)
    }
}

/// The connection vocabulary and the commit that reads it.
@MainActor
@Suite("Connection state")
struct ConnectionStateTests {
    @Test("only reachable can send")
    func onlyReachableSends() {
        for state in ConnectionState.allCases {
            #expect(state.canSend == (state == .reachable))
        }
    }

    @Test("each state has its own sentence, and the unreachable one says what happens to the work")
    func vocabulary() {
        let reachable = ConnectionBanner(.reachable, macName: "Luke's MacBook Pro").message
        let unreachable = ConnectionBanner(.notReachable, macName: "Luke's MacBook Pro").message
        let never = ConnectionBanner(.neverPaired).message

        #expect(reachable == "Luke's MacBook Pro — items you send arrive now.")
        #expect(unreachable.contains("Can't reach Luke's MacBook Pro"))
        #expect(unreachable.contains("waits here until it's back"), "the copy does not say what happens to queued work")
        #expect(never == "No Mac paired. Pair one to send anything.")
        #expect(Set([reachable, unreachable, never]).count == 3, "two states share a sentence")
    }

    /// The brief's requirement: the refusal happens before the tap, not after it.
    @Test("an unreachable Mac disables the commit and names the reason above it")
    func commitBlockedBeforeTheTap() {
        let blocked = SendCommitBar(state: .notReachable, macName: "Luke's MacBook Pro", itemCount: 2)
        #expect(blocked.blockedReason != nil)
        #expect(blocked.blockedReason?.contains("Can't reach Luke's MacBook Pro") == true)
        #expect(blocked.blockedReason?.contains("2 items are waiting") == true)

        let ready = SendCommitBar(state: .reachable, macName: "Luke's MacBook Pro", itemCount: 2)
        #expect(ready.blockedReason == nil)
    }

    @Test("the commit names what it will do, verb first")
    func commitLabel() {
        #expect(SendCommitBar(state: .reachable, macName: "m", itemCount: 2).commitLabel == "Send 2 to Mac")
        #expect(SendCommitBar(state: .reachable, macName: "m", itemCount: 1).commitLabel == "Send 1 to Mac")
    }

    @Test("one waiting item reads as one item, not as '1 items'")
    func singular() {
        let one = SendCommitBar(state: .notReachable, macName: "m", itemCount: 1)
        #expect(one.blockedReason?.contains("One item is waiting") == true)
    }
}

/// The honesty rule, at the surface that would render the number.
@MainActor
@Suite("Verifying countdown")
struct VerifyingCountdownTests {
    static func payload(expiring seconds: TimeInterval) -> PairingPayload {
        PairingPayload(
            version: 1,
            code: PairingCode("K7QN4FMB")!,
            macName: "Luke's MacBook Pro",
            expiresAt: Date(timeIntervalSince1970: 1_786_708_800 + seconds),
            host: "h", port: 1, fingerprint: "f"
        )
    }

    static let now = Date(timeIntervalSince1970: 1_786_708_800)

    /// The observed number, shown because it was observed.
    @Test("a scanned attempt shows the countdown the payload carried")
    func scannedShowsCountdown() {
        let view = VerifyingView(attempt: .scanned(Self.payload(expiring: 292)), now: Self.now)
        #expect(view.countdown == "code expires in 4:52")
    }

    /// The whole point. A typed code has told the phone nothing, so there is nothing to show.
    @Test("a typed attempt shows no number at all")
    func typedShowsNothing() {
        let view = VerifyingView(attempt: .typed(PairingCode("K7QN4FMB")!), now: Self.now)
        #expect(view.countdown == nil)
    }

    @Test("an already-dead code shows no countdown rather than a negative one")
    func deadCodeShowsNothing() {
        let view = VerifyingView(attempt: .scanned(Self.payload(expiring: -30)), now: Self.now)
        #expect(view.countdown == nil)
    }

    @Test("the countdown is zero-padded so it does not jitter as it counts down")
    func padding() {
        #expect(VerifyingView(attempt: .scanned(Self.payload(expiring: 65)), now: Self.now).countdown == "code expires in 1:05")
    }
}

/// The nine states exist, are distinct, and each speaks the right connection vocabulary.
@MainActor
@Suite("Paired-Mac surface states")
struct PairedMacSurfaceStateTests {
    static let mac = FixturePairingService.specimenMac
    static let partialMac = PairedMac(
        name: mac.name, pairedAt: mac.pairedAt, lastSeen: nil,
        host: mac.host, port: mac.port, fingerprint: mac.fingerprint
    )

    static let allStates: [PairedMacSurfaceState] = [
        .reachable(mac), .neverPaired, .loading, .partial(partialMac),
        .unreadable, .justPaired(mac), .macUnreachable(mac)
    ]

    @Test("every state renders without trapping and reports a connection state")
    func everyStateRenders() {
        for state in Self.allStates {
            let view = PairedMacSettingsView(state: state)
            _ = view.body
            _ = state.connection
        }
    }

    @Test("only the unreachable state says it cannot be reached")
    func connectionMapping() {
        #expect(PairedMacSurfaceState.reachable(Self.mac).connection == .reachable)
        #expect(PairedMacSurfaceState.partial(Self.partialMac).connection == .reachable)
        #expect(PairedMacSurfaceState.justPaired(Self.mac).connection == .reachable)
        #expect(PairedMacSurfaceState.macUnreachable(Self.mac).connection == .notReachable)
        #expect(PairedMacSurfaceState.neverPaired.connection == .neverPaired)
        #expect(PairedMacSurfaceState.unreadable.connection == .neverPaired)
    }

    /// The Partial state is the one that must admit a gap rather than fill it.
    @Test("the partial state carries a Mac with no last-seen, and says unknown")
    func partialAdmitsTheGap() {
        #expect(PairedMacSurfaceState.partial(Self.partialMac).mac?.lastSeen == nil)
        let subtitle = PairingSubtitle.text(for: Self.partialMac)
        #expect(subtitle.hasSuffix("last seen unknown"))
    }

    @Test("the states that have no Mac report none, rather than a placeholder one")
    func statesWithoutAMac() {
        #expect(PairedMacSurfaceState.neverPaired.mac == nil)
        #expect(PairedMacSurfaceState.loading.mac == nil)
        #expect(PairedMacSurfaceState.unreadable.mac == nil)
    }
}

/// The tab shell.
@MainActor
@Suite("Phone shell")
struct PhoneShellTests {
    @Test("five tabs, in order, with Settings last")
    func tabOrder() {
        #expect(PhoneShell<EmptyView>.Tab.allCases.map(\.rawValue) == ["discover", "triage", "queue", "library", "settings"])
        #expect(PhoneShell<EmptyView>.Tab.allCases.last == .settings)
    }

    @Test("every tab has a sentence-case title and a real icon from the shared set")
    func tabsAreLabelled() {
        for tab in PhoneShell<EmptyView>.Tab.allCases {
            #expect(!tab.title.isEmpty)
            #expect(tab.title.first?.isUppercase == true)
            #expect(tab.title.dropFirst().allSatisfy { !$0.isUppercase }, "\(tab.title) is not sentence case")
            #expect(Icon.allCases.contains(tab.icon), "\(tab) uses an icon outside the shared set")
        }
    }

    /// The four tabs whose content another item owns each have their own awaiting copy; Settings has
    /// content of its own and therefore none.
    @Test("exactly the four non-Settings tabs carry awaiting copy")
    func awaitingCoverage() {
        for tab in PhoneShell<EmptyView>.Tab.allCases {
            if tab == .settings {
                #expect(tab.awaitingKey == nil)
            } else {
                #expect(tab.awaitingKey != nil, "\(tab) has no awaiting copy")
            }
        }
    }

    @Test("the shell builds with fixtures and no camera")
    func shellBuilds() {
        _ = PhoneShell().body
    }
}
