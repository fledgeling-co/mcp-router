import Testing
@testable import MCPRouterKit
@testable import MCPRouterUI

/// The shell's default pairing service is the factory's choice, so a preview or host test that names no
/// service cannot be handed the fixture by the shell itself.
///
/// The shell keeps the service in a private property, so this reads it by reflection. The check is about
/// which type the default resolves to, and reflection is the only way to see it without making the
/// property public.
///
/// The default is decided by the test process's environment. `MCPROUTER_PHONE_PAIRING` is not set in a
/// test run, so a Debug build composes the live service. A run that sets it would select a fixture here,
/// deliberately, and that run would say so.
@Suite("Phone shell pairing default")
struct PhoneShellPairingDefaultTests {
    @Test("a shell that names no pairing service composes the live service, not the fixture")
    func defaultIsTheLiveService() {
        let pairing = Mirror(reflecting: PhoneShell()).children.first { $0.label == "pairing" }?.value

        #expect(pairing is LivePairingService)
        #expect(!(pairing is FixturePairingService))
    }
}
