import Foundation
import Testing
@testable import RouterCore

/// A `PATCH` body that is a bare primitive — the input that kills the reference.
///
/// The reference gates every field on `'projects' in b`, having produced `b` with `body ?? {}`. The
/// coalesce is **nullish**, so `null` and an absent body become `{}` and an array passes through as
/// an object; all three reach `in` legally. A primitive does not. `'projects' in 42` is a
/// `TypeError` in V8, it is thrown inside an async request handler that nothing wraps, and the
/// **process exits**.
///
/// Measured against the running reference on 2026-08-14, not inferred — `scripts/` has the harness:
///
/// ```
/// PATCH /servers/s1  42      http=000  PROCESS-DIED  TypeError: Cannot use 'in' operator …in 42
/// PATCH /servers/s1  "hi"    http=000  PROCESS-DIED  TypeError: Cannot use 'in' operator …in hi
/// PATCH /servers/s1  true    http=000  PROCESS-DIED  TypeError: Cannot use 'in' operator …in true
/// PATCH /servers/s1  [1,2]   http=200  ALIVE
/// PATCH /servers/s1  null    http=200  ALIVE
/// POST  /servers     42      http=400  ALIVE         {"error":"name is required"}
/// ```
///
/// This port answers 400 rather than dying. That is a **deliberate divergence**, in the same family
/// as D1's refusal to perform the config-destroying write the reference performs: reproducing a
/// remote-kill would be porting a denial of service into the replacement. It is asserted here and
/// named in the differential harness so it can never decay into an accidental divergence.
///
/// The last row is the boundary of the refusal, and the reason `bodyObject` was left alone: `POST`
/// only *reads a property*, and `(42).name` is `undefined` in JavaScript rather than an error. A
/// port that refused every primitive body would answer 400 `Cannot use 'in' operator` where the
/// reference answers 400 `name is required` — a different body, and a new divergence introduced by
/// the fix for this one.
@Suite("A primitive PATCH body")
struct PrimitiveBodyTests {
    private func withConfig(_ body: (String) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("primitive-body-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("servers.json").path
        try Data(#"{"mcpServers":{"s1":{"command":"/bin/echo"}}}"#.utf8)
            .write(to: URL(fileURLWithPath: path))
        try body(path)
    }

    private func patch(_ rawBody: String, configPath: String) async throws -> ControlAPIResponse {
        let parsed = try JSONParser.parse(#"{"mcpServers":{"s1":{"command":"/bin/echo"}}}"#)
        let entries = parsed.member("mcpServers")?.asObjectMembers ?? []
        var upstreams: [(name: JSString, upstream: UpstreamConfig)] = []
        for entry in entries {
            guard case let .upstream(upstream) = ServerParser.parse(
                name: entry.key.string, raw: entry.value
            ) else { continue }
            upstreams.append((entry.key, upstream))
        }
        var deps = try PortIdentityTests.deps(upstreams: upstreams)
        deps.configPath = configPath

        let request = ControlAPIRequest(
            method: "PATCH",
            encodedPath: "/servers/s1",
            query: [],
            headers: [
                (name: "x-mcpr-token", value: "t"),
                (name: "content-type", value: "application/json")
            ],
            body: Data(rawBody.utf8)
        )
        return await ControlHandler(token: "t").handle(request, &deps)
    }

    /// Red without the refusal: `bodyObject` reported no members for a primitive, so every field
    /// was simply absent, nothing was edited, and the handler answered **200** with the described
    /// row — a silent success where the reference is a fatal error.
    @Test(
        "a primitive body is refused rather than silently succeeding",
        arguments: [
            ("42", "42"),
            (#""hi""#, "hi"),
            ("true", "true"),
            ("-0.5", "-0.5"),
            ("1e21", "1e+21")
        ]
    )
    func primitiveIsRefused(_ input: String, _ rendered: String) throws {
        try withConfig { path in
            let response = try runBlocking { try await patch(input, configPath: path) }
            #expect(response.handled, "the path is owned, so the refusal is still a handled reply")
            #expect(
                response.status == 400,
                "a primitive body answered \(response.status); the reference cannot answer at all"
            )
            guard case let .bytes(bytes) = response.body else {
                Issue.record("the refusal produced a stream")
                return
            }
            let text = String(bytes: bytes, encoding: .utf8) ?? ""
            // The reference's own TypeError text, so R4's parity gate can see which divergence
            // this is rather than meeting an unattributed 400.
            #expect(
                text == #"{"error":"Cannot use 'in' operator to search for 'projects' in \#(rendered)"}"#,
                "unexpected refusal body: \(text)"
            )
        }
    }

    /// The other half of the contract. These three are *not* refused, because the reference handles
    /// all three without throwing — a refusal here would be a divergence invented by this fix.
    @Test(
        "null, an array and an object body are all still applied",
        arguments: ["null", "[1,2]", #"{"warm":true}"#]
    )
    func usableBodiesStillApply(_ input: String) throws {
        try withConfig { path in
            let response = try runBlocking { try await patch(input, configPath: path) }
            #expect(
                response.status == 200,
                "\(input) answered \(response.status); the reference answers 200"
            )
        }
    }

    /// `null` reaching `in` is the case the nullish coalesce catches, and the one a `!= nil` port
    /// would get wrong in the opposite direction — refusing where the reference proceeds.
    @Test("the disposition splits exactly where the `in` operator does")
    func dispositionBoundary() {
        func disposition(_ raw: String?) -> ControlAPIRequest.BodyDisposition {
            ControlAPIRequest(
                method: "PATCH", encodedPath: "/servers/s1", query: [], headers: [],
                body: raw.map { Data($0.utf8) }
            ).bodyDisposition
        }
        for usable in ["null", "[1,2]", "{}", #"{"warm":1}"#, "{ not json", nil] {
            guard case .usable = disposition(usable) else {
                Issue.record("\(usable ?? "<absent>") was refused; the reference applies `in` to it")
                continue
            }
        }
        for primitive in ["42", #""hi""#, "true", "false", "0", #""""#] {
            guard case .primitive = disposition(primitive) else {
                Issue.record("\(primitive) was accepted; the reference throws on it")
                continue
            }
        }
    }

    /// Swift Testing runs async tests, but the helpers above are synchronous closures that must not
    /// outlive their temporary directory. This bridges the two without leaking the directory.
    private func runBlocking<T: Sendable>(
        _ work: @escaping @Sendable () async throws -> T
    ) throws -> T {
        let semaphore = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var outcome: Result<T, any Error>!
        Task {
            do { outcome = try await .success(work()) } catch { outcome = .failure(error) }
            semaphore.signal()
        }
        semaphore.wait()
        return try outcome.get()
    }
}
