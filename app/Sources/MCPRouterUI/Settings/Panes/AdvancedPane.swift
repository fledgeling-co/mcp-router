#if os(macOS)
    import MCPRouterKit
    import SwiftUI

    /// Advanced — where the router keeps its two files, and what this build calls itself.
    ///
    /// **Paths and no sizes.** The mock draws `router.log · 4.2 MB`; the path is derived from the
    /// same directory the client resolves to find the token, so it is observed, while the megabyte
    /// figure would need a `stat` of a file inside a directory A36's one-channel rule keeps this
    /// layer out of — and `DESIGN.md` §6 forbids a number nobody observed either way. The server
    /// count beside the configuration path *is* observed: it is the length of the array the Servers
    /// board draws.
    ///
    /// `Rebuild the tool cache` and `Restore direct configuration` are not built. Re-indexing is
    /// per-server on the control API and there is no bulk endpoint; nothing anywhere writes adopted
    /// servers back into the harnesses they came from.
    struct AdvancedPane: View {
        @Bindable var shell: ShellModel
        let routerHome: URL
        let buildIdentity: BuildIdentity
        /// Opens the child-PATH sheet on the Settings window. A closure rather than a model, so
        /// this pane still renders without one.
        var onShowChildPath: () -> Void = {}

        private var files: SettingsPresentation.RouterFiles {
            .init(home: routerHome)
        }

        var body: some View {
            VStack(alignment: .leading, spacing: SettingsMetrics.groupGap) {
                filesGroup
                identityFooter
            }
        }

        private var filesGroup: some View {
            SettingsGroup(SettingsPaneCopy.filesGroup) {
                SettingsCard {
                    SettingsRow(
                        label: SettingsPaneCopy.logLabel,
                        value: files.logPath(),
                        truncatesFromLeft: true
                    )
                    SettingsRow(
                        label: SettingsPaneCopy.configurationLabel,
                        value: configurationValue,
                        truncatesFromLeft: true
                    )
                }
                SettingsHelp(SettingsPaneCopy.filesHelp, id: "files-help")

                // `…` because it opens a further view (§3.4). Quiet, because reading where the
                // router looks for a binary commits nothing.
                Button(SettingsPaneCopy.childPathAction, action: onShowChildPath)
                    .buttonStyle(StandardButtonStyle())
            }
        }

        /// The path, and the declared-server count only where one has been observed. A build that
        /// has never reached the router draws the path alone rather than `0 servers`, which would be
        /// a count of something nobody has read.
        private var configurationValue: String {
            let path = files.configurationPath()
            guard let count = shell.servers?.count else { return path }
            return "\(path) · \(count) \(count == 1 ? "server" : "servers")"
        }

        /// The build line, handed in as a value from the one file permitted to read the app's own
        /// bundle metadata (A36). The name of that API is deliberately not written anywhere in this
        /// directory: the boundary gate is a source grep and cannot tell prose from a call.
        ///
        /// The mock's footer also claims `Developer ID signed and notarised`; nothing in this
        /// process observes its own signature and every build in this repository is unsigned, so
        /// that clause is not carried.
        private var identityFooter: some View {
            SettingsHelp(
                buildIdentity.summary ?? SettingsPaneCopy.buildIdentityUnknown,
                id: "build-identity"
            )
        }
    }
#endif
