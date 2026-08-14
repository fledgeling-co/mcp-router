import MCPRouterKit
import MCPRouterUI
import SwiftUI
import UIKit

/// The iPhone companion.
///
/// The shell is `PhoneShell`, drawn entirely from the shared design system, and everything
/// device-bound is injected here rather than reached for from inside the views: the camera adapter,
/// the scanner preview, and the one call that leaves the app for iOS Settings. That is what lets
/// every surface be exercised on a macOS test host, and it is why `MCPRouterUI` carries no `UIKit`
/// import of its own.
///
/// **`FixturePairingService` is deliberate, not a stub left behind.** M6 owns the Mac's pairing
/// endpoint; the transport it needs is deferred (D-m6-a), and the seam this implements is
/// `PairingService`, published in `planning/specs/spec-I1.md`. Shipping an invented network client
/// now would mean the Mac discovering our wire rather than agreeing one.
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

    var body: some Scene {
        WindowGroup {
            switch storage {
            case let .success(directory):
                PhoneShell(
                    pairing: FixturePairingService(),
                    store: KeychainPairingStore(),
                    camera: LiveCameraAuthorization(),
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
