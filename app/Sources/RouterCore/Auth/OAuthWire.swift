import Foundation

/// The bytes an OAuth request is made of: percent-encoding, query serialization, and the URL
/// arithmetic the reference performs with `new URL(reference, base)`.
///
/// The encoder is **`URLSearchParams`'**, not `URLComponents`'. Every authorization URL and every
/// token body in the reference is built by setting search parameters, and that serializer encodes
/// `:` and `/`, renders a space as `+`, and leaves only ASCII alphanumerics plus `*-._` alone.
/// `addingPercentEncoding(withAllowedCharacters:)` produces a different string from the same input
/// for any of Foundation's stock sets — `redirect_uri` alone carries three characters they disagree
/// about, and the difference is on the wire in the one field this route returns.
public enum OAuthWire {
    /// The complement of the WHATWG `application/x-www-form-urlencoded` percent-encode set:
    /// ASCII alphanumerics, `*`, `-`, `.` and `_`. Everything else is percent-encoded, and U+0020
    /// becomes `+` rather than `%20`.
    private static let unencoded: Set<UInt8> = {
        var set = Set<UInt8>()
        for byte in UInt8(ascii: "0") ... UInt8(ascii: "9") {
            set.insert(byte)
        }
        for byte in UInt8(ascii: "A") ... UInt8(ascii: "Z") {
            set.insert(byte)
        }
        for byte in UInt8(ascii: "a") ... UInt8(ascii: "z") {
            set.insert(byte)
        }
        set.formUnion([UInt8(ascii: "*"), UInt8(ascii: "-"), UInt8(ascii: "."), UInt8(ascii: "_")])
        return set
    }()

    private static let hexDigits: [Character] = Array("0123456789ABCDEF")

    /// One value, serialized as `URLSearchParams` serializes it.
    public static func encode(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.utf8.count)
        for byte in text.utf8 {
            if unencoded.contains(byte) {
                out.append(Character(UnicodeScalar(byte)))
            } else if byte == 0x20 {
                out.append("+")
            } else {
                out.append("%")
                out.append(hexDigits[Int(byte >> 4)])
                out.append(hexDigits[Int(byte & 0x0F)])
            }
        }
        return out
    }

    /// `pairs.map(k=v).join('&')` — the order given is the order on the wire, which is why this
    /// takes an array and not a dictionary.
    public static func query(_ pairs: [(name: String, value: String)]) -> String {
        pairs.map { "\(encode($0.name))=\(encode($0.value))" }.joined(separator: "&")
    }

    /// `new URL(reference, base).toString()`.
    ///
    /// Nil when either side will not parse, which the callers turn into the same failure the
    /// reference's `new URL` throw produces rather than into a silent fallback.
    public static func resolve(_ reference: String, against base: String) -> String? {
        guard let baseURL = URL(string: base) else { return nil }
        return URL(string: reference, relativeTo: baseURL)?.absoluteURL.absoluteString
    }

    /// `url.origin` — scheme, host and, when it is not the scheme's default, port.
    public static func origin(of url: String) -> String? {
        guard
            let components = URLComponents(string: url),
            let scheme = components.scheme,
            let host = components.host
        else { return nil }
        guard let port = components.port else { return "\(scheme)://\(host)" }
        return "\(scheme)://\(host):\(port)"
    }

    /// `url.pathname`. An empty path is `/`, as it is in JavaScript — `URLComponents` reports it
    /// as the empty string, and the difference decides whether path-aware discovery runs at all.
    public static func pathname(of url: String) -> String {
        guard let components = URLComponents(string: url) else { return "/" }
        let path = components.percentEncodedPath
        return path.isEmpty ? "/" : path
    }

    /// `url.search` — the query with its leading `?`, or the empty string.
    public static func search(of url: String) -> String {
        guard
            let components = URLComponents(string: url),
            let query = components.percentEncodedQuery
        else { return "" }
        return "?\(query)"
    }

    /// `checkResourceAllowed`: same origin, and the requested path is the configured path or a
    /// subpath of it. Both are compared with a trailing slash appended so `/api123` is not read as
    /// a subpath of `/api`.
    public static func resourceAllowed(requested: String, configured: String) -> Bool {
        guard
            let requestedOrigin = origin(of: requested),
            let configuredOrigin = origin(of: configured),
            requestedOrigin == configuredOrigin
        else { return false }
        let requestedPath = pathname(of: requested)
        let configuredPath = pathname(of: configured)
        guard requestedPath.count >= configuredPath.count else { return false }
        let left = requestedPath.hasSuffix("/") ? requestedPath : requestedPath + "/"
        let right = configuredPath.hasSuffix("/") ? configuredPath : configuredPath + "/"
        return left.hasPrefix(right)
    }

    /// `extractFieldFromWwwAuth(response, field)` for the Bearer challenge: the quoted form first,
    /// then the bare form, and only when the header is a `Bearer` challenge with a scheme after it.
    public static func wwwAuthenticateField(_ name: String, in header: String) -> String? {
        let parts = header.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].lowercased() == "bearer", !parts[1].isEmpty else {
            return nil
        }
        guard let start = header.range(of: "\(name)=") else { return nil }
        let rest = header[start.upperBound...]
        if rest.hasPrefix("\"") {
            let quoted = rest.dropFirst()
            guard let end = quoted.firstIndex(of: "\"") else { return nil }
            let value = String(quoted[quoted.startIndex ..< end])
            return value.isEmpty ? nil : value
        }
        let value = String(rest.prefix { $0 != " " && $0 != "," })
        return value.isEmpty ? nil : value
    }
}
