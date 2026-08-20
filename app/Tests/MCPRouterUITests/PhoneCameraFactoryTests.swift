import Foundation
import MCPRouterKit
import Testing
@testable import MCPRouterUI

/// The rule that a Release build always asks the real camera, and the switch that makes the
/// `.notDetermined` pre-prompt reachable on glass.
///
/// The pre-prompt is the surface that explains what the camera is for before iOS asks. It could
/// not be photographed on any simulator, because `AVCaptureDevice.authorizationStatus(for: .video)`
/// answers `.authorized` there and `simctl privacy` does not carry `camera` among its services —
/// so `PhoneCameraFactory` exists, and these are the assertions that keep it from reaching a
/// shipped build.
///
/// Not gated on `os(macOS)` the way `ShellClientFactoryTests` is: that suite tests a factory whose
/// collaborators are Mac-only, and this one tests a pure function over a string.
@Suite("Phone camera-adapter selection")
struct PhoneCameraFactoryTests {
    @Test("a Release build is live, and the environment cannot change that")
    func releaseIsAlwaysLive() {
        #expect(PhoneCameraFactory.choice(isDebugBuild: false, environment: [:]) == .live)
        // Every permission state, tried against a Release build. `.authorized` is the one that
        // matters most: a shipped build talked into it would open the scanner without iOS having
        // granted anything, and the pre-prompt — the only place the user is told what the camera
        // is for — would never render.
        for state in CameraAuthorization.allCases {
            let environment = [PhoneCameraFactory.cameraVariable: state.rawValue]
            #expect(
                PhoneCameraFactory.choice(isDebugBuild: false, environment: environment) == .live,
                "a Release build was talked into the \(state.rawValue) camera fixture"
            )
        }
    }

    @Test("a Debug build with nothing set asks the real camera")
    func debugDefaultsToLive() {
        // Deliberately unlike `ShellClientFactory`, which defaults a Debug build to a fixture. A
        // phone with no router has no honest live control answer; a phone with a camera has an
        // honest live camera answer, so the default here is the real one and the fixture is only
        // ever chosen by name.
        #expect(PhoneCameraFactory.choice(isDebugBuild: true, environment: [:]) == .live)
    }

    @Test("every permission state is reachable through the variable")
    func everyStateIsReachable() {
        // Not a sample: a state that cannot be selected is a state the on-glass lane can never
        // drive the running app into, which is the whole gap this switch closes.
        for state in CameraAuthorization.allCases {
            let environment = [PhoneCameraFactory.cameraVariable: state.rawValue]
            #expect(
                PhoneCameraFactory.choice(isDebugBuild: true, environment: environment)
                    == .fixture(state),
                "\(state.rawValue) was not reachable through \(PhoneCameraFactory.cameraVariable)"
            )
        }
    }

    @Test("an unrecognised name falls back to the real camera rather than to a guess")
    func unknownNameIsLive() {
        // A misspelled state must not silently select a neighbouring one. Falling through to
        // `.live` makes the mistake visible on the surface — the scanner opens as it always does —
        // rather than rendering a permission state nobody asked for.
        let environment = [PhoneCameraFactory.cameraVariable: "notdetermined"]
        #expect(PhoneCameraFactory.choice(isDebugBuild: true, environment: environment) == .live)
    }
}
