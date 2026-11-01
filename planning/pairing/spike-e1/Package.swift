// swift-tools-version: 6.0
import PackageDescription

/// E1, the TLS exporter and libsodium spike (planning/plans/plan-pairing-typed-spake2.md §5).
/// Finding only: nothing here is product code, and the app package does not depend on it.
let package = Package(
    name: "E1Spike",
    platforms: [.macOS(.v15)],
    dependencies: [
        // Pinned exactly, as §1 requires. 0.11.0 is the release whose bundled libsodium is 1.0.22.
        .package(url: "https://github.com/jedisct1/swift-sodium", exact: "0.11.0")
    ],
    targets: [
        .executableTarget(name: "e1-nw-exporter", path: "Sources/E1NWExporter"),
        .executableTarget(
            name: "e1-sodium",
            dependencies: [.product(name: "Clibsodium", package: "swift-sodium")],
            path: "Sources/E1Sodium"
        )
    ],
    swiftLanguageModes: [.v5]
)
