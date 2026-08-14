@preconcurrency import AVFoundation
import MCPRouterKit

/// The real camera-permission adapter.
///
/// It lives here rather than in `MCPRouterKit` because the kit imports no framework by rule
/// (`SWIFT_PRACTICES.md` §8), and here rather than in `MCPRouterUI` because `AVFoundation`'s
/// authorization API is iOS/macOS-divergent and the shared UI product compiles for both. Everything
/// the surfaces need is the four-case `CameraAuthorization`, which is why they can be tested
/// without any of this.
struct LiveCameraAuthorization: CameraAuthorizing {
    func current() async -> CameraAuthorization {
        Self.map(AVCaptureDevice.authorizationStatus(for: .video))
    }

    func request() async -> CameraAuthorization {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        // Only `.notDetermined` can be changed by asking. Calling `requestAccess` when the answer
        // is already no returns false immediately without showing anything, so a surface that
        // treated it as a retry would present a button that visibly does nothing.
        guard status == .notDetermined else { return Self.map(status) }

        let granted = await AVCaptureDevice.requestAccess(for: .video)
        return granted ? .authorized : .denied
    }

    /// All four cases, mapped explicitly. `@unknown default` maps to `.restricted` rather than
    /// `.denied`: a status this build does not recognise is one the user probably cannot clear from
    /// Settings, and `.restricted` is the state whose recovery is the typed path — the one that
    /// always works.
    static func map(_ status: AVAuthorizationStatus) -> CameraAuthorization {
        switch status {
        case .notDetermined: .notDetermined
        case .authorized: .authorized
        case .denied: .denied
        case .restricted: .restricted
        @unknown default: .restricted
        }
    }
}
