import Foundation
import Testing
@testable import RouterCore

/// R22 — the diagnostics routes, **through `ControlHandler.handle`**.
///
/// Through the handler rather than by calling the response builders, for the reason
/// `ControlHealthRoutesTests` gives: `D-j` was never a broken function, it was a missing dispatch
/// arm, and a test that calls the builder directly cannot fail when the arm is deleted.
///
/// ## The one thing every assertion here is arranged around
///
/// "The bundle does not contain the secret" is the easiest assertion in this repository to make
/// unfailable. It passes over an empty document, over a route that 404s, over a gatherer that never
/// read the config, and over a redactor that was never called because layer 1 had already dropped
/// the field. So no test below asserts an absence on its own. Each one pairs the absence with:
///
///   * a **public canary** planted beside the secret, which must be PRESENT — proving the section
///     that carried the secret was actually gathered;
///   * the **key name**, which must be PRESENT — proving the pair was reached and a decision was
///     taken about it, rather than the whole server having been skipped;
///   * where layer 2 is the subject, `occurrencesRemoved`, which must be **non-zero** — proving the
///     scrubber had something to do rather than merely having run.
///
/// `planning/test-campaign/bin/arm-r22-diagnostics.sh` then removes each layer in turn and requires
/// the matching test to go red, because an assertion nobody has watched fail is not known to bite.
@Suite("R22 diagnostics routes")
struct ControlDiagnosticsTests {
    typealias Support = ControlAuthSupport

    /// Long enough to clear ``SecretNeedles/minimumNeedleLength`` several times over, and shaped so
    /// no substring of it occurs anywhere else in the document by accident.
    static let secret = "sk-r22-QZ7vN4pLxK9mT2wB8yH3cJ6dF5gS1aE0"
    /// Planted beside the secret in the same log line. Its PRESENCE is what makes the secret's
    /// absence mean something: both fall out together if the log section was never gathered.
    static let canary = "R22-PUBLIC-CANARY-LOG-LINE-REACHED"
    static let logPath = "/router/r.log"

    /// A config carrying the secret in an `env` value, a header value and a URL's userinfo — the
    /// three positions layer 1 is responsible for — plus a short value the needle floor must refuse.
    static func config(
        secret: String = ControlDiagnosticsTests.secret, short: String = "dev"
    ) -> String {
        """
        {
          "mcpServers": {
            "r22-stdio": {
              "command": "/bin/echo",
              "args": ["--mode", "diagnose"],
              "env": { "GITHUB_TOKEN": "\(secret)", "MODE": "\(short)" }
            },
            "r22-http": {
              "url": "https://alice:\(secret)@example.invalid/mcp?api_key=\(secret)",
              "type": "http",
              "headers": { "Authorization": "Bearer \(secret)" }
            }
          }
        }
        """
    }

    static func deps(
        log lines: [String] = [], config configText: String? = nil
    ) throws -> ControlDeps {
        let fileSystem = AuthTestFileSystem()
        if !lines.isEmpty {
            fileSystem.memory.seed(lines.joined(separator: "\n") + "\n", atPath: logPath)
        }
        return try Support.makeDeps(fileSystem: fileSystem, config: configText ?? config())
    }

    static func answer(
        _ path: String, method: String, authorized: Bool = true, _ deps: inout ControlDeps
    ) async -> (status: Int, body: String) {
        var headers = [
            (name: "content-type", value: "application/json")
        ]
        if authorized { headers.append((name: "x-mcpr-token", value: Support.token)) }
        let response = await ControlHandler(token: Support.token).handle(
            ControlAPIRequest(
                method: method, encodedPath: path, query: [], headers: headers,
                body: method == "GET" ? nil : Data("{}".utf8)
            ),
            &deps
        )
        guard case let .bytes(bytes) = response.body else { return (response.status, "") }
        // swiftlint:disable:next optional_data_string_conversion
        return (response.status, String(decoding: bytes, as: UTF8.self))
    }

    // MARK: - CASE-0270 — the bundle carries no configured credential, and is not empty

    @Test("CASE-0270 — every configured secret is absent, and the document that omits it is real")
    func configuredSecretsAreAbsentFromANonEmptyBundle() async throws {
        var deps = try Self.deps(log: ["2026-08-29T00:00:00.000Z info  \(Self.canary)"])
        let answer = await Self.answer("/diagnostics/bundle", method: "POST", &deps)

        #expect(answer.status == 200)
        // The absence. All three positions layer 1 owns, in every form layer 2 knows.
        for form in SecretNeedles.variants(of: Self.secret) {
            #expect(
                answer.body.contains(form) == false,
                "a form of the configured secret reached the bundle"
            )
        }
        // The three proofs that the absence is not vacuous.
        #expect(answer.body.contains(Self.canary), "the log section was never gathered")
        #expect(answer.body.contains("GITHUB_TOKEN"), "the env pair was never reached")
        #expect(answer.body.contains("Authorization"), "the header pair was never reached")
        // And that a decision was taken about the value rather than the field being dropped.
        #expect(answer.body.contains(#""value":"present""#))
    }

    // MARK: - CASE-0271 — layer 2: a secret that reached free text

    @Test("CASE-0271 — a secret quoted back in a log line is removed, and the removal is counted")
    func aSecretInFreeTextIsScrubbed() async throws {
        var deps = try Self.deps(log: [
            "2026-08-29T00:00:00.000Z error upstream refused: bad token \(Self.secret) \(Self.canary)"
        ])
        let answer = await Self.answer("/diagnostics/bundle", method: "POST", &deps)

        #expect(answer.status == 200)
        #expect(answer.body.contains(Self.secret) == false)
        // Layer 1 alone would satisfy the line above — it never places an env value — and would
        // leave this log line untouched. These three are what separate the two layers.
        #expect(answer.body.contains("<redacted:r22-stdio.env.GITHUB_TOKEN>"))
        #expect(answer.body.contains(#""occurrencesRemoved":0"#) == false)
        #expect(answer.body.contains(Self.canary), "the scrubber removed the whole line")
    }

    // MARK: - CASE-0272 — the needle floor

    @Test("CASE-0272 — a value too short to be a needle is named, not used, and not disclosed")
    func theNeedleFloorIsReportedRatherThanApplied() async throws {
        var deps = try Self.deps(log: [
            "2026-08-29T00:00:00.000Z info  started dev-server on port 3000 \(Self.canary)"
        ])
        let answer = await Self.answer("/diagnostics/bundle", method: "POST", &deps)

        #expect(answer.status == 200)
        // Named, with the reason, so a reader knows before sending the bundle on.
        #expect(answer.body.contains("r22-stdio.env.MODE"))
        #expect(answer.body.contains("shorter than 8 characters"))
        #expect(answer.body.contains(#""value":"short""#))
        // Not used as a needle: `dev` occurs inside `dev-server`, and scrubbing it would corrupt
        // the log line while reading as thorough redaction. This is the assertion that fails if
        // somebody removes the floor.
        #expect(answer.body.contains("dev-server on port 3000"))
        #expect(answer.body.contains("<redacted:r22-stdio.env.MODE>") == false)
    }

    // MARK: - CASE-0273 — the encoded forms

    @Test("CASE-0273 — a secret that reached the log encoded is removed in that form too")
    func encodedFormsOfASecretAreScrubbed() async throws {
        let percent = try #require(
            Self.secret.addingPercentEncoding(withAllowedCharacters: .alphanumerics)
        )
        let base64 = Data(Self.secret.utf8).base64EncodedString()
        var deps = try Self.deps(log: [
            "2026-08-29T00:00:00.000Z warn  redirect carried ?t=\(percent) \(Self.canary)",
            "2026-08-29T00:00:01.000Z warn  authorization basic \(base64)"
        ])
        let answer = await Self.answer("/diagnostics/bundle", method: "POST", &deps)

        #expect(answer.status == 200)
        #expect(answer.body.contains(percent) == false, "the percent-encoded form survived")
        #expect(answer.body.contains(base64) == false, "the base64 form survived")
        #expect(answer.body.contains(Self.canary), "the log section was never gathered")
    }

    // MARK: - CASE-0274 — the preview is ungated, so it carries nothing

    @Test("CASE-0274 — the untokened preview reports what would be gathered and none of it")
    func thePreviewDisclosesNothingTheBundleWouldRedact() async throws {
        var deps = try Self.deps(log: [
            "2026-08-29T00:00:00.000Z error bad token \(Self.secret) \(Self.canary)"
        ])
        // No token. `GET` is ungated in this router by design (see `ControlHandler.gate`), which is
        // exactly why the preview may not carry content.
        let answer = await Self.answer("/diagnostics", method: "GET", authorized: false, &deps)

        #expect(answer.status == 200)
        #expect(answer.body.contains(Self.secret) == false)
        // The line that makes this a real constraint rather than a restatement of the one above:
        // the preview carries no log CONTENT at all, secret or not.
        #expect(answer.body.contains(Self.canary) == false, "the preview leaked a log line")
        #expect(answer.body.contains(#""value":"present""#) == false, "the preview leaked a shape")
        // What it does carry: the categories, their counts, and the redaction plan.
        #expect(answer.body.contains(#""category":"routerLog""#))
        #expect(answer.body.contains(#""secretsKnown":4"#))
        #expect(answer.body.contains("POST /diagnostics/bundle"))
    }

    // MARK: - CASE-0275 — the verb is the gate

    @Test("CASE-0275 — the bundle is reachable only by POST, and only with the token")
    func theBundleIsBehindTheTokenGate() async throws {
        var deps = try Self.deps(log: ["2026-08-29T00:00:00.000Z info  \(Self.canary)"])

        let untokened = await Self.answer(
            "/diagnostics/bundle", method: "POST", authorized: false, &deps
        )
        #expect(untokened.status == 401, "the bundle answered without the token")
        #expect(untokened.body.contains(Self.canary) == false)

        // A GET on the bundle path is claimed and unhandled, so it reaches the handler's 405
        // rather than serving the document to an ungated caller.
        let wrongVerb = await Self.answer("/diagnostics/bundle", method: "GET", &deps)
        #expect(wrongVerb.status == 405)
        #expect(wrongVerb.body.contains(Self.canary) == false)

        // And the tokened POST does answer, so the two above are refusals rather than an absent route.
        let allowed = await Self.answer("/diagnostics/bundle", method: "POST", &deps)
        #expect(allowed.status == 200)
        #expect(allowed.body.contains(Self.canary))
    }

    // MARK: - Supporting behaviour

    @Test("R22-a — the URL keeps its host and path and loses its userinfo and query values")
    func urlIsSanitisedStructurally() async throws {
        var deps = try Self.deps()
        let answer = await Self.answer("/diagnostics/bundle", method: "POST", &deps)

        #expect(answer.body.contains("example.invalid/mcp"), "the endpoint was lost")
        #expect(answer.body.contains("<redacted:userinfo>@example.invalid"))
        #expect(answer.body.contains("api_key=<redacted:query>"))
        #expect(answer.body.contains("alice:") == false)
    }

    @Test("R22-b — an unreadable log is reported as unavailable, not as an empty log")
    func anAbsentLogSaysSoRatherThanReadingEmpty() async throws {
        var deps = try Self.deps()
        let answer = await Self.answer("/diagnostics/bundle", method: "POST", &deps)

        #expect(answer.body.contains(#""available":false"#))
        #expect(answer.body.contains("no log file at the configured path"))
        // A router that logged nothing and a router whose log could not be read must not produce
        // the same document.
        #expect(answer.body.contains(#""lines":0"#) == false)
    }

    @Test("R22-c — the home directory is elided from every path in the document")
    func homePathsAreElided() {
        let home = RouterHome.resolvedHomeDirectory()
        let elision = HomePathElision(home: home)
        #expect(elision.elide("\(home)/.claude/mcp-router/servers.json")
            == "~/.claude/mcp-router/servers.json")
        // A root or empty home disables the pass rather than rewriting every absolute path to `~`.
        #expect(HomePathElision(home: "/").elide("/usr/bin/node") == "/usr/bin/node")
        #expect(HomePathElision(home: "").elide("/usr/bin/node") == "/usr/bin/node")
    }

    @Test("R22-d — a needle that is a substring of another does not truncate the longer redaction")
    func longerNeedlesAreReplacedFirst() {
        let needles = SecretNeedles(
            needles: [
                SecretNeedles.Needle(label: "short", literal: "abcdefgh"),
                SecretNeedles.Needle(label: "long", literal: "abcdefghijklmnop")
            ],
            unscrubbable: []
        )
        let redacted = SecretRedactor(needles: needles).redact("value=abcdefghijklmnop end")
        #expect(redacted == "value=<redacted:long> end")
        // The failure this guards: replacing `short` first leaves `ijklmnop` in the text beside a
        // redaction marker, which reads as a successful redaction of the whole thing.
        #expect(redacted.contains("ijklmnop") == false)
    }

    @Test("R22-f — a secret used as an env KEY does not escape through the redaction block")
    func theRedactionBlockIsScrubbedToo() async throws {
        // `s1` holds the secret as a VALUE, which makes it a needle. `s2` names an env key with
        // that same literal and gives it a value below the floor — so the key path lands in
        // `unscrubbable`, which is built AFTER the document has been scrubbed and appended to it.
        //
        // This is the shape a reviewer named as a leak vector: layer 2 keeps object keys and
        // redacts values, so a credential written into a key name survives unless the pass reads
        // keys too. It does everywhere in the gathered document — and the redaction block is not
        // part of that document, so appending it raw would reopen the hole at the last line.
        let config = """
        {
          "mcpServers": {
            "s1": { "command": "/bin/echo", "env": { "TOKEN": "\(Self.secret)" } },
            "s2": { "command": "/bin/echo", "env": { "\(Self.secret)": "dev" } }
          }
        }
        """
        var deps = try Self.deps(
            log: ["2026-08-29T00:00:00.000Z info  \(Self.canary)"], config: config
        )
        let answer = await Self.answer("/diagnostics/bundle", method: "POST", &deps)

        #expect(answer.status == 200)
        #expect(answer.body.contains(Self.secret) == false, "the secret escaped through a key path")
        // Non-vacuous: the block really is present and really does name that pair, so the absence
        // above is a redaction rather than a section that was never built.
        #expect(answer.body.contains("shorter than 8 characters"))
        #expect(answer.body.contains("<redacted:s1.env.TOKEN>"))
        #expect(answer.body.contains(Self.canary))
    }

    @Test("R22-e — the control token is a needle, so the router cannot leak its own key")
    func theControlTokenIsScrubbed() {
        let needles = SecretNeedles.collect(
            config: RouterConfig(
                port: 1, host: "127.0.0.1", idleMs: 1, startupTimeoutMs: 1, upstreams: [],
                manifestPath: "/m", logPath: "/l", usagePath: "/u", statsPath: "/s", authDir: "/a"
            ),
            controlToken: "control-token-long-enough"
        )
        #expect(needles.needles.contains { $0.label == "control.token" })
        let out = SecretRedactor(needles: needles)
            .redact("authorization: Bearer control-token-long-enough")
        #expect(out == "authorization: Bearer <redacted:control.token>")
    }
}
