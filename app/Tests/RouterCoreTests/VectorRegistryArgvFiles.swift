import Foundation
import Testing
@testable import RouterCore

/// The DEF-070 consumer: `GET /servers` argv redaction, read from the file
/// `scripts/parity/generate-argv-vectors.mjs` writes from the TypeScript reference.
///
/// Split into its own file for the same reason the document vectors are: the repo caps a file at
/// 400 lines, and the control list is already near it. Appended to ``VectorRegistry/files``, so the
/// attestation counts these cases and the floor in `VectorRegistry.swift` covers them.
extension VectorRegistry {
    static let argvFiles: [RegisteredVectorFile] = [
        RegisteredVectorFile(
            file: "argv-redact", rows: ["DEF-070"], consumer: "ArgvRedaction.redact"
        ) { cases in
            for testCase in cases {
                let id = ManifestVectors.text(testCase.member("id")) ?? ""
                // The same construction `ControlHandler` makes for `GET /servers`: the needles come
                // from every upstream the router holds, and from its control token.
                let servers = testCase.member("servers")?.asObjectMembers ?? []
                let upstreams = servers.compactMap { entry -> UpstreamConfig? in
                    guard case let .upstream(upstream) = ServerParser.parse(
                        name: entry.key.string, raw: entry.value
                    ) else { return nil }
                    return upstream
                }
                let scrubber = SecretRedactor(needles: SecretNeedles.collect(
                    upstreams: upstreams,
                    controlToken: ManifestVectors.text(testCase.member("token")) ?? ""
                ))
                let target = ManifestVectors.text(testCase.member("target")) ?? ""
                let args = upstreams.first { $0.name == target }?.raw.member("args") ?? .array([])
                #expect(
                    ArgvRedaction.redact(args, with: scrubber) == (testCase.member("expected") ?? .null),
                    "registry/argv-redact \(id)"
                )
            }
            return cases.count
        }
    ]
}
