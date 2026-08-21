import Foundation
import Testing
@testable import RouterCore

/// `redirect_uri` is the constraint that matters most on the authorization surface.
///
/// Without it a page the user is visiting navigates them to
/// `/authorize?redirect_uri=https://attacker.example/cb`, the approval fires, and the attacker
/// holds a code. Every shape below was MEASURED against both URL parsers on 2026-08-21 — the
/// out-of-family review lane pointed at this parser as the place it would attack — and the
/// expectations here are what that measurement found, not what seemed likely.
@Suite("Loopback redirect URIs")
struct AuthServerRedirectTests {
    @Test("the three loopback spellings are accepted, at any port")
    func loopbackAccepted() {
        for uri in [
            "http://127.0.0.1:33418/callback",
            "http://localhost:1/cb",
            "http://[::1]:65535/cb",
            "http://127.0.0.1/cb"
        ] {
            #expect(AuthServerAuthority.isLoopbackRedirect(uri), "\(uri) should be accepted")
        }
    }

    /// Both differences the measurement found between Foundation's parser and Node's, closed here.
    /// Node lowercases the host and canonicalises IPv6; Foundation does neither, so without these
    /// a client that registers successfully against the reference is refused by this router.
    @Test("case and IPv6 spelling are normalised, because the reference's parser normalises them")
    func normalisation() {
        #expect(AuthServerAuthority.isLoopbackRedirect("http://LOCALHOST:1/cb"))
        #expect(AuthServerAuthority.isLoopbackRedirect("http://[0:0:0:0:0:0:0:1]:1/cb"))
        #expect(AuthServerAuthority.isLoopbackRedirect("HTTP://127.0.0.1:1/cb"))
    }

    /// The attack this predicate exists to refuse. Every one of these resolves to a host that is
    /// not the loopback, and the userinfo family is the reason the check reads the PARSED host
    /// rather than matching the raw string — `http://[::1]@evil.example/cb` contains `[::1]` and
    /// goes to `evil.example`.
    @Test("a redirect off the machine is refused, in every shape measured")
    func offMachineRefused() {
        for uri in [
            "https://127.0.0.1/cb",
            "https://attacker.example/cb",
            "http://[::1]@evil.example/cb",
            "http://127.0.0.1@evil.example/cb",
            "http://localhost@evil.example/cb",
            "http://127.0.0.1.evil.example/cb",
            "http://localhost.evil.example/cb",
            "http://evil.example/cb#127.0.0.1",
            "http://[::ffff:127.0.0.1]/cb",
            "http://127.0.0.2/cb",
            "ftp://127.0.0.1/cb",
            "javascript:alert(1)//127.0.0.1"
        ] {
            #expect(!AuthServerAuthority.isLoopbackRedirect(uri), "\(uri) should be refused")
        }
    }

    /// The declared divergence, asserted so it cannot be closed from this end without this test
    /// saying so. The reference's parser normalises IPv4 shorthand to `127.0.0.1` and accepts
    /// these; this router refuses them. Safe in that direction — neither redirects off the machine
    /// — and recorded as `div-r14-redirect-host` rather than silently reconciled.
    @Test("IPv4 shorthand is refused here and accepted by the reference — div-r14-redirect-host")
    func declaredDivergence() {
        #expect(!AuthServerAuthority.isLoopbackRedirect("http://127.1/cb"))
        #expect(!AuthServerAuthority.isLoopbackRedirect("http://2130706433/cb"))
    }

    /// An over-long URI is refused before it is parsed, so a looping page cannot make the router
    /// do unbounded work per request.
    @Test("an over-long redirect_uri is refused without being parsed")
    func lengthCapped() {
        let long = "http://127.0.0.1:1/" + String(repeating: "a", count: 2048)
        #expect(!AuthServerAuthority.isLoopbackRedirect(long))
    }
}
