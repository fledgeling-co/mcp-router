import MCPRouterKit
import MCPRouterUI
import SwiftUI

/// The macOS shell.
///
/// This is scaffolding, and it says so rather than inventing content. The server board, activity,
/// skills and settings arrive with the surface items that depend on this one; a placeholder that
/// showed a fake server list or a made-up count would be the exact failure the product forbids —
/// no number is displayed that the router does not observe, and this build observes none.
///
/// What it does do is draw entirely through `MCPRouterUI`. The private colour bridge that used to
/// live at the bottom of this file is gone: there is one design system now, in one place, and both
/// apps read it. A Debug build additionally carries the design gallery, which is the surface that
/// makes the system reviewable rather than merely asserted.
@main
struct MCPRouterApp: App {
    var body: some Scene {
        WindowGroup("MCP Router") {
            FoundationView()
                .frame(minWidth: 480, minHeight: 320)
        }
        .windowResizability(.contentSize)

        #if DEBUG
            // Debug only, and the acceptance harness asserts its identifier is absent from a
            // Release binary. A reference surface that shipped would be a feature nobody designed.
            //
            // A `Window` scene is listed in the Window menu under its own title, so this needs no
            // custom command to be reachable — and §3.9 wants every command reachable from the
            // menu bar, which this satisfies by construction rather than by addition.
            Window("Design system", id: "design-gallery") {
                DesignGallery()
            }
        #endif
    }
}

struct FoundationView: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MCP Router")
                .typeRole(.title1)
                .foregroundStyle(ColorToken.t1.color)

            Text("Version \(version)")
                .typeRole(.callout, monospaced: true)
                .foregroundStyle(ColorToken.t2.color)

            Text(
                """
                The generated project and shared library are in place. The server board, \
                activity and settings arrive with the surfaces built on top of this.
                """
            )
            .typeRole(.body)
            .foregroundStyle(ColorToken.t2.color)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(ColorToken.ground.color)
    }
}
