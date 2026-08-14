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
/// endpoint and is unmerged; the seam it implements is `PairingService`, published in
/// `planning/specs/spec-I1.md`. Shipping an invented network client now would mean M6 discovering
/// our wire rather than agreeing one.
@main
struct MCPRouterIOSApp: App {
    var body: some Scene {
        WindowGroup {
            PhoneShell(
                pairing: FixturePairingService(),
                store: KeychainPairingStore(),
                camera: LiveCameraAuthorization(),
                openSystemSettings: openSystemSettings,
                cameraPreview: { onCode in QRScannerView(onCode: onCode) }
            )
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
