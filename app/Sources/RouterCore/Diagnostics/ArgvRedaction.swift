import Foundation

/// The argv half of R22's scrub, applied to `GET /servers` before it serialises each upstream's args
/// (DEF-070).
///
/// `GET /servers` is not token-gated, so anything that can open a loopback socket reads every
/// stdio upstream's `args`. An argument list is a credential channel: `--token=…`, `--api-key …` and
/// a connection string with an inline password are each the one place a config writer had to put a
/// secret. Structural withholding does not reach this, because a flag's name is the key here and
/// the value is not a field anyone can leave out. So this pass reads the shape of each argument, and
/// then removes any literal the router knows (``SecretNeedles``), as the diagnostics bundle does.
///
/// The rules, applied to each argument in order. `src/secrets.ts` implements the same rules with
/// the same replacement strings, and `Vectors/argv-redact.json` is read by both suites, so a rule
/// changed in one language and not the other fails both.
///
/// 1. A value consumed by a secret-named flag is replaced. `--name=value` keeps its name and loses
///    its value. `--name value` loses the next argument, unless that argument is itself a flag
///    (`--…`), in which case the first flag stood alone. A non-string value is replaced too, since a
///    number can be a secret.
/// 2. `NAME=value` with a secret-named `NAME` loses its value.
/// 3. In a URL the password is replaced and the user kept. A userinfo with no password is replaced
///    whole, because `https://<token>@host` carries the token in the user position.
/// 4. A query parameter with a secret-named key loses its value.
/// 5. Every literal needle is replaced with ``SecretRedactor``'s `<redacted:LABEL>`.
///
/// A name is secret-named when one of its segments, split on `-`, `_` or `.`, is in
/// ``secretSegments``. That is wide on purpose: `--sort-key=name` is redacted. An over-redaction
/// shows in place as `<redacted>`, and an under-redaction does not show at all.
public enum ArgvRedaction {
    /// What a structural rule writes in place of a value. A needle match writes `<redacted:LABEL>`
    /// instead, so the reader can see which config key the value came from.
    public static let replacement = "<redacted>"

    /// The name segments that mark a value as a secret.
    public static let secretSegments: Set<String> = [
        "token", "tokens", "secret", "secrets", "password", "passwd", "pass", "pwd", "key", "apikey",
        "auth", "authorization", "bearer", "credential", "credentials", "cookie", "cookies"
    ]

    /// An `args` member as the reference serialises it, with its element types kept. A string is
    /// treated as one argument; any other non-array value is passed through untouched.
    public static func redact(_ args: JSONValue, with scrubber: SecretRedactor) -> JSONValue {
        switch args {
        case let .array(items):
            .array(pipeline(items, scrubber))
        case .string:
            pipeline([args], scrubber)[0]
        default:
            args
        }
    }

    /// Whether a flag or parameter name marks its value as a secret.
    static func isSecretName(_ name: String) -> Bool {
        name.lowercased()
            .split(whereSeparator: { $0 == "-" || $0 == "_" || $0 == "." })
            .contains { secretSegments.contains(String($0)) }
    }

    private static func pipeline(_ items: [JSONValue], _ scrubber: SecretRedactor) -> [JSONValue] {
        var out: [JSONValue] = []
        // Set by a secret-named flag written without `=`: the next argument is its value.
        var valueNext = false
        for item in items {
            guard case let .string(text) = item else {
                // A non-string is never a flag, so it can only be the value a flag asked for.
                out.append(valueNext ? .string(JSString(replacement)) : item)
                valueNext = false
                continue
            }
            let arg = text.string
            if valueNext {
                valueNext = false
                if !arg.hasPrefix("--") {
                    out.append(.string(JSString(replacement)))
                    continue
                }
            }
            if let groups = firstMatch(of: flagAssign, in: arg), isSecretName(groups[2]) {
                out.append(.string(JSString("\(groups[1])\(groups[2])=\(replacement)")))
            } else if let groups = firstMatch(of: flagBare, in: arg), isSecretName(groups[1]) {
                out.append(item)
                valueNext = true
            } else if let groups = firstMatch(of: envAssign, in: arg), isSecretName(groups[1]) {
                out.append(.string(JSString("\(groups[1])=\(replacement)")))
            } else {
                out.append(.string(JSString(scrubText(arg, scrubber))))
            }
        }
        return out
    }

    /// Rules 3, 4 and 5, in that order: the structural URL and query rules first, then the needles,
    /// so a needle that is itself the password is already gone when the needle pass reads it.
    private static func scrubText(_ text: String, _ scrubber: SecretRedactor) -> String {
        let withoutPassword = replacingMatches(of: userinfo, in: text) { groups in
            let userinfoText = groups[1]
            guard !userinfoText.isEmpty else { return "://@" }
            guard let colon = userinfoText.firstIndex(of: ":") else {
                return "://\(replacement)@"
            }
            return "://\(userinfoText[..<colon]):\(replacement)@"
        }
        let withoutQueryValue = replacingMatches(of: queryParameter, in: withoutPassword) { groups in
            isSecretName(groups[2]) ? "\(groups[1])\(groups[2])=\(replacement)" : groups[0]
        }
        return scrubber.redact(withoutQueryValue)
    }

    // The patterns are built per call. `NSRegularExpression` is not `Sendable`, so a stored one
    // would not compile under the Swift 6 language mode this target builds in.

    /// `--name=value` or `-name=value`. The value may contain `=` and newlines.
    private static let flagAssign = #"^(--?)([A-Za-z0-9][A-Za-z0-9._-]*)=([\s\S]*)$"#
    /// `--name` or `-name` standing alone.
    private static let flagBare = #"^--?([A-Za-z0-9][A-Za-z0-9._-]*)$"#
    /// `NAME=value`, as an environment assignment passed as an argument.
    private static let envAssign = #"^([A-Za-z_][A-Za-z0-9_]*)=([\s\S]*)$"#
    /// Everything between `://` and the last `@` of the authority, which is where userinfo ends.
    private static let userinfo = #"://([^/?#\s]*)@"#
    /// A query parameter: its separator, its key and its value.
    private static let queryParameter = #"([?&])([A-Za-z0-9._-]+)=([^&#\s]*)"#

    private static func firstMatch(of pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: fullRange(of: text))
        else { return nil }
        return groups(of: match, in: text)
    }

    /// Replaces each match, left to right and without overlap, the way a global JavaScript
    /// `replace` does. `src/secrets.ts` relies on that agreement.
    private static func replacingMatches(
        of pattern: String, in text: String, _ transform: ([String]) -> String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let source = text as NSString
        var out = ""
        var cursor = 0
        for match in regex.matches(in: text, range: fullRange(of: text)) {
            out += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            out += transform(groups(of: match, in: text))
            cursor = match.range.location + match.range.length
        }
        return out + source.substring(from: cursor)
    }

    private static func groups(of match: NSTextCheckingResult, in text: String) -> [String] {
        let source = text as NSString
        return (0 ..< match.numberOfRanges).map { source.substring(with: match.range(at: $0)) }
    }

    private static func fullRange(of text: String) -> NSRange {
        NSRange(location: 0, length: (text as NSString).length)
    }
}
