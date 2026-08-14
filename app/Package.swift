// swift-tools-version: 6.0
import PackageDescription

/// `MCPRouterKit` is the code both apps and the Swift router's tests share, and it deliberately has
/// **no external dependencies** — both app targets link it, and a pre-1.0 package in that graph
/// would put the apps at the mercy of a breaking minor bump.
///
/// `MCPRouterUI` is the shared presentation layer. It is a **separate product** rather than part of
/// the kit for one binding reason: `SWIFT_PRACTICES.md` §8 requires the kit to stay free of UI
/// frameworks so the router's own tests can import it. Putting the shared views in each app instead
/// would give the product two design systems that drift, so both app targets link this one.
///
/// `RouterCore` is the Swift router's data layer and is linked by **neither app**. It is where the
/// MCP SDK dependency lives, pinned to an exact version, so the SDK's instability is contained to
/// the target that actually speaks the protocol — which is what keeps the "no external
/// dependencies" promise above true for everything the apps compile.
let package = Package(
    name: "MCPRouterKit",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "MCPRouterKit", targets: ["MCPRouterKit"]),
        .library(name: "MCPRouterUI", targets: ["MCPRouterUI"]),
        .library(name: "RouterCore", targets: ["RouterCore"])
    ],
    dependencies: [
        // Pinned to an EXACT version, never a range: the SDK is pre-1.0 and its own README warns
        // that a minor bump may break the API. Probe-built against Swift 6 strict concurrency
        // before adopting.
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", exact: "0.12.1")
    ],
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
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // The Swift router's data layer. Deliberately NOT linked by either app target: the Mac app
        // talks to the router only over the loopback control API, and leaving this out of the
        // app's dependency graph means reading `servers.json` directly would have to be added on
        // purpose rather than reached for by import.
        .target(
            name: "RouterCore",
            dependencies: [.product(name: "MCP", package: "swift-sdk")],
            path: "Sources/RouterCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
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
        .testTarget(
            name: "RouterCoreTests",
            dependencies: ["RouterCore"],
            path: "Tests/RouterCoreTests",
            resources: [.copy("Vectors")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // The one check a stub cannot stand in for. Every other test in this package talks to a
        // stub we wrote ourselves, which proves the client agrees with our belief about the wire;
        // this talks to the actual router. It is an executable rather than a test because it needs
        // a running daemon, and a unit suite that needs a daemon is a unit suite that fails on a
        // machine where one is not running.
        // The differential acceptance oracle: answers one control request through the Swift
        // handler so a script can diff its bytes against the running TypeScript router's. Every
        // other check in this package compares the port against something we wrote; this one
        // compares it against the reference, running, now.
        .executableTarget(
            name: "ControlDiff",
            dependencies: ["RouterCore"],
            path: "Sources/ControlDiff",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "ControlProbe",
            dependencies: ["MCPRouterKit"],
            path: "Sources/ControlProbe",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // The router itself: the process the cutover would point a launchd agent at.
        //
        // R2 shipped the pool, the supervision and the passthrough value layer and deferred the
        // process that uses them, so until this target existed `RouterCore` was a library nothing
        // ran — and R4's parity gate had five lanes it could not measure at all, because there was
        // no Swift binary to invoke, no listener to drive and no long-lived process to hold state
        // or write a log.
        //
        // It ships **alongside** `node dist/index.js`, which stays the installed default until
        // R4's differential parity gate passes.
        .executableTarget(
            name: "MCPRouterCLI",
            dependencies: ["RouterCore"],
            path: "Sources/MCPRouterCLI",
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
