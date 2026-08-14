import MCPRouterKit
import SwiftUI

/// The pairing flow's state, owned in one place.
///
/// `@MainActor` on the type rather than on each method (`SWIFT_PRACTICES.md` §1), and `@Observable`
/// rather than `@State` copies scattered across the views, so there is one owner for "which step
/// are we on" and the surfaces derive from it instead of holding their own opinion.
@MainActor
@Observable
public final class PairingFlowModel {
    /// Where the flow is. A closed set: the screen is a function of this, so a state with no screen
    /// fails to compile rather than rendering blank.
    public enum Step: Equatable {
        case scan
        case cameraBlocked(CameraAuthorization)
        case typing
        case verifying(PairingAttempt)
        case failed(PairingOutcome)
        case paired(PairedMac)
        /// The Mac paired, and the Keychain write did not.
        ///
        /// Kept apart from both neighbours on purpose. Folding it into `.paired` is the bug this
        /// case replaced — a `try?` that let the success surface render over a write that never
        /// happened, so the pairing vanished at the next launch with nothing having said so
        /// (`SWIFT_PRACTICES.md` §3: never swallow an error to keep a UI tidy). Folding it into
        /// `.failed` would be the opposite lie: the Mac really did pair, and a pairing code is
        /// one-use, so "pairing failed" would send the user to spend a code they do not need to.
        case pairedNotStored(PairedMac)
    }

    public private(set) var step: Step = .scan
    public var entry = PairingCodeEntry()
    /// The failure that belongs *beside the field* rather than on its own pane.
    public private(set) var inlineFailure: PairingOutcome?

    private let pairing: any PairingService
    private let camera: any CameraAuthorizing
    private let store: any PairingRecordStore
    /// Injectable for the same reason `KeychainPairingStore`'s is: A24 is a claim about what
    /// reaches a log line, and a log with no seam is a claim no test can reach.
    private let log: ControlLog

    public init(
        pairing: any PairingService,
        camera: any CameraAuthorizing,
        store: any PairingRecordStore,
        log: ControlLog = ControlLog()
    ) {
        self.pairing = pairing
        self.camera = camera
        self.store = store
        self.log = log
    }

    /// Decide the opening step from the camera's actual state.
    public func start() async {
        let authorization = await camera.current()
        step = authorization.canScan ? .scan : .cameraBlocked(authorization)
    }

    public func requestCamera() async {
        let authorization = await camera.request()
        step = authorization.canScan ? .scan : .cameraBlocked(authorization)
    }

    public func typeInstead() {
        inlineFailure = nil
        step = .typing
    }

    public func scanInstead() {
        inlineFailure = nil
        entry = PairingCodeEntry()
        step = .scan
    }

    /// A QR came back from the scanner.
    ///
    /// The decode's three failures are kept apart all the way to the surface: "not our code" is a
    /// different sentence from "our code, wrong version", and both are different from "our code,
    /// unreadable". Collapsing them here would undo the two-pass decode that produced them.
    public func scanned(_ text: String) async {
        do {
            let payload = try PairingPayload.decode(text)
            await submit(.scanned(payload))
        } catch {
            switch error {
            case .notAPairingCode:
                step = .failed(.notAPairingCode)
            case let .unsupportedVersion(found):
                _ = found
                step = .failed(.versionMismatch(macName: nil))
            case .malformedPayload:
                step = .failed(.malformedPayload)
            }
        }
    }

    /// The typed code was committed.
    public func submitTyped() async {
        guard let code = entry.code else { return }
        await submit(.typed(code))
    }

    private func submit(_ attempt: PairingAttempt) async {
        step = .verifying(attempt)
        let outcome = await pairing.pair(using: attempt)

        switch outcome {
        case let .paired(mac):
            // The write is what makes the pairing survive a relaunch, so its failure is a state
            // the user is told about rather than an error discarded to keep the success surface.
            do {
                try await store.save(mac)
                step = .paired(mac)
            } catch {
                log.warning(
                    "pairing record could not be stored: \(PairingWriteFailure.logSafe(error))"
                )
                step = .pairedNotStored(mac)
            }
        case .notRecognised, .expired:
            // These two are fixable by typing again, so they belong beside the field.
            inlineFailure = outcome
            step = .typing
        default:
            step = .failed(outcome)
        }
    }

    /// Retry from the top after a whole-pane failure.
    public func retry() {
        inlineFailure = nil
        entry = PairingCodeEntry()
        step = .scan
    }

    /// Retry from the top, **re-asking the camera** rather than assuming the scanner is reachable.
    ///
    /// `retry()` sets `.scan` unconditionally, and `start()` — the only authorization check — runs
    /// from `.task`, which does not re-fire when the step changes. A user whose camera is denied or
    /// restricted therefore lands on a scanner that can never see anything, which is precisely the
    /// dead end A16 exists to prevent: every camera state must still offer the typed path.
    public func restart() async {
        inlineFailure = nil
        entry = PairingCodeEntry()
        await start()
    }
}

/// The pairing flow, from the scan surface to the paired screen.
struct PairingFlowView<Preview: View>: View {
    @Bindable var model: PairingFlowModel
    let onOpenSettings: () -> Void
    let onFinished: () -> Void
    /// The camera preview is injected as a *function of the callback* rather than as a plain view,
    /// so the scanner reports codes straight into the model. Shipping it as a bare view would need
    /// a second channel — a binding or a notification — for the decoded string to travel back.
    @ViewBuilder var cameraPreview: (@escaping @MainActor (String) -> Void) -> Preview

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PhoneMetric.loose) {
                switch model.step {
                case .scan:
                    ScanView(onTypeInstead: model.typeInstead) {
                        cameraPreview { text in Task { await model.scanned(text) } }
                    }

                case let .cameraBlocked(authorization):
                    CameraPermissionView(
                        authorization: authorization,
                        onRequest: { Task { await model.requestCamera() } },
                        onOpenSettings: onOpenSettings,
                        onTypeInstead: model.typeInstead
                    )

                case .typing:
                    TypedEntryView(
                        entry: $model.entry,
                        failure: model.inlineFailure,
                        onSubmit: { Task { await model.submitTyped() } },
                        onScanInstead: model.scanInstead
                    )

                case let .verifying(attempt):
                    VerifyingView(attempt: attempt)

                case let .failed(outcome):
                    PairingOutcomeView(
                        outcome: outcome,
                        macName: macName(from: outcome),
                        onPrimary: outcomeAction(for: outcome)
                    )

                case let .paired(mac):
                    PairedSuccessView(mac: mac, onDone: onFinished)

                case let .pairedNotStored(mac):
                    PairedNotStoredView(mac: mac) { Task { await model.restart() } }
                }
            }
            .padding(PhoneMetric.loose)
        }
        .background(ColorToken.ground.color)
        .navigationTitle("Pair Mac")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .task { await model.start() }
    }

    private func macName(from outcome: PairingOutcome) -> String? {
        switch outcome {
        case let .versionMismatch(name), let .unreachable(name), let .refused(name): name
        default: nil
        }
    }

    /// Refused sends you back rather than round again — the decision was made at the Mac.
    ///
    /// Everything else restarts through `restart()` rather than `retry()`, so the camera is asked
    /// again on the way. The panes reached here are the ones a user retries most, and dropping a
    /// denied-camera user onto a scanner that can never see anything is the dead end A16 forbids.
    private func outcomeAction(for outcome: PairingOutcome) -> () -> Void {
        if case .refused = outcome { return onFinished }
        return { Task { await model.restart() } }
    }
}

/// The Settings tab: the paired-Mac surface, and the flow it opens.
public struct PhoneSettingsScreen<Preview: View>: View {
    private let pairing: any PairingService
    private let store: any PairingRecordStore
    private let camera: any CameraAuthorizing
    private let openSystemSettings: () -> Void
    private let cameraPreview: (@escaping @MainActor (String) -> Void) -> Preview

    @State private var state: PairedMacSurfaceState = .loading
    @State private var isPairing = false
    @State private var confirmingUnpair = false
    /// Set when `clear()` threw. Held on the screen rather than added to
    /// `PairedMacSurfaceState` on purpose: the nine states of `DESIGN.md` §5 describe what the
    /// *data* is doing, and a failed delete leaves the data exactly where it was — the Mac is
    /// still paired, and still renders as such. What is missing without this is the sentence
    /// saying so, not a tenth data state.
    /// The name of the Mac whose unpair failed, or nil when none did.
    ///
    /// The **name is captured at the moment of failure** rather than read from `state` when the
    /// banner draws. `load()` sets `.loading` first, where `state.mac` is nil, so a banner
    /// resolving against the current state says "Couldn't unpair your Mac" over a skeleton — and
    /// in the never-paired branch it would sit above "No Mac paired yet", naming a Mac the surface
    /// is simultaneously denying.
    ///
    /// Held on the screen rather than added to `PairedMacSurfaceState` on purpose: the nine states
    /// of `DESIGN.md` §5 describe what the *data* is doing, and a failed delete leaves the data
    /// exactly where it was — the Mac is still paired, and still renders as such. What is missing
    /// without this is the sentence saying so, not a tenth data state.
    @State private var unpairFailure: String?

    public init(
        pairing: any PairingService,
        store: any PairingRecordStore,
        camera: any CameraAuthorizing,
        openSystemSettings: @escaping () -> Void,
        @ViewBuilder cameraPreview: @escaping (@escaping @MainActor (String) -> Void) -> Preview
    ) {
        self.pairing = pairing
        self.store = store
        self.camera = camera
        self.openSystemSettings = openSystemSettings
        self.cameraPreview = cameraPreview
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PhoneMetric.normal) {
                    if let unpairFailure {
                        PhoneMessageBlock(
                            entry: PairingCopy.entry(.unpairFailed).resolved(macName: unpairFailure),
                            tone: .failure,
                            glyph: .warn
                        )
                    }

                    PairedMacSettingsView(
                        state: state,
                        // Starting a new pairing retires the failure: whatever happens next, the
                        // sentence describing the previous attempt stops being true.
                        onPair: {
                            unpairFailure = nil
                            isPairing = true
                        },
                        onUnpair: { confirmingUnpair = true }
                    )
                }
                .padding(PhoneMetric.loose)
            }
            .background(ColorToken.ground.color)
            .navigationTitle("Settings")
            .navigationDestination(isPresented: $isPairing) {
                PairingFlowView(
                    model: PairingFlowModel(pairing: pairing, camera: camera, store: store),
                    onOpenSettings: openSystemSettings,
                    onFinished: {
                        isPairing = false
                        // A completed pairing settles the question the failed unpair raised, so
                        // the banner must not outlive it — otherwise a Mac that was just correctly
                        // re-paired sits under "Couldn't unpair … still paired. Nothing changed".
                        unpairFailure = nil
                        Task { await load() }
                    },
                    cameraPreview: cameraPreview
                )
            }
            // A named consequence, and Cancel is its own control. `DESIGN.md` §9 prefers undo over
            // confirm — but unpairing revokes a credential and cannot be undone, so it earns the
            // dialog. The destructive action is never the default.
            .confirmationDialog(
                PairingCopy.entry(.unpairConfirm).resolved(macName: state.mac?.name).headline ?? "",
                isPresented: $confirmingUnpair,
                titleVisibility: .visible
            ) {
                Button(PairingCopy.entry(.unpairConfirm).actionLabel ?? "Unpair", role: .destructive) {
                    Task { await unpair() }
                }
                Button(PairingCopy.entry(.unpairConfirm).secondaryActionLabel ?? "Cancel", role: .cancel) {}
            } message: {
                Text(PairingCopy.entry(.unpairConfirm).body)
            }
            .task { await load() }
        }
    }

    /// Read the stored pairing and ask whether the Mac is answering.
    ///
    /// The three-way load matters here: **missing is not an error**. A phone restored from a backup
    /// has no record — `ThisDeviceOnly` did not carry it — and greeting that user with "Can't read
    /// this phone's pairing" would offer to fix a problem they do not have.
    private func load() async {
        state = .loading
        switch await store.load() {
        case .missing:
            state = .neverPaired
        case .unreadable:
            state = .unreadable
        case let .loaded(mac):
            let connection = await pairing.reachability(of: mac)
            switch connection {
            case .reachable:
                // Reachable but never reported since launch is the Partial state, not the happy
                // one — and it says "unknown" rather than inventing a last-seen instant.
                state = mac.lastSeen == nil ? .partial(mac) : .reachable(mac)
            case .notReachable:
                state = .macUnreachable(mac)
            case .neverPaired:
                state = .neverPaired
            }
        }
    }

    private func unpair() async {
        // The name is read *before* the attempt, because `load()` below moves through `.loading`
        // where there is no Mac to name.
        let name = state.mac?.name
        // The record is still there when this fails, so the Mac is still paired. Say that, rather
        // than reloading into an unchanged surface and leaving the user to infer it.
        unpairFailure = await store.unpair() == .failed ? name : nil
        await load()
    }
}
