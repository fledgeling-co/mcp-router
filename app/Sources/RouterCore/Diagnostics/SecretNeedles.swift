import Foundation

/// The set of literal secret values a diagnostics bundle must not carry out of this machine — R22.
///
/// This is the *needle* half of the two-layer redaction in ``SecretRedactor``. Layer 1 is
/// structural: a field whose position makes it secret-bearing never has its value emitted at all,
/// so it cannot be evaded by an unexpected key name. Layer 2 is this one: every literal value the
/// router can name as a secret is scrubbed out of every string that *did* survive, so it cannot be
/// evaded by an unexpected **location** — a token echoed back inside an upstream's error message,
/// pasted into a log line, or passed on a command line.
///
/// **A deny-list of key names was the alternative and it is the wrong shape.** `env` blocks in this
/// repository carry `GITHUB_TOKEN` and `NOTION_SECRET`, which a name list catches, and they equally
/// carry names a list cannot predict; W1/W2 inventoried 13 credentials across 9 configs and the
/// naming is not a convention anyone agreed to. A list that is wrong is worse than no list, because
/// it reports thorough redaction while a value walks out under a name nobody thought of.
public struct SecretNeedles: Sendable {
    /// One value to remove, and the key it was found under. The key travels with it so the
    /// replacement can say where the removed text came from — `<redacted:GITHUB_TOKEN>` — which is
    /// what makes an over-redaction auditable rather than a hole in the text.
    public struct Needle: Sendable, Hashable {
        public let label: String
        public let literal: String

        public init(label: String, literal: String) {
            self.label = label
            self.literal = literal
        }
    }

    /// A value the router knows is a secret and **cannot use as a needle**, with the reason.
    ///
    /// Reported by key name in the bundle rather than dropped silently. Layer 1 still withholds it,
    /// so this is not a disclosure — it is the statement that one particular value was not scrubbed
    /// out of free text, which a reader of the bundle is entitled to know before sending it on.
    public struct Unscrubbable: Sendable, Hashable {
        public let label: String
        public let reason: String

        public init(label: String, reason: String) {
            self.label = label
            self.reason = reason
        }
    }

    /// The shortest value that may be used as a scrub needle.
    ///
    /// **The floor is a correctness rule, not a performance one.** An `env` value of `1`, `true` or
    /// `dev` used as a needle would delete every occurrence of that text from every log line in the
    /// bundle — the timestamps, the port numbers, the word `device`. The result reads as thorough
    /// redaction and is a corrupted document, and nobody looking at it can tell which. Eight is the
    /// length below which a value is more likely to be a flag than a credential; every token this
    /// repository's configs actually carry is far above it.
    ///
    /// Both out-of-family reviewers proposed an entropy filter on top of the floor, to keep a value
    /// like `production` from scrubbing that word out of the logs. It is **not** implemented, and
    /// the reason is the direction of the error: an over-redaction announces itself in place, as
    /// `<redacted:MODE>`, and a reader can see exactly what happened and why. An under-redaction is
    /// silent. A second exclusion rule, tuned by entropy, moves values from the first class to the
    /// second on a judgement nobody can audit from the bundle.
    public static let minimumNeedleLength = 8

    public let needles: [Needle]
    public let unscrubbable: [Unscrubbable]

    public init(needles: [Needle], unscrubbable: [Unscrubbable]) {
        self.needles = needles
        self.unscrubbable = unscrubbable
    }

    /// Everything this router can name as a secret, from the config it loaded and the token that
    /// gates its own control API.
    ///
    /// `auth` records are **not** read here and that is a declared gap rather than an oversight:
    /// ``AuthStore`` exposes `hasTokens` and `authorizedAt` and no way to read a token's value, so
    /// an access token minted after this config was written has no needle. Layer 1 still withholds
    /// every stored auth value, because the bundle never reads the auth directory at all — the gap
    /// is a token *reflected back by an upstream into an error string*, recorded in
    /// `planning/specs/spec-R22.md` §6 as residual rather than claimed closed.
    public static func collect(config: RouterConfig, controlToken: String) -> SecretNeedles {
        collect(upstreams: config.upstreams, controlToken: controlToken)
    }

    /// The same set as ``collect(config:controlToken:)``, from the upstreams a caller holds. The
    /// control API passes its live upstream map here, so a reload is reflected without re-reading
    /// the config file (DEF-070).
    public static func collect(upstreams: [UpstreamConfig], controlToken: String) -> SecretNeedles {
        var needles: [Needle] = []
        var unscrubbable: [Unscrubbable] = []

        func consider(label: String, value: String) {
            if value.isEmpty {
                unscrubbable.append(Unscrubbable(label: label, reason: "empty"))
            } else if value.count < minimumNeedleLength {
                unscrubbable.append(Unscrubbable(
                    label: label,
                    reason: "shorter than \(minimumNeedleLength) characters; "
                        + "scrubbing it from free text would corrupt the bundle"
                ))
            } else {
                needles.append(Needle(label: label, literal: value))
            }
        }

        for upstream in upstreams {
            for pair in upstream.env {
                consider(label: "\(upstream.name).env.\(pair.key.string)", value: pair.value.string)
            }
            for pair in upstream.headers {
                consider(
                    label: "\(upstream.name).headers.\(pair.key.string)", value: pair.value.string
                )
            }
            if let url = upstream.url, let userinfo = URLUserinfo.secret(in: url) {
                consider(label: "\(upstream.name).url.userinfo", value: userinfo)
            }
        }
        consider(label: "control.token", value: controlToken)

        return SecretNeedles(needles: needles, unscrubbable: unscrubbable)
    }

    /// The forms of one needle that must all be removed.
    ///
    /// A secret does not always reach a log line as itself. It reaches it percent-encoded when it
    /// travelled in a URL, and base64-encoded when it travelled in a `Basic` credential — and a
    /// scrubber that only knows the literal reports a clean bundle over both.
    ///
    /// **JSON escaping is deliberately not a fourth variant**, which is where this departs from
    /// both out-of-family reviews. They are right that a token containing `"` appears in the
    /// *serialised* document as `\"` and would survive a needle search over the finished bytes.
    /// ``SecretRedactor`` does not search the finished bytes: it walks the value tree before
    /// serialisation, where every string is still unescaped, so the escaping has not happened yet.
    /// Scrubbing earlier removes the whole class rather than enumerating its members.
    static func variants(of literal: String) -> [String] {
        var forms = [literal]
        let allowed = CharacterSet.alphanumerics
        if let encoded = literal.addingPercentEncoding(withAllowedCharacters: allowed),
           encoded != literal
        {
            forms.append(encoded)
        }
        let base64 = Data(literal.utf8).base64EncodedString()
        if base64 != literal { forms.append(base64) }
        return forms
    }
}

/// Pulling the credential half out of a URL without parsing the rest of it.
enum URLUserinfo {
    /// The password in `scheme://user:password@host/…`, or nil.
    ///
    /// `URLComponents` is not used: it rejects a URL whose userinfo carries a character it
    /// considers illegal, and a config carrying exactly that is the one whose password most needs
    /// removing. The authority section is split by hand for that reason.
    static func secret(in url: String) -> String? {
        guard let schemeEnd = url.range(of: "://") else { return nil }
        let rest = url[schemeEnd.upperBound...]
        let authorityEnd = rest.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" })
        let authority = rest[rest.startIndex ..< (authorityEnd ?? rest.endIndex)]
        guard let at = authority.lastIndex(of: "@") else { return nil }
        let userinfo = authority[authority.startIndex ..< at]
        guard let colon = userinfo.firstIndex(of: ":") else { return nil }
        let password = userinfo[userinfo.index(after: colon)...]
        return password.isEmpty ? nil : String(password)
    }
}
