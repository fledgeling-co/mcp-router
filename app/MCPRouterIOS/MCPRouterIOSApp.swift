import MCPRouterKit
import MCPRouterUI
import SwiftUI
import UIKit

/// The iPhone companion.
///
/// The shell is `PhoneShell`, drawn entirely from the shared design system, and everything
/// device-bound is injected here rather than reached for from inside the views: the camera adapter,
/// the scanner preview, and the one call that leaves the app for iOS Settings. That is what lets
/// every surface be exercised on a macOS test host. The iOS tab-identifier bridge stays inside
/// PhoneShell and changes only its enclosing controller’s accessibility identifiers.
///
/// **Pairing is the live service in every Release build.** `PhonePairingFactory` composes
/// `LivePairingService` over `NetworkPairingTransport`, pinned to the QR's fingerprint (plan §2.2).
/// The fixture is reachable only from a Debug build that names one on purpose, so a shipped phone
/// cannot report "Paired." for a Mac it never reached.
///
/// **The control client is no longer a fixture by default, and the queue is no longer in memory.**
/// Until I3 this call site passed neither, so `PhoneShell` took `FixtureControlAPIClient()` and
/// `InMemoryCapabilityQueue()` in every configuration — meaning a Release build rendered recorded
/// servers as the user's real library, and a queued item did not survive relaunching the app
/// despite `FileCapabilityQueueWriter` existing and being tested. Both are wired properly here.
@main
struct MCPRouterIOSApp: App {
    /// Where the queue and the dismissal set live, resolved once.
    ///
    /// **A failure here is carried, not swallowed.** `defaultDirectory` throws, and the tempting
    /// `try?` would fall back to an in-memory store — silently reproducing the exact defect this
    /// wiring exists to fix, and rendering a queue that quietly forgets everything on relaunch.
    /// So the failure becomes a value the surfaces can show.
    private let storage: Result<URL, Error> = Result {
        try FileCapabilityQueueWriter.defaultDirectory()
    }

    /// The pairing record, kept between launches. `KeychainPairingStore` holds no state of its own, so
    /// the service and the shell each hold one and read and write the same Keychain item.
    private let records = KeychainPairingStore()

    /// The pairing service this build uses. `PhonePairingFactory` holds the decision: Release is always
    /// the live service, and the fixture is reachable only from a Debug build.
    private let pairing: any PairingService = PhonePairingFactory.makeService(
        deviceName: UIDevice.current.name,
        records: KeychainPairingStore()
    )

    /// The camera adapter this build uses. `PhoneCameraFactory` holds the decision, and the
    /// measurement that makes it necessary.
    ///
    /// **Stored once rather than built in `body`.** `LiveCameraAuthorization` is a fieldless struct,
    /// so constructing it per render cost nothing and hid this: `FixtureCameraAuthorization` is an
    /// actor, and a fresh one on every body pass gave `PairingFlowModel` a dependency whose identity
    /// changed underneath it. Measured 20 Aug 2026 — tapping 'Pair Mac' pushed the flow and landed
    /// back on Settings, and the on-glass test read that as the pre-prompt never opening.
    private let camera: any CameraAuthorizing = switch PhoneCameraFactory.currentChoice() {
    case .live: LiveCameraAuthorization()
    case let .fixture(state): FixtureCameraAuthorization(state)
    }

    var body: some Scene {
        WindowGroup {
            switch storage {
            case let .success(directory):
                PhoneShell(
                    pairing: pairing,
                    store: records,
                    camera: camera,
                    client: PhoneClientFactory.makeClient(),
                    queue: FileCapabilityQueueWriter(directory: directory),
                    dismissals: FileDismissalStore(directory: directory),
                    openSystemSettings: openSystemSettings,
                    cameraPreview: { onCode in QRScannerView(onCode: onCode) }
                )
            case let .failure(error):
                StorageUnavailableView(reason: error.localizedDescription)
            }
        }
    }

    /// The denied-camera recovery. It leaves the app, which is the only honest action available —
    /// asking again after a refusal shows nothing at all.
    @MainActor
    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
