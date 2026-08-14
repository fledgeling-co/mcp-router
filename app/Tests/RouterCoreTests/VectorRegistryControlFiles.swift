import Foundation
import Testing
@testable import RouterCore

/// The R3 vector consumers — the control API, usage and the registry.
///
/// Split from `VectorRegistryFiles.swift` for the reason that file was split from
/// `VectorRegistry.swift`: the repo caps a file at 400 lines, and adding this item's coercion
/// corpus took the combined list past it. The division is by item rather than arbitrary, so the
/// question "which vectors did R3 add" is answered by a filename.
///
/// These are appended to ``VectorRegistry/files``, so the attestation counts them and the parity
/// floor in `VectorRegistry.swift` covers them.
extension VectorRegistry {
    static let controlFiles: [RegisteredVectorFile] = [
        RegisteredVectorFile(
            file: "is-control-path", rows: ["B01"], consumer: "ControlPathParityTests"
        ) { cases in
            for testCase in cases {
                let pathname = ManifestVectors.text(testCase.member("pathname")) ?? ""
                #expect(
                    ControlPaths.isControlPath(pathname)
                        == (testCase.member("control")?.asBool ?? false),
                    "registry/is-control-path \(ManifestVectors.text(testCase.member("id")) ?? "")"
                )
            }
            return cases.count
        },

        RegisteredVectorFile(
            file: "js-to-number", rows: ["N4", "N6"], consumer: "JSCoercionTests.numberMatches"
        ) { cases in
            for testCase in cases {
                let id = ManifestVectors.text(testCase.member("id")) ?? ""
                let produced = JSToNumber.number(ManifestVectors.text(testCase.member("text")) ?? "")
                // NaN and the infinities have no JSON spelling, so the expectation arrives as a tag.
                // Comparing them as numbers would make `NaN == NaN` false and pass a broken port.
                switch ManifestVectors.text(testCase.member("kind")) {
                case "nan": #expect(produced.isNaN, "registry/js-to-number \(id) should be NaN")
                case "inf": #expect(produced == .infinity, "registry/js-to-number \(id)")
                case "-inf": #expect(produced == -.infinity, "registry/js-to-number \(id)")
                default:
                    #expect(
                        produced == (testCase.member("value")?.asNumber ?? .nan),
                        "registry/js-to-number \(id)"
                    )
                    // `Number("-0")` is -0, and `-0 == 0` in Swift as in JavaScript, so the
                    // equality above cannot see the sign. `JSON.stringify(-0)` is `"0"`, so the
                    // vector cannot carry it in `value` either — the generator tags it instead.
                    // The sign is what `slice` branches on, so it has to be checked.
                    let wantsNegativeZero = testCase.member("negativeZero")?.asBool ?? false
                    #expect(
                        produced.sign == (wantsNegativeZero ? .minus : .plus)
                            || produced != 0,
                        "registry/js-to-number \(id) sign"
                    )
                }
            }
            return cases.count
        },

        RegisteredVectorFile(
            file: "locale-compare", rows: ["N8"], consumer: "RegistryTests.rankingUsesLocaleCompare"
        ) { cases in
            for testCase in cases {
                let lhs = ManifestVectors.text(testCase.member("lhs")) ?? ""
                let rhs = ManifestVectors.text(testCase.member("rhs")) ?? ""
                let expected = Int(testCase.member("result")?.asNumber ?? 0)
                let produced = JSLocaleCompare.compare(lhs, rhs)
                // The sort consumes the sign, which is all ICU guarantees across versions.
                #expect(
                    (produced > 0 ? 1 : produced < 0 ? -1 : 0) == expected,
                    "registry/locale-compare \(ManifestVectors.text(testCase.member("id")) ?? "")"
                )
            }
            return cases.count
        },

        RegisteredVectorFile(
            file: "project-of", rows: ["B47"], consumer: "ControlFixtureTests.usageSummary"
        ) { cases in
            for testCase in cases {
                let cwd = ManifestVectors.text(testCase.member("cwd")) ?? ""
                // An absent member is `undefined`, which the reference omits rather than nulls (N1).
                #expect(
                    projectOf(cwd) == ManifestVectors.text(testCase.member("project")),
                    "registry/project-of \(ManifestVectors.text(testCase.member("id")) ?? "")"
                )
            }
            return cases.count
        },

        RegisteredVectorFile(
            file: "usage-limit", rows: ["N4", "B45", "B46"], consumer: "ControlFixtureTests.usageRecent"
        ) { cases in
            // One store, warmed from the same log bytes the reference read, reused across every
            // case: `recent` is a read, so a per-case store would only prove the constructor twice.
            let log = try ManifestVectors.text(ManifestVectors.document("usage-limit").member("log")) ?? ""
            let fileSystem = MemoryFileSystem()
            fileSystem.seed(log, atPath: "/u/usage.log")
            let store = UsageStore(
                logPath: "/u/usage.log",
                statsPath: "/u/usage-stats.json",
                fileSystem: fileSystem,
                clock: ManualClock(milliseconds: 1_755_100_000_000)
            )
            for testCase in cases {
                let id = ManifestVectors.text(testCase.member("id")) ?? ""
                // The member is absent when the reference took its default, which is 200 and not a
                // coerced empty string — the two differ, so the absence has to survive to here.
                let limit = testCase.member("limit").map { JSToNumber.number(ManifestVectors.text($0) ?? "") }
                let produced = store.recent(
                    limit: limit,
                    server: ManifestVectors.text(testCase.member("server")),
                    cwd: ManifestVectors.text(testCase.member("cwd"))
                ).map(\.tool)
                let expected = (testCase.member("records")?.asArray ?? [])
                    .compactMap { ManifestVectors.text($0) }
                #expect(produced == expected, "registry/usage-limit \(id)")
            }
            return cases.count
        },

        RegisteredVectorFile(
            file: "registry-limit", rows: ["N6", "B54"], consumer: "RegistryTests.limitCoercion"
        ) { cases in
            // The row set the reference sliced, taken from the vector rather than restated here, so
            // the two cannot drift apart and quietly agree on a slice of a different array.
            let rowCount = try Int(ManifestVectors.document("registry-limit").member("rows")?.asNumber ?? 0)
            #expect(rowCount > 60, "the row set must exceed the 60 cap or the cap proves nothing")
            let rows = (0 ..< rowCount).map { index -> JSObjectDraft in
                var draft = JSObjectDraft()
                draft.set("id", .string(JSString("row-\(index)")))
                return draft
            }
            for testCase in cases {
                let id = ManifestVectors.text(testCase.member("id")) ?? ""
                let coerced = Registry.coerceLimit(ManifestVectors.text(testCase.member("limit")))
                switch ManifestVectors.text(testCase.member("kind")) {
                case "nan": #expect(coerced.isNaN, "registry/registry-limit \(id) should be NaN")
                case "inf": #expect(coerced == .infinity, "registry/registry-limit \(id)")
                case "-inf": #expect(coerced == -.infinity, "registry/registry-limit \(id)")
                default:
                    #expect(
                        coerced == (testCase.member("coerced")?.asNumber ?? .nan),
                        "registry/registry-limit \(id)"
                    )
                }
                // The coerced number is half of it; what the app receives is the slice it produces,
                // and a negative limit drops rows from the end rather than taking them (N6).
                let expected = (testCase.member("sliced")?.asArray ?? [])
                    .compactMap { ManifestVectors.text($0) }
                let sliced = Registry.jsSlice(rows, limit: coerced)
                    .compactMap { ManifestVectors.text($0.jsonValue.member("id")) }
                #expect(sliced == expected, "registry/registry-limit \(id) slice")
            }
            return cases.count
        }
    ]
}
