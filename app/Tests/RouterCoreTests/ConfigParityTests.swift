import Foundation
import Testing
@testable import RouterCore

struct ParseServerVectors: Decodable {
    struct Case: Decodable {
        let id: String
        let name: String
        let raw: JSONCodableValue
        let reason: String?
        let upstream: JSONCodableValue?
        let hash: String?
    }

    let cases: [Case]
}

struct UpstreamHashVectors: Decodable {
    struct Case: Decodable {
        let id: String
        let upstream: JSONCodableValue
        let hash: String
    }

    let cases: [Case]
}

struct SelfReferenceVectors: Decodable {
    struct Case: Decodable {
        let id: String
        let name: String
        let raw: JSONCodableValue
        let port: Int
        let result: Bool
    }

    let cases: [Case]
}

struct URLVectors: Decodable {
    struct Case: Decodable {
        let id: String
        let input: String
        let ok: Bool
        let hostname: String?
        let port: String?
    }

    let cases: [Case]
}

/// Carries a vector's raw JSON through `Decodable` without losing member order, by keeping the
/// bytes and re-parsing them with the router's own parser.
struct JSONCodableValue: Decodable {
    let value: JSONValue

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let any = try container.decode(AnyRawJSON.self)
        value = any.value
    }
}

/// Minimal re-materialisation of a JSON subtree. Member order comes from `CodingKeys`-free
/// decoding, which loses it — so anywhere order matters the test compares against the router's own
/// parse of the original text instead.
struct AnyRawJSON: Decodable {
    let value: JSONValue

    init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer() {
            if container.decodeNil() {
                value = .null
                return
            }
            if let flag = try? container.decode(Bool.self) {
                value = .bool(flag)
                return
            }
            if let number = try? container.decode(Double.self) {
                value = .number(number)
                return
            }
            if let text = try? container.decode(String.self) {
                value = .string(JSString(text))
                return
            }
            if let array = try? container.decode([AnyRawJSON].self) {
                value = .array(array.map(\.value))
                return
            }
        }
        let keyed = try decoder.container(keyedBy: AnyKey.self)
        var members: [JSONMember] = []
        for key in keyed.allKeys {
            let nested = try keyed.decode(AnyRawJSON.self, forKey: key)
            members.append(JSONMember(key: JSString(key.stringValue), value: nested.value))
        }
        value = .object(members)
    }

    struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int?
        init?(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue: Int) {
            self.intValue = intValue; stringValue = String(intValue)
        }
    }
}

@Suite("Config parity with src/config.ts")
struct ConfigParityTests {
    // MARK: parseServer

    @Test("every rejection reason is byte-identical to the reference's")
    func rejectionReasons() throws {
        let vectors = try Vectors.load("parse-server", as: ParseServerVectors.self)
        var checked = 0
        for testCase in vectors.cases {
            guard let expectedReason = testCase.reason else { continue }
            let parsed = ServerParser.parse(name: testCase.name, raw: testCase.raw.value)
            guard case let .skipped(reason) = parsed else {
                Issue.record("\(testCase.id): adopted a server the reference rejected")
                continue
            }
            #expect(Array(reason.utf8) == Array(expectedReason.utf8), "\(testCase.id)")
            checked += 1
        }
        #expect(checked > 0, "the corpus must contain rejections, or this test proves nothing")
    }

    @Test("every adopted server matches the reference in every field, not just the decision")
    func adoptedServersMatchInEveryField() throws {
        let vectors = try Vectors.load("parse-server", as: ParseServerVectors.self)
        var checked = 0
        for testCase in vectors.cases {
            guard let expectedUpstream = testCase.upstream?.value else { continue }
            let parsed = ServerParser.parse(name: testCase.name, raw: testCase.raw.value)
            guard case let .upstream(upstream) = parsed else {
                Issue.record("\(testCase.id): rejected a server the reference adopted")
                continue
            }
            let expected = expectedUpstream
            expectField(
                expected,
                "transport",
                equals: .string(JSString(upstream.transport.rawValue)),
                testCase.id
            )
            expectField(expected, "name", equals: .string(JSString(upstream.name)), testCase.id)
            expectField(
                expected,
                "cwd",
                equals: upstream.cwd.map { .string(JSString($0)) } ?? .null,
                testCase.id
            )
            expectField(
                expected,
                "url",
                equals: upstream.url.map { .string(JSString($0)) } ?? .null,
                testCase.id
            )
            expectField(expected, "oauth", equals: upstream.oauth.map { .bool($0) } ?? .null, testCase.id)
            expectField(expected, "warm", equals: upstream.warm.map { .bool($0) } ?? .null, testCase.id)
            expectField(
                expected,
                "idleMs",
                equals: upstream.idleMs.map { .number(Double($0)) } ?? .null,
                testCase.id
            )
            expectField(
                expected,
                "startupTimeoutMs",
                equals: upstream.startupTimeoutMs.map { .number(Double($0)) } ?? .null,
                testCase.id
            )
            checked += 1
        }
        #expect(checked > 0)
    }

    private func expectField(_ expected: JSONValue, _ key: String, equals actual: JSONValue, _ id: String) {
        let want = expected.member(key) ?? .null
        #expect(
            JSStringify.compact(want) == JSStringify.compact(actual),
            "\(id).\(key): produced \(JSStringify.compact(actual)), expected \(JSStringify.compact(want))"
        )
    }

    // MARK: upstreamHash

    @Test("the config hash matches the reference over the whole adversarial corpus")
    func hashesMatchTheReference() throws {
        let vectors = try Vectors.load("parse-server", as: ParseServerVectors.self)
        var checked = 0
        for testCase in vectors.cases {
            guard let expected = testCase.hash else { continue }
            guard case let .upstream(upstream) = ServerParser.parse(
                name: testCase.name,
                raw: testCase.raw.value
            )
            else { continue }
            #expect(UpstreamHash.hash(upstream) == expected, "\(testCase.id)")
            checked += 1
        }
        #expect(checked > 0)
    }

    /// The exclusion rule, asserted as a relationship rather than as a list of digests: changing a
    /// field that does not alter what a server advertises must not cost a re-index.
    @Test("fields outside the hash material do not change the hash, and fields inside it do")
    func hashMaterialBoundaries() throws {
        let vectors = try Vectors.load("upstream-hash", as: UpstreamHashVectors.self)
        let byID = Dictionary(uniqueKeysWithValues: vectors.cases.map { ($0.id, $0.hash) })

        for excluded in [
            "excluded-name",
            "excluded-warm",
            "excluded-idle",
            "excluded-projects",
            "excluded-placard"
        ] {
            #expect(byID["cwd-absent"] == byID[excluded], "\(excluded) must not change the hash")
        }
        #expect(byID["args-order-za"] != byID["args-order-az"], "argument order is significant")
        #expect(
            byID["env-key-order-irrelevant-a"] == byID["env-key-order-irrelevant-b"],
            "env keys are sorted, so their order in the file is not significant"
        )
        #expect(
            byID["env-value-changes-hash"] != byID["env-value-changed"],
            "an env value change must invalidate the cached tool list"
        )
        #expect(byID["http-transport"] != byID["sse-transport"], "http and sse are different transports")
        #expect(byID["cwd-absent"] != byID["cwd-present"])
    }

    // MARK: isSelfReference

    @Test("self-reference detection matches, including the default-port case")
    func selfReference() throws {
        let vectors = try Vectors.load("self-reference", as: SelfReferenceVectors.self)
        for testCase in vectors.cases {
            let result = SelfReference.isSelfReference(
                name: testCase.name,
                raw: testCase.raw.value,
                port: testCase.port
            )
            #expect(result == testCase.result, "\(testCase.id): got \(result), expected \(testCase.result)")
        }
    }

    // MARK: URL reading

    @Test("the URL reader agrees with new URL() on parseability, host and reported port")
    func urlParsing() throws {
        let vectors = try Vectors.load("url-parse", as: URLVectors.self)
        for testCase in vectors.cases {
            let parsed = JSURL(testCase.input)
            #expect(
                (parsed != nil) == testCase.ok,
                "\(testCase.id): \(testCase.input.debugDescription) parseability"
            )
            guard let parsed, testCase.ok else { continue }
            #expect(parsed.host == testCase.hostname, "\(testCase.id) host")
            #expect(parsed.port == testCase.port, "\(testCase.id) port")
        }
    }
}
