import Foundation
import RouterCore

/// The two streams, kept apart on purpose.
///
/// `src/index.ts` puts some answers on stdout and others on stderr, and the split is not incidental:
/// `cmdStatus` **catches** a failed fetch and writes to stdout with `process.exitCode = 1`, while
/// `cmdUsage` **throws** the same sentence, which `run().catch` writes to stderr behind a
/// `mcp-router: ` prefix. A harness capturing `2>&1` cannot tell those apart, so
/// `scripts/acceptance/parity-cli.sh` compares the two streams separately and this type is what
/// keeps them separable.
enum Out {
    static func print(_ text: String) {
        FileHandle.standardOutput.write(Data(text.utf8))
    }

    static func error(_ text: String) {
        FileHandle.standardError.write(Data(text.utf8))
    }
}

/// Argument parsing, matching the reference's two helpers exactly.
struct Flags {
    private let arguments: [String]

    /// A flag that is present but not a finite number is an **error**, not a silent NaN.
    ///
    /// The reference's own comment says why: `--port abc` would otherwise reach `listen(NaN)`, which
    /// binds an arbitrary ephemeral port — the router comes up looking healthy and no client can
    /// reach it. Exit code 2, and the message goes to stderr.
    init(_ arguments: [String]) throws {
        self.arguments = arguments
    }

    func has(_ name: String) -> Bool {
        arguments.contains("--\(name)")
    }

    func value(_ name: String) -> String? {
        guard let index = arguments.firstIndex(of: "--\(name)"), index + 1 < arguments.count else {
            return nil
        }
        return arguments[index + 1]
    }

    func number(_ name: String) throws -> Int? {
        guard let raw = value(name) else { return nil }
        // `Number(raw)` then `Number.isFinite` — so `" 8879 "` parses, `""` is 0, and `abc` is NaN.
        guard let parsed = Copy.jsNumber(raw), parsed.isFinite else {
            Out.error("--\(name) expects a number, got \"\(raw)\"\n")
            exit(2)
        }
        return Int(parsed)
    }
}

/// Copy and formatting shared by the verbs.
enum Copy {
    /// `String.prototype.padEnd` — pads, never truncates. A server name wider than its column pushes
    /// the row rather than being elided, because a truncated name is unactionable in a terminal.
    static func pad(_ text: String, _ width: Int) -> String {
        text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
    }

    /// `String.prototype.padStart`.
    static func padStart(_ text: String, _ width: Int) -> String {
        text.count >= width ? text : String(repeating: " ", count: width - text.count) + text
    }

    /// How a JavaScript template literal renders one member of an object.
    ///
    /// An **absent** member interpolates as the literal text `undefined`. That is not a curiosity
    /// here: `cmdStatus` reads `c.calls` while `/status` emits `callsServed`, so every running child
    /// the reference prints carries the word `undefined`.
    static func interpolate(_ fields: [JSONMember], _ key: String) -> String {
        guard let value = fields.first(where: { $0.key == JSString(key) })?.value else {
            return "undefined"
        }
        switch value {
        case .null: return "null"
        case let .bool(flag): return flag ? "true" : "false"
        case let .number(number): return JSNumber.string(number)
        case let .string(text): return text.string
        default: return value.jsDisplayString
        }
    }

    /// `Number(raw)`: leading and trailing whitespace is ignored, an empty string is 0, and anything
    /// else that is not fully numeric is NaN. Foundation's `Double(_:)` rejects `" 5 "` and accepts
    /// `"5x"` in some locales, so neither is a substitute.
    static func jsNumber(_ raw: String) -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return 0 }
        return Double(trimmed)
    }

    /// The usage block, byte for byte, including its trailing blank line and its three-path footer.
    static func usage(home: RouterHome) -> String {
        """
        mcp-router — one shared MCP endpoint, upstreams opened on demand

          mcp-router import [--from <path>]   Adopt servers from ~/.claude.json (stdio and http)
          mcp-router index [--force]          Build/refresh the cached tool manifest
          mcp-router serve [--port N] [--idle-ms N] [--verbose]
          mcp-router status [--port N]        Query a running router
          mcp-router tools                    List the namespaced tools served from cache
          mcp-router auth <server>            Authorize an http upstream in your browser
          mcp-router usage [--limit N]        Recent tool calls, with the project that made them
          mcp-router watch [--verbose]        One shot: adopt any new server out of
                                              ~/.claude.json (run by launchd on file change)

        Config:   \(home.configPath)
        Manifest: \(home.manifestPath)
        Token:    \((home.root as NSString).appendingPathComponent("control.token"))

        """
    }
}

/// A minimal loopback HTTP client for the verbs that query a running router.
///
/// Deliberately not `URLSession`: `status` and `usage` must report "no router answering" for a
/// refused connection and for nothing else, and `URLSession`'s error surface makes several
/// unrelated failures look identical to that one. This asks for exactly one thing and returns `nil`
/// when it does not get it.
enum Loopback {
    static func get(port: Int, path: String) async -> JSONValue? {
        await request(
            "GET \(path) HTTP/1.1\r\nHost: 127.0.0.1:\(port)\r\nconnection: close\r\n\r\n",
            port: port
        )
    }

    static func post(port: Int, path: String, token: String) async -> JSONValue? {
        let body = "{}"
        return await request(
            "POST \(path) HTTP/1.1\r\nHost: 127.0.0.1:\(port)\r\n"
                + "authorization: Bearer \(token)\r\ncontent-type: application/json\r\n"
                + "content-length: \(body.utf8.count)\r\nconnection: close\r\n\r\n\(body)",
            port: port
        )
    }

    private static func request(_ text: String, port: Int) async -> JSONValue? {
        guard let raw = await RawLoopbackClient.send(Data(text.utf8), port: port) else { return nil }
        // The body starts after the head. A response with no terminator is not a response.
        guard let range = raw.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        return try? JSONParser.parse(Data(raw[range.upperBound...]))
    }
}
