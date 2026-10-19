// swift-tools-version: 6.0
import Foundation
import PackageDescription

/// M23's measurement harness is compiled only when it is asked for.
///
/// With `MCP_ROUTER_MEASURE=1` in the environment at package-load time, `MEASURE` is defined for
/// the presentation layer and for the tool that drives it; without it, every `measured(…)` call
/// site is the identity modifier, the recorder is not linked into the app, and `MeasureDump` exits
/// 3 — inconclusive — rather than reporting a surface it never rendered.
///
/// A compile-time define rather than a runtime flag: a runtime switch leaves the recorder, the
/// preference key and the per-node closures in the shipped binary, which is a measurement
/// apparatus in a product nobody is measuring.
let measuring = ProcessInfo.processInfo.environment["MCP_ROUTER_MEASURE"] == "1"
let measureDefine: [SwiftSetting] = measuring ? [.define("MEASURE")] : []

/// `MCPRouterKit` is the code both apps and the Swift router's tests share, and it deliberately has
/// **no external dependencies** — both app targets link it, and a pre-1.0 package in that graph
/// would put the apps at the mercy of a breaking minor bump.
///
/// `MCPRouterUI` is the shared presentation layer. It is a **separate product** rather than part of
/// the kit for one binding reason: `SWIFT_PRACTICES.md` §8 requires the kit to stay free of UI
/// frameworks so the router's own tests can import it. Putting the shared views in each app instead
/// would give the product two design systems that drift, so both app targets link this one.
///
/// The Swift router (`RouterCore`, `MCPRouterCLI`, `ControlDiff` and `RouterCoreTests`) is retired and
/// not built. The owner decided on 2026-10-19 to keep its sources in the tree and take them out of
/// every build and release gate (`planning/plans/plan-retire-swift-router.md`, G2). Its targets are
/// not declared here, so nothing in it compiles, and the MCP SDK it alone depended on is not
/// resolved. `app/Retired/README.md` says what to restore to build it again.
let package = Package(
    name: "MCPRouterKit",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "MCPRouterKit", targets: ["MCPRouterKit"]),
        .library(name: "MCPRouterUI", targets: ["MCPRouterUI"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "MCPRouterKit",
            path: "Sources/MCPRouterKit",
            // The recorded fixtures ship with the library rather than with its tests, because the
            // test double is for *consumers* — the two app targets' own tests need to construct a
            // client with no router running, and a resource that lived in this package's test
            // bundle would be unreachable from theirs.
            resources: [.copy("Control/Fixtures"), .copy("Control/Authored")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "MCPRouterUI",
            dependencies: ["MCPRouterKit"],
            path: "Sources/MCPRouterUI",
            swiftSettings: [.swiftLanguageMode(.v6)] + measureDefine
        ),
        .testTarget(
            name: "MCPRouterKitTests",
            dependencies: ["MCPRouterKit"],
            path: "Tests/MCPRouterKitTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "MCPRouterUITests",
            dependencies: ["MCPRouterUI"],
            path: "Tests/MCPRouterUITests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // M23's conversion harness driver. Renders one surface in a hosted view, reads what the
        // instrumented nodes report about themselves, and writes the JSON tree the fidelity gate
        // diffs. Never activates and never comes to the front.
        .executableTarget(
            name: "MeasureDump",
            dependencies: ["MCPRouterKit", "MCPRouterUI"],
            path: "Sources/MeasureDump",
            swiftSettings: [.swiftLanguageMode(.v6)] + measureDefine
        ),
        .executableTarget(
            name: "ControlProbe",
            dependencies: ["MCPRouterKit"],
            path: "Sources/ControlProbe",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "MCPRouterApp",
            dependencies: ["MCPRouterKit", "MCPRouterUI"],
            path: "MCPRouter",
            exclude: ["Info.plist", "MCPRouter.entitlements", "Assets.xcassets"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
