import Foundation
import Testing
@testable import RouterCore

/// The M30 vector consumers — the document route's three pure halves.
///
/// A wire comparison of two routers that agree cannot tell a shared misreading of a reference from
/// a correct one, so the halves that decide **which file is read** are pinned here against the
/// TypeScript reference rather than against the other router.
///
/// Appended to ``VectorRegistry/files``, so the attestation counts them and the parity floor covers
/// them.
extension VectorRegistry {
    static let documentFiles: [RegisteredVectorFile] = [
        RegisteredVectorFile(
            file: "document-image-refs",
            rows: ["M30-refs"],
            consumer: "DocumentPackage.imageReferences"
        ) { cases in
            for testCase in cases {
                let id = ManifestVectors.text(testCase.member("id")) ?? ""
                let text = ManifestVectors.text(testCase.member("text")) ?? ""
                let expected = (testCase.member("references")?.asArray ?? [])
                    .compactMap { ManifestVectors.text($0) }
                #expect(
                    DocumentPackage.imageReferences(in: text) == expected,
                    "registry/document-image-refs \(id)"
                )
            }
            return cases.count
        },

        RegisteredVectorFile(
            file: "document-resolve",
            rows: ["M30-resolve"],
            consumer: "DocumentPackage.resolve"
        ) { cases in
            // The vector declares the package it was taken against, so this builds the SAME tree
            // before it asks the same questions. A consumer that materialised a tree of its own
            // would be comparing two answers to two different questions and reporting agreement.
            let document = try ManifestVectors.document("document-resolve")
            let root = try DocumentVectorPackage.materialise(tree: document.member("tree"))
            defer { try? FileManager.default.removeItem(atPath: root.deletingLastPathComponent().path) }

            for testCase in cases {
                let id = ManifestVectors.text(testCase.member("id")) ?? ""
                let reference = ManifestVectors.text(testCase.member("reference")) ?? ""
                let produced = DocumentPackage.resolve(
                    reference, inPackageAt: root.path, fileSystem: RealFileSystem()
                )
                switch ManifestVectors.text(testCase.member("kind")) {
                case "readable":
                    let relative = ManifestVectors.text(testCase.member("relative")) ?? ""
                    guard case let .readable(path) = produced else {
                        Issue.record("registry/document-resolve \(id): expected readable, got \(produced)")
                        continue
                    }
                    // Compared as the path INSIDE the package: the absolute prefix is a scratch
                    // directory this run made up and the reference run made up a different one.
                    #expect(
                        path == root.appendingPathComponent(relative).resolvingSymlinksInPath().path,
                        "registry/document-resolve \(id)"
                    )
                default:
                    guard case let .refused(refusal) = produced else {
                        Issue.record("registry/document-resolve \(id): expected a refusal, got \(produced)")
                        continue
                    }
                    #expect(
                        refusal.reason == (ManifestVectors.text(testCase.member("reason")) ?? ""),
                        "registry/document-resolve \(id)"
                    )
                    // The payload beside the reason, where the refusal carries one. A port that
                    // agreed on the case and lost the scheme would send a placeholder whose
                    // sentence names the wrong thing.
                    if case let .remote(scheme) = refusal {
                        #expect(
                            scheme == (ManifestVectors.text(testCase.member("scheme")) ?? ""),
                            "registry/document-resolve \(id) scheme"
                        )
                    }
                    if case let .unsupportedType(ext) = refusal {
                        #expect(
                            ext == (ManifestVectors.text(testCase.member("extension")) ?? ""),
                            "registry/document-resolve \(id) extension"
                        )
                    }
                }
            }
            return cases.count
        },

        RegisteredVectorFile(
            file: "document-caps",
            rows: ["M30-caps"],
            consumer: "DocumentPackage.documentOverCap and imageCapDecisions"
        ) { cases in
            // The caps themselves, before any decision is compared. Two implementations that agreed
            // on every decision while both holding a 1 MiB document cap would pass every case below
            // and serve a different wire.
            let document = try ManifestVectors.document("document-caps")
            let caps = document.member("caps")
            #expect(
                Int(caps?.member("documentBytes")?.asNumber ?? 0) == DocumentPackage.Caps.documentBytes,
                "registry/document-caps documentBytes"
            )
            #expect(
                Int(caps?.member("imageBytes")?.asNumber ?? 0) == DocumentPackage.Caps.imageBytes,
                "registry/document-caps imageBytes"
            )
            #expect(
                Int(caps?.member("imageBudgetBytes")?.asNumber ?? 0) == DocumentPackage.Caps.imageBudgetBytes,
                "registry/document-caps imageBudgetBytes"
            )

            for testCase in cases {
                let id = ManifestVectors.text(testCase.member("id")) ?? ""
                if ManifestVectors.text(testCase.member("kind")) == "document" {
                    let size = Int(testCase.member("size")?.asNumber ?? 0)
                    #expect(
                        DocumentPackage.documentOverCap(size)
                            == (testCase.member("over")?.asBool ?? false),
                        "registry/document-caps \(id)"
                    )
                    continue
                }
                let sizes = (testCase.member("sizes")?.asArray ?? []).map { Int($0.asNumber ?? 0) }
                let expected = (testCase.member("decisions")?.asArray ?? [])
                    .compactMap { ManifestVectors.text($0) }
                #expect(
                    DocumentPackage.imageCapDecisions(sizes: sizes).map(\.rawValue) == expected,
                    "registry/document-caps \(id)"
                )
            }
            return cases.count
        }
    ]
}

/// Builds the package a `document-resolve` vector was taken against.
///
/// The tree is read out of the vector rather than written here, so the two sides cannot drift: a
/// symlink that stopped being created would turn the escape case green by removing the escape.
enum DocumentVectorPackage {
    /// Returns the package root. Its parent is the scratch directory the caller removes.
    static func materialise(tree: JSONValue?) throws -> URL {
        let manager = FileManager.default
        let scratch = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("mcp-router-doc-vectors-\(UUID().uuidString)", isDirectory: true)
        let root = scratch.appendingPathComponent("pkg", isDirectory: true)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)

        for value in tree?.member("directories")?.asArray ?? [] {
            guard let name = value.asString?.string else { continue }
            try manager.createDirectory(
                at: root.appendingPathComponent(name), withIntermediateDirectories: true
            )
        }
        for value in tree?.member("files")?.asArray ?? [] {
            guard let name = value.asString?.string else { continue }
            let file = root.appendingPathComponent(name)
            try manager.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try Data("x".utf8).write(to: file)
        }
        try Data("x".utf8).write(to: scratch.appendingPathComponent("outside.png"))
        if let sibling = tree?.member("sibling")?.asString?.string {
            let directory = scratch.appendingPathComponent(sibling, isDirectory: true)
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("x".utf8).write(to: directory.appendingPathComponent("x.png"))
        }
        for value in tree?.member("symlinks")?.asArray ?? [] {
            guard let link = value.member("link")?.asString?.string,
                  let target = value.member("target")?.asString?.string else { continue }
            try manager.createSymbolicLink(
                atPath: root.appendingPathComponent(link).path, withDestinationPath: target
            )
        }
        return root
    }
}
