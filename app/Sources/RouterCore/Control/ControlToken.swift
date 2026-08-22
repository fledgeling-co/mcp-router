import Foundation

/// The control API's path ownership and its shared secret.
public enum ControlPaths {
    /// True when this path belongs to the control API rather than to `/mcp`.
    ///
    /// Classified over the **encoded** pathname with no decoding, slash-collapsing or dot-segment
    /// normalisation: `/servers%2Fx` is not a control path, and a port that decodes first would
    /// claim it (B15).
    ///
    /// The negatives matter as much as the positives — `/servershim` and `/usagexyz` share a prefix
    /// with an owned path and are not owned, which a `hasPrefix("/servers")` test gets wrong.
    public static func isControlPath(_ pathname: String) -> Bool {
        pathname == "/servers"
            || pathname.hasPrefix("/servers/")
            || pathname == "/usage"
            || pathname.hasPrefix("/usage/")
            || pathname.hasPrefix("/registry/")
            // M22's two. **Exact match, with no prefix arm**, unlike `/servers` and `/usage`:
            // neither has a sub-path, so `/harnesses/x` is not a route this router answers and
            // claiming it would turn a typo into a 405 that reads as "the method is wrong".
            // `/harnessesx` and `/insightsy` share a prefix with an owned path and are not owned,
            // which is the negative the `hasPrefix` arms above have to be careful about.
            //
            // Both diverge from `src/control.ts`, which answers them 404, and both are declared
            // as divergences in `planning/parity/surface.tsv` rather than left to be discovered.
            || pathname == "/harnesses"
            || pathname == "/insights"
    }
}

/// A shared secret for the mutating half of the control API.
///
/// The Host allowlist on `/mcp` defeats DNS rebinding but not plain CSRF: a page the user visits
/// can POST straight to the loopback port with a correct Host header, and a `text/plain` body is a
/// CORS "simple request" needing no preflight — the page cannot read the reply, but the side effect
/// lands. Installing a server means running an arbitrary command with the user's environment, so
/// that side effect is the whole machine. The token lives in a `0600` file no web page can read,
/// and the JSON content-type requirement forces a preflight that is never answered.
public struct ControlToken: Sendable {
    private let path: String
    private let fileSystem: any FileSystem & FileModeWriting
    private let randomBytes: @Sendable (Int) -> [UInt8]

    /// The modes the reference writes, and the reason they are not decoration.
    ///
    /// `writeFileSync(TOKEN_PATH, …, { mode: 0o600 })` and
    /// `mkdirSync(ROUTER_HOME, { recursive: true, mode: 0o700 })` (`src/control.ts:51-53`). Written
    /// through the mode-less `FileSystem` overloads instead, the token lands at the umask default —
    /// `0644` in a `0755` directory — and the whole argument above collapses: the secret that gates
    /// an endpoint whose job is to run an arbitrary command line becomes readable by every account
    /// on the machine. `FileAuthStore` already writes its records this way (`0700`/`0600`); this is
    /// the same rule for the higher-value secret.
    static let tokenMode: UInt16 = 0o600
    static let homeMode: UInt16 = 0o700

    public init(
        path: String,
        fileSystem: any FileSystem & FileModeWriting = RealFileSystem(),
        randomBytes: @escaping @Sendable (Int) -> [UInt8] = { count in
            (0 ..< count).map { _ in UInt8.random(in: 0 ... 255) }
        }
    ) {
        self.path = path
        self.fileSystem = fileSystem
        self.randomBytes = randomBytes
    }

    /// Reuse a non-empty token, otherwise mint one.
    ///
    /// The hex is **lowercase** — `randomBytes(32).toString('hex')` in Node is lowercase, and
    /// `%02X` would produce 64 characters that pass a naive "is it hex" check while differing from
    /// the reference byte for byte (B18).
    public func load() throws -> String {
        let existing: Data? = fileSystem.fileExists(atPath: path)
            ? try? fileSystem.readFile(atPath: path)
            : nil
        if let data = existing {
            // Lossy on purpose: `readFileSync(path, 'utf8')` substitutes U+FFFD rather than
            // failing, and a token file of invalid bytes is non-empty to the reference.
            // swiftlint:disable:next optional_data_string_conversion
            let trimmed = Self.jsTrim(String(decoding: data, as: UTF8.self))
            if !trimmed.isEmpty { return trimmed }
        }
        try fileSystem.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent, mode: Self.homeMode
        )
        let token = randomBytes(32).map { String(format: "%02x", $0) }.joined()
        try fileSystem.writeFile(Data((token + "\n").utf8), atPath: path, mode: Self.tokenMode)
        return token
    }

    /// ECMAScript `String.prototype.trim` — **not** Foundation's `.whitespacesAndNewlines`.
    ///
    /// The two disagree in both directions, and each disagreement is reachable from a file a user
    /// or an editor wrote: JavaScript trims `U+FEFF` (a byte-order mark, which Foundation keeps)
    /// and does **not** trim `U+0085` (which Foundation strips). A token file whose only content is
    /// `U+0085` is therefore non-empty to the reference and empty to a Foundation trim, so the two
    /// implementations would disagree about whether to mint a new token (B19).
    static func jsTrim(_ text: String) -> String {
        let whitespace: Set<UInt32> = [
            0x9, 0xA, 0xB, 0xC, 0xD, 0x20, 0xA0, 0x1680, 0xFEFF,
            0x2000, 0x2001, 0x2002, 0x2003, 0x2004, 0x2005, 0x2006, 0x2007, 0x2008, 0x2009,
            0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000
        ]
        func isJSWhitespace(_ scalar: Unicode.Scalar) -> Bool {
            whitespace.contains(scalar.value)
        }
        var scalars = Array(text.unicodeScalars)
        while let first = scalars.first, isJSWhitespace(first) {
            scalars.removeFirst()
        }
        while let last = scalars.last, isJSWhitespace(last) {
            scalars.removeLast()
        }
        var out = String.UnicodeScalarView()
        for scalar in scalars {
            out.append(scalar)
        }
        return String(out)
    }

    /// Constant-time comparison of the supplied credential against the expected one.
    ///
    /// Two details are contract rather than style. An exact `Bearer ` prefix **shadows**
    /// `x-mcpr-token` even when the bearer value is empty or wrong — a port that tries both and
    /// accepts either would authorise a request the reference rejects (B17). And the length check
    /// is on **UTF-8 bytes**, matching `Buffer.from`, so 64 `é` characters never reach the
    /// comparison against a 64-byte ASCII token.
    public static func isAuthorized(_ request: ControlAPIRequest, expected: String) -> Bool {
        let header = request.header("authorization") ?? ""
        let supplied: String = if header.hasPrefix("Bearer ") {
            String(header.dropFirst(7))
        } else {
            request.header("x-mcpr-token") ?? ""
        }
        let a = Array(supplied.utf8)
        let b = Array(expected.utf8)
        guard a.count == b.count else { return false }
        var difference: UInt8 = 0
        for index in a.indices {
            difference |= a[index] ^ b[index]
        }
        return difference == 0
    }

    /// `ct.startsWith('application/json')` on the **untrimmed, case-sensitive** header.
    ///
    /// So `application/jsonp` is accepted — the reference tests a prefix, not equality, and a port
    /// that tightens this to equality-or-`;` rejects a request the reference allows (B21).
    public static func hasJSONContentType(_ request: ControlAPIRequest) -> Bool {
        (request.header("content-type") ?? "").hasPrefix("application/json")
    }
}
