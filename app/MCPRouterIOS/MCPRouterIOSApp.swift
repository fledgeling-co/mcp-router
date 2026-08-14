import MCPRouterKit
import MCPRouterUI
import SwiftUI

/// The iPhone companion's shell.
///
/// Same rule as the Mac shell: scaffolding that states what it is instead of showing invented
/// data, drawing entirely through the shared design system so there is one look rather than two.
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
    #if DEBUG
        @State private var showingGallery = false
    #endif

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
                The companion's shell is in place. Pairing and the review queue \
                arrive with the surfaces built on top of this.
                """
            )
            .typeRole(.body)
            .foregroundStyle(ColorToken.t2.color)
            .fixedSize(horizontal: false, vertical: true)

            #if DEBUG
                // Debug only. The phone gets the same six sections as the Mac, in its own
                // navigation, so the system can be reviewed on the device it also has to work on.
                Button("Design system") { showingGallery = true }
                    .buttonStyle(StandardButtonStyle())
            #endif

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(ColorToken.ground.color)
        #if DEBUG
            .sheet(isPresented: $showingGallery) { DesignGallery() }
        #endif
    }
}
