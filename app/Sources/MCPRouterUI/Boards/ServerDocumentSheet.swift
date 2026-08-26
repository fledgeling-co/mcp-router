#if os(macOS)
    import MCPRouterKit
    import SwiftUI

    /// The capability document panel, opened for one declared server.
    ///
    /// **The entry point M19 could not build.** M19 drew the panel and measured it under M23, and
    /// `RouterSheet.Kind.readme` sat in the inventory declaring `owner == "M19"` — the marker for
    /// *drawn in the mock, hosted by nothing* — because no router served a document. M30 serves one,
    /// so this is what presents it.
    ///
    /// It asks on every open rather than holding a value. A package can be re-installed underneath
    /// an open board, and a document captured when the sheet was opened would describe the package
    /// that used to be there — the reason `RouterSheet.Servers.document` carries a name and not a
    /// document.
    ///
    /// The three states are the source's, not this view's: `loading` while the request is in
    /// flight, `document` when one arrived, `unavailable` carrying the router's own refusal. A
    /// failure is never rendered as an empty panel, which would read as "this package publishes
    /// nothing" for a router that was never reached.
    struct ServerDocumentSheet: View {
        let source: any CapabilityDocumentSource
        let serverName: String
        let dismiss: @MainActor @Sendable () -> Void

        @State private var content: CapabilityDocumentSheet.Content = .loading

        var body: some View {
            CapabilityDocumentSheet(content: content, dismiss: dismiss)
                .task(id: serverName) { await load() }
        }

        private func load() async {
            do {
                content = try await .document(source.document(for: serverName))
            } catch {
                content = .unavailable(error)
            }
        }
    }
#endif
