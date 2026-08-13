// swift-tools-version: 6.0
import PackageDescription

/// `MCPRouterKit` is the code both apps and the Swift router's tests share.
///
/// It deliberately has **no external dependencies**. The Swift MCP SDK is pre-1.0 and its own
/// README warns that a minor bump may break the API, so the decision about adopting it — and
/// pinning it to an exact version rather than a range — belongs to the router item that actually
/// needs it, not to this foundation.
///
/// `MCPRouterUI` is the shared presentation layer. It is a **separate product** rather than part of
/// the kit for one binding reason: `SWIFT_PRACTICES.md` §8 requires the kit to stay free of UI
/// frameworks so the router's own tests can import it. Putting the shared views in each app instead
/// would give the product two design systems that drift, so both app targets link this one.
let package = Package(
    name: "MCPRouterKit",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "MCPRouterKit", targets: ["MCPRouterKit"]),
        .library(name: "MCPRouterUI", targets: ["MCPRouterUI"])
    ],
    targets: [
        .target(
            name: "MCPRouterKit",
            path: "Sources/MCPRouterKit",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "MCPRouterUI",
            dependencies: ["MCPRouterKit"],
            path: "Sources/MCPRouterUI",
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
        )
    ]
)
