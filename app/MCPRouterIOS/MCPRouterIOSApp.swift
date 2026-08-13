import MCPRouterKit
import SwiftUI

/// The iPhone companion's shell.
///
/// Same rule as the Mac shell: scaffolding that states what it is instead of showing invented
/// data, reading its colour and type from the shared library so the link is visible on screen.
///
/// The companion's eventual job is narrower than the Mac app's by design — it queues capabilities
/// for review on the Mac and never installs them — but none of that surface exists yet.
@main
struct MCPRouterIOSApp: App {
    var body: some Scene {
        WindowGroup {
            FoundationView()
        }
    }
}

struct FoundationView: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MCP Router")
                .font(.system(size: TypeToken.title1.size, weight: .bold))
                .foregroundStyle(ColorToken.t1.swiftUIColor)

            Text("Version \(version)")
                .font(.system(size: TypeToken.callout.size, weight: .semibold, design: .monospaced))
                .foregroundStyle(ColorToken.t2.swiftUIColor)

            Text(
                """
                The companion's shell is in place. Pairing and the review queue \
                arrive with the surfaces built on top of this.
                """
            )
            .font(.system(size: TypeToken.body.size, weight: .semibold))
            .foregroundStyle(ColorToken.t2.swiftUIColor)
            .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(ColorToken.ground.swiftUIColor)
    }
}

/// See the note on the macOS shell's copy: a temporary bridge so the scaffolding can draw, kept
/// out of `MCPRouterKit` so the library stays importable without a UI framework. The
/// design-system item replaces both copies with the real asset-catalogue layer.
extension ColorToken {
    var swiftUIColor: Color {
        let hex = hex.dropFirst()
        let value = UInt64(hex, radix: 16) ?? 0
        return Color(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: opacity
        )
    }
}
