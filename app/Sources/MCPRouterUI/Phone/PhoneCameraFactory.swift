import Foundation
import MCPRouterKit

/// Which camera-permission adapter the phone uses, and the one rule that must never bend.
///
/// **A Release build always asks the real camera.** This is `PhoneClientFactory`'s rule applied to
/// the other adapter the phone injects, and for the same reason: a build that can be talked into a
/// permission state by an environment variable is a build that can be talked into claiming it has
/// permission it does not have.
///
/// **Why this exists at all.** `AVCaptureDevice.authorizationStatus(for: .video)` reports
/// `.authorized` on the iOS Simulator — measured 20 Aug 2026 on iPhone 17 Pro / iOS 26.0, both on a
/// fresh install and after `xcrun simctl privacy <udid> reset all`, which does not list `camera`
/// among its services and does not reach it. So the `.notDetermined` pre-prompt — the surface that
/// explains what the camera is for *before* iOS asks — cannot be produced on the one instrument
/// that renders the shipping app. Without this it is not a state that happens to be untested; it is
/// a state no on-glass test can ever reach.
///
/// **What the substitution costs, stated plainly.** With `MCPROUTER_CAMERA` set, the on-glass test
/// proves the surface renders correctly *for a given authorization state*. It does not prove
/// `LiveCameraAuthorization` maps `AVAuthorizationStatus` to that state — that mapping is four
/// lines and is covered on the host by `CameraAuthorizationTests`. The two claims are kept apart
/// rather than folded together, because folding them is how a double comes to stand in for the
/// thing it doubles.
///
/// The decision is a pure function over `(isDebugBuild, environment)` for the reason
/// `PhoneClientFactory` gives: a Debug test run can then assert the *Release* branch, which is the
/// only way the rule above is checkable without a Release simulator install.
public enum PhoneCameraFactory {
    /// The variable the on-glass lane sets to choose a permission state. Debug builds only.
    public static let cameraVariable = "MCPROUTER_CAMERA"

    public enum Choice: Equatable, Sendable {
        /// The real `AVCaptureDevice` adapter. What ships.
        case live
        /// A named permission state. Debug only, and only ever chosen deliberately.
        case fixture(CameraAuthorization)
    }

    public static func choice(isDebugBuild: Bool, environment: [String: String]) -> Choice {
        guard isDebugBuild else { return .live }
        guard let named = environment[cameraVariable],
              let state = CameraAuthorization(rawValue: named)
        else {
            return .live
        }
        return .fixture(state)
    }

    /// The choice this build and this process actually make.
    ///
    /// Unlike `PhoneClientFactory`, an unset variable falls through to `.live` rather than to a
    /// fixture. The control client has no honest live answer on a phone with no router, so it
    /// defaults to a recording; the camera does, on every device that has one.
    public static func currentChoice(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Choice {
        #if DEBUG
            choice(isDebugBuild: true, environment: environment)
        #else
            choice(isDebugBuild: false, environment: environment)
        #endif
    }
}
