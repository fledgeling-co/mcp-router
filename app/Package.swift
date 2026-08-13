// swift-tools-version: 6.0
import PackageDescription

/// `MCPRouterKit` is the code both apps and the Swift router's tests share, and it deliberately has
/// **no external dependencies** — both app targets link it, and a pre-1.0 package in that graph
/// would put the apps at the mercy of a breaking minor bump.
///
/// `RouterCore` is the Swift router's data layer and is linked by **neither app**. It is where the
/// MCP SDK dependency lives, pinned to an exact version, so the SDK's instability is contained to
/// the target that actually speaks the protocol.
let package = Package(
    name: "MCPRouterKit",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "MCPRouterKit", targets: ["MCPRouterKit"]),
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
            name: "RouterCoreTests",
            dependencies: ["RouterCore"],
            path: "Tests/RouterCoreTests",
            resources: [.copy("Vectors")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
