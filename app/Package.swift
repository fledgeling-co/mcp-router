// swift-tools-version: 6.0
import PackageDescription

/// `MCPRouterKit` is the code both apps and the Swift router's tests share.
///
/// It deliberately has **no external dependencies**. The Swift MCP SDK is pre-1.0 and its own
/// README warns that a minor bump may break the API, so the decision about adopting it — and
/// pinning it to an exact version rather than a range — belongs to the router item that actually
/// needs it, not to this foundation.
let package = Package(
    name: "MCPRouterKit",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "MCPRouterKit", targets: ["MCPRouterKit"])
    ],
    targets: [
        .target(
            name: "MCPRouterKit",
            path: "Sources/MCPRouterKit",
            // The recorded fixtures ship with the library rather than with its tests, because the
            // test double is for *consumers* — the two app targets' own tests need to construct a
            // client with no router running, and a resource that lived in this package's test
            // bundle would be unreachable from theirs.
            resources: [.copy("Control/Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "MCPRouterKitTests",
            dependencies: ["MCPRouterKit"],
            path: "Tests/MCPRouterKitTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // The one check a stub cannot stand in for. Every other test in this package talks to a
        // stub we wrote ourselves, which proves the client agrees with our belief about the wire;
        // this talks to the actual router. It is an executable rather than a test because it needs
        // a running daemon, and a unit suite that needs a daemon is a unit suite that fails on a
        // machine where one is not running.
        .executableTarget(
            name: "ControlProbe",
            dependencies: ["MCPRouterKit"],
            path: "Sources/ControlProbe",
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
