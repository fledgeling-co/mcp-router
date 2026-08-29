import Foundation

/// What a diagnostics export gathers, and what it refuses to gather — R22.
///
/// The brief asks for "recent activity logs, process execution status, and listener state" in one
/// action. The shape of the problem is not the gathering: every fact here is already reachable
/// through some route or file. It is that `servers.json` carries live bearer tokens today, so a
/// convenience that packages the router's state into one document is a convenience that packages
/// its credentials into one document.
///
/// **Layer 1 lives here.** A field whose position makes it secret-bearing is never placed in the
/// value at all — the value is not gathered and then removed, it is not gathered. That is the
/// difference between a document a scrubber has been over and a document that never held the
/// thing. ``SecretRedactor`` is layer 2 and runs afterwards over everything that did survive.
///
/// The precedent is in this repository and is followed rather than reinvented: ``Describe`` emits
/// `envKeys` and `headerKeys` and never a value, "because this endpoint is reachable by anything
/// that can open a loopback socket, and a server's env is where its API keys live" (B10).
public enum DiagnosticsBundle {
    /// The last lines of the router log to carry. Bounded on both counts, because a bundle a person
    /// is going to attach to a bug report has a size past which nobody reads it — and because an
    /// unbounded read of a log file is an unbounded allocation inside the request that asked for it.
    public static let logLineLimit = 500
    public static let logByteLimit = 512 * 1024

    /// How many recent tool calls to carry. `UsageStore`'s own recent-call ring is the same order,
    /// so this is the window the router already keeps rather than a second one.
    public static let usageRecordLimit = 200

    /// What a withheld value is reported as.
    ///
    /// **A bucket, not a character count**, and this is a deliberate departure from
    /// ``ControlTokenStore``'s `redacted(_:)`, which renders a secret as `<39 chars>`. That
    /// rendering is right where it is used: a log line stays on this machine, and a length is the
    /// difference between "the token is there" and "the token is empty", which is the whole
    /// diagnostic value a token has.
    ///
    /// A bundle is different in the one way that matters — it is built expressly to be sent to
    /// somebody else. An exact length is a fingerprint of the credential's *family*: 40 characters
    /// is a GitHub classic token, 51 is an OpenAI key. That tells a reader of the bundle which
    /// vendor to attack and narrows nothing for the person debugging. The bucket keeps the
    /// present-versus-empty distinction and drops the fingerprint.
    public enum ValueShape: String, Sendable, CaseIterable {
        /// The key is declared and its value is the empty string — a real and common misconfiguration.
        case empty
        /// Below ``SecretNeedles/minimumNeedleLength``, so it is also not usable as a scrub needle.
        case short
        case present
    }

    public static func shape(of value: String) -> ValueShape {
        if value.isEmpty { return .empty }
        if value.count < SecretNeedles.minimumNeedleLength { return .short }
        return .present
    }

    /// The log tail, or the reason there is none.
    ///
    /// Not `Result`: an unreadable log is not an error the request failed on, it is one section of
    /// the bundle reporting its own absence. Modelling it as a failure invites a caller to treat
    /// the whole export as failed over a log file that was simply never configured.
    public enum LogTail: Sendable, Hashable {
        case lines([String])
        case unavailable(String)
    }

    /// The log's last lines, oldest first, or the reason there are none.
    ///
    /// A read failure is reported to the caller as an absent section rather than swallowed: a
    /// bundle that silently omits the logs and a bundle from a router that logged nothing are the
    /// same document, and only one of them means what the reader will take it to mean.
    public static func logTail(path: String, fileSystem: any FileSystem) -> LogTail {
        guard fileSystem.fileExists(atPath: path) else {
            return .unavailable("no log file at the configured path")
        }
        let data: Data
        do {
            data = try fileSystem.readFile(atPath: path)
        } catch {
            return .unavailable("\(error)")
        }
        let tail = data.count > logByteLimit ? data.suffix(logByteLimit) : data
        // `String(decoding:as:)` rather than the failable `String(bytes:encoding:)` the linter
        // prefers, and this is the one place in the file where the lossy one is correct: the cut
        // above is a BYTE suffix, so it can land in the middle of a multi-byte codepoint. The
        // failable initialiser returns nil for that and the whole log section disappears — a
        // truncated last character is a better answer than no logs.
        // swiftlint:disable:next optional_data_string_conversion
        let text = String(decoding: tail, as: UTF8.self)
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        // A byte-suffix cut lands mid-line. Dropping the first fragment is the honest move: half a
        // log line reads as a whole one and nothing in the document says it was cut.
        if data.count > logByteLimit, !lines.isEmpty { lines.removeFirst() }
        if lines.last?.isEmpty == true { lines.removeLast() }
        if lines.count > logLineLimit { lines = Array(lines.suffix(logLineLimit)) }
        return .lines(lines)
    }

    /// The URL with its credential half removed and its query values replaced.
    ///
    /// Kept whole otherwise: the host and path are the diagnostic content of a URL, and a bundle
    /// that hides which endpoint an upstream talks to cannot be used to debug the thing it was
    /// exported for. A query **value** is redacted without exception — `?api_key=…` is a shape this
    /// repository has to assume, and no query value is worth the class of leak it opens.
    public static func safeURL(_ url: String) -> String {
        guard let schemeEnd = url.range(of: "://") else { return url }
        let scheme = url[url.startIndex ..< schemeEnd.upperBound]
        var rest = String(url[schemeEnd.upperBound...])

        var fragment = ""
        if let hash = rest.firstIndex(of: "#") {
            fragment = String(rest[hash...])
            rest = String(rest[rest.startIndex ..< hash])
        }
        var query = ""
        if let mark = rest.firstIndex(of: "?") {
            query = String(rest[rest.index(after: mark)...])
            rest = String(rest[rest.startIndex ..< mark])
        }

        var authorityAndPath = rest
        let pathStart = rest.firstIndex(of: "/")
        var authority = String(rest[rest.startIndex ..< (pathStart ?? rest.endIndex)])
        let path = pathStart.map { String(rest[$0...]) } ?? ""
        if let at = authority.lastIndex(of: "@") {
            authority = "<redacted:userinfo>@" + String(authority[authority.index(after: at)...])
            authorityAndPath = authority + path
        }

        guard !query.isEmpty else { return scheme + authorityAndPath + fragment }
        let redacted = query.split(separator: "&", omittingEmptySubsequences: false).map { pair -> String in
            guard let equals = pair.firstIndex(of: "=") else { return String(pair) }
            return String(pair[pair.startIndex ..< equals]) + "=<redacted:query>"
        }
        return scheme + authorityAndPath + "?" + redacted.joined(separator: "&") + fragment
    }
}
