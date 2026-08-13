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
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "MCPRouterKitTests",
            dependencies: ["MCPRouterKit"],
            path: "Tests/MCPRouterKitTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
