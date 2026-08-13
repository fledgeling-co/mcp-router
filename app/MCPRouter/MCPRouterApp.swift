import MCPRouterKit
import SwiftUI

/// The macOS shell.
///
/// This is scaffolding, and it says so rather than inventing content. The server board, activity,
/// skills and settings arrive with the surface items that depend on this one; a placeholder that
/// showed a fake server list or a made-up count would be the exact failure the product forbids —
/// no number is displayed that the router does not observe, and this build observes none.
///
/// What it does do is read its colour and type from `MCPRouterKit`. That is deliberate: it makes
/// the shared library's presence provable by looking at the running window, not just by the fact
/// that the linker succeeded.
@main
struct MCPRouterApp: App {
    var body: some Scene {
        WindowGroup("MCP Router") {
            FoundationView()
                .frame(minWidth: 480, minHeight: 320)
        }
        .windowResizability(.contentSize)
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
                The workspace and shared library are in place. The server board, \
                activity and settings arrive with the surfaces built on top of this.
                """
            )
            .font(.system(size: TypeToken.body.size, weight: .semibold))
            .foregroundStyle(ColorToken.t2.swiftUIColor)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(ColorToken.ground.swiftUIColor)
    }
}

/// A minimal bridge from a token value to a SwiftUI colour, deliberately local to this shell.
///
/// `MCPRouterKit` stays free of SwiftUI so the Swift router's own tests can import it without a
/// UI framework, and the real presentation layer — the asset catalogue with an authored light
/// appearance, the font ramp, the control styles — belongs to the design-system item. This exists
/// only so the scaffolding shell can draw, and that item replaces it.
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
