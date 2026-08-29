import Foundation

/// Layer 2 of R22's redaction: remove every known secret value from every string that survived
/// layer 1, wherever it ended up.
///
/// Layer 1 lives in ``DiagnosticsBundle`` and is structural — an `env` value, a header value or a
/// URL's userinfo is never *placed* in the document at all, so no key name a config invents can
/// smuggle one through. That is the strong half and it covers the config.
///
/// It does not cover the rest of the bundle. A credential reaches a diagnostics export by more
/// routes than the field it was configured in: an upstream that rejects a call and quotes the token
/// back in its error text, a command line that carries `--token=…`, a log line somebody wrote by
/// hand. Those are strings the bundle has every reason to carry, and the only thing that
/// distinguishes the secret inside one is its **value**. So this pass knows values.
///
/// **It runs over the value tree, once, as the last step** — see ``redact(_:)``. Applying it at
/// each site that appends a string would make the guarantee depend on nobody forgetting; applying
/// it to the finished tree makes it depend on nothing. Object **keys** are scrubbed as well as
/// string values, because a config is free to put a token in a key.
///
/// It runs before serialisation rather than over the serialised bytes, which is what lets the
/// needle set stay small: at tree level every string is still unescaped, so a token containing a
/// quote is present as itself rather than as `\"`.
public struct SecretRedactor: Sendable {
    /// One replaceable form of one needle, longest first.
    private struct Form {
        let text: String
        let label: String
    }

    private let forms: [Form]
    public let needles: SecretNeedles

    public init(needles: SecretNeedles) {
        self.needles = needles
        // Longest first. A short needle that is a substring of a long one would otherwise be
        // replaced inside it, leaving the remainder of the longer secret in the text with a
        // redaction marker in the middle of it — which reads as a successful redaction.
        forms = needles.needles
            .flatMap { needle in
                SecretNeedles.variants(of: needle.literal)
                    .map { Form(text: $0, label: needle.label) }
            }
            .sorted { $0.text.count > $1.text.count }
    }

    /// How many occurrences the last ``redact(_:)`` removed, and from how many distinct secrets.
    ///
    /// Reported in the bundle. A count is the difference between "this pass ran" and "this pass had
    /// something to do", and the two are not the same claim: a bundle whose free text happened to
    /// contain no secret and a bundle built by a scrubber that was never called both read clean.
    public struct Tally: Sendable, Hashable {
        public var occurrences = 0
        public var labels: Set<String> = []

        public init() {}
    }

    /// Replace every form of every needle throughout `value`, in strings and in object keys.
    public func redact(_ value: JSONValue) -> (JSONValue, Tally) {
        var tally = Tally()
        let scrubbed = walk(value, &tally)
        return (scrubbed, tally)
    }

    /// The text of one string with every needle removed.
    public func redact(_ text: String) -> String {
        var tally = Tally()
        return scrub(text, &tally)
    }

    private func walk(_ value: JSONValue, _ tally: inout Tally) -> JSONValue {
        switch value {
        case let .string(text):
            .string(JSString(scrub(text.string, &tally)))
        case let .array(items):
            .array(items.map { walk($0, &tally) })
        case let .object(members):
            .object(members.map { member in
                JSONMember(
                    key: JSString(scrub(member.key.string, &tally)),
                    value: walk(member.value, &tally)
                )
            })
        case .null, .bool, .number:
            value
        }
    }

    private func scrub(_ text: String, _ tally: inout Tally) -> String {
        guard !forms.isEmpty else { return text }
        var out = text
        for form in forms where !form.text.isEmpty {
            guard out.contains(form.text) else { continue }
            var hits = 0
            var rebuilt = ""
            var cursor = out.startIndex
            while let found = out.range(of: form.text, range: cursor ..< out.endIndex) {
                rebuilt += out[cursor ..< found.lowerBound]
                rebuilt += "<redacted:\(form.label)>"
                cursor = found.upperBound
                hits += 1
            }
            rebuilt += out[cursor...]
            out = rebuilt
            tally.occurrences += hits
            tally.labels.insert(form.label)
        }
        return out
    }
}

/// Layer 3: the operator's own account name, which is in every absolute path this router holds.
///
/// A bundle is written to be sent to somebody else, and `/Users/alice/Library/…` names a person as
/// surely as an email address does. The substitution is the one every shell already understands, so
/// a reader loses nothing they were going to use.
///
/// It is a **separate pass from ``SecretRedactor``** rather than a fourth needle, because it is a
/// different promise: a home path is not a credential and conflating the two would let a run that
/// satisfied one report that it had satisfied the other.
public struct HomePathElision: Sendable {
    private let home: String

    /// `home` is the absolute home directory, without a trailing slash. An empty or `/` home
    /// disables the pass rather than rewriting every path in the document to `~`.
    public init(home: String) {
        var trimmed = home
        while trimmed.count > 1, trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        self.home = (trimmed == "/" || trimmed.isEmpty) ? "" : trimmed
    }

    public func elide(_ value: JSONValue) -> JSONValue {
        guard !home.isEmpty else { return value }
        switch value {
        case let .string(text):
            return .string(JSString(elide(text.string)))
        case let .array(items):
            return .array(items.map(elide))
        case let .object(members):
            return .object(members.map {
                JSONMember(key: $0.key, value: elide($0.value))
            })
        case .null, .bool, .number:
            return value
        }
    }

    public func elide(_ text: String) -> String {
        guard !home.isEmpty else { return text }
        return text.replacingOccurrences(of: home, with: "~")
    }
}
