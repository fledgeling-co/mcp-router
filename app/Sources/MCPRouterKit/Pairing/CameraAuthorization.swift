import Foundation

/// Whether this app may open the camera.
///
/// **Four cases, mirroring `AVAuthorizationStatus`, and the fourth is the one that gets dropped.**
/// `restricted` is not a stricter `denied`: it is set by a device policy or Screen Time, and the
/// user in front of the phone may have no way to change it. Sending them to iOS Settings — the
/// correct recovery for `denied` — is a dead end there, so `restricted` renders its own state whose
/// primary action is the typed path.
///
/// Mirrored rather than re-exported so `MCPRouterKit` keeps its promise of no framework
/// dependencies: `AVFoundation` appears only in the iOS app target, behind `CameraAuthorizing`.
public enum CameraAuthorization: String, Sendable, Equatable, CaseIterable {
    case notDetermined
    case authorized
    case denied
    case restricted

    /// Whether the scanner can run.
    public var canScan: Bool { self == .authorized }

    /// Whether asking would produce a system prompt. Asking again once denied does nothing, which
    /// is why the denied surface offers Settings instead of a second, silent request.
    public var canRequest: Bool { self == .notDetermined }

    /// The copy this state renders. Authorized has none — the scanner itself is the surface.
    public var copyKey: PairingCopy.Key? {
        switch self {
        case .notDetermined: .cameraNotDetermined
        case .denied: .cameraDenied
        case .restricted: .cameraRestricted
        case .authorized: nil
        }
    }
}

/// Reading and requesting camera permission.
///
/// A protocol so all four states are exercised in a unit test on the macOS host, with no simulator,
/// no device, and no `AVFoundation` import in the test target. The live implementation is
/// `LiveCameraAuthorization` in the iOS app target.
public protocol CameraAuthorizing: Sendable {
    /// The current state, without prompting.
    func current() async -> CameraAuthorization
    /// Prompt if — and only if — prompting can produce an answer.
    func request() async -> CameraAuthorization
}

/// A fixture that starts in any state and records whether it was asked.
public actor FixtureCameraAuthorization: CameraAuthorizing {
    private var state: CameraAuthorization
    private let grantsOnRequest: Bool
    public private(set) var requestCount = 0

    public init(_ state: CameraAuthorization = .authorized, grantsOnRequest: Bool = true) {
        self.state = state
        self.grantsOnRequest = grantsOnRequest
    }

    public func current() async -> CameraAuthorization {
        state
    }

    public func request() async -> CameraAuthorization {
        requestCount += 1
        // Only `notDetermined` can change by asking. A denied or restricted state that "became"
        // authorized on request would let a test pass a recovery path the OS does not offer.
        guard state.canRequest else { return state }
        state = grantsOnRequest ? .authorized : .denied
        return state
    }

    public func asked() async -> Int {
        requestCount
    }
}
