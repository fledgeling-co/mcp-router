#if os(macOS)
    import MCPRouterKit
    import SwiftUI

    /// The Settings window's own state, which is only ever the control token.
    ///
    /// Everything else the window draws comes from the shell's poll. This owns the one fact the
    /// router does not serve — whether this Mac has a token stored — and the one action the Security
    /// pane performs.
    ///
    /// **One instance per window, and a `Settings` scene destroys its window on close**, so `load()`
    /// re-reads the keychain on every `⌘,`. That was the Settings board's behaviour too — it built
    /// its model in `init` and `ContentZone` rebuilt it on every destination switch — so it is not a
    /// regression, and it is one `SecItemCopyMatching`. Recorded because it stops being cheap the
    /// moment a pane adds a second read.
    ///
    /// The store is **injected**, so no test touches the real Keychain and the token clauses can run
    /// against `InMemoryTokenStore`. A model that constructed `KeychainTokenStore()` itself would
    /// make every test that exercises this pane prompt the developer's login keychain.
    @MainActor
    @Observable
    final class SettingsWindowModel {
        @ObservationIgnored private let store: any ControlTokenStore
        @ObservationIgnored private let file: RouterTokenFile

        private(set) var status: SettingsPresentation.TokenStatus = .absent

        /// The window's one open sheet.
        ///
        /// It lives on the **window's** model rather than the shell's so the presentation attaches
        /// to the Settings window, which is the brief's one requirement with no reference to build
        /// against: the mock draws both windows on one page and cannot demonstrate it. A sheet
        /// hung off `ShellModel` here would drop from the console's titlebar instead.
        var sheet: RouterSheet.Settings?

        init(store: any ControlTokenStore, file: RouterTokenFile = RouterTokenFile()) {
            self.store = store
            self.file = file
        }

        /// Where the router keeps its state, derived from the same path the client resolves to find
        /// the token — so the directory shown is the directory used, rather than a second guess at
        /// it that could drift.
        var routerHome: URL { file.url.deletingLastPathComponent() }

        var tokenPath: String {
            let path = file.url.path
            let home = NSHomeDirectory()
            guard !home.isEmpty, path.hasPrefix(home) else { return path }
            return "~" + path.dropFirst(home.count)
        }

        var tokenHelp: String {
            switch status {
            case .stored, .unavailable: SettingsPresentation.tokenStoredHelp
            case .absent: SettingsPresentation.tokenAbsentHelp
            case .rejected: SettingsPresentation.tokenRejectedHelp
            }
        }

        /// Read whether a token is stored. Never reads it *for* display — the value is not returned
        /// from here and there is nowhere in `TokenStatus` to put it.
        ///
        /// `unauthorized` is passed in rather than discovered, because "a token is stored" and "the
        /// router rejects it" are two different facts from two different places, and only the caller
        /// watching the tracker knows the second.
        func load(unauthorized: Bool) async {
            do {
                let stored = try await store.read()
                if stored?.isEmpty == false {
                    status = unauthorized ? .rejected : .stored
                } else {
                    status = .absent
                }
            } catch {
                // The keychain itself refused. Distinct from "no token": the app is still using the
                // copy it read from the router's file, so this is a degraded state rather than a
                // broken one, and saying "not stored yet" here would be wrong in a way that sends
                // the user looking for a problem they do not have.
                status = .unavailable(status: Self.osStatus(from: error))
            }
        }

        /// Delete the stored token so the client re-reads the router's file on its next request.
        ///
        /// **Sends nothing to the router.** There is no rotate endpoint and this is not one: the
        /// router owns the token, writes it to its own file, and this app only caches it.
        func forget() async {
            guard status.canForget else { return }
            do {
                try await store.delete()
                status = .absent
            } catch {
                status = .unavailable(status: Self.osStatus(from: error))
            }
        }

        /// The OSStatus behind a keychain failure, where the error carries one.
        ///
        /// Reported because it is the single detail a support conversation needs, and it is not a
        /// secret. `errSecItemNotFound` is the common one and reads as −25300.
        private static func osStatus(from error: any Error) -> Int32 {
            if case let TokenStoreError.keychain(status) = error { return status }
            return Int32((error as NSError).code)
        }
    }
#endif
