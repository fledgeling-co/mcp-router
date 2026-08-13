import SwiftUI

struct SettingsView: View {
    @Environment(RouterStore.self) private var store
    @AppStorage("routerPort") private var port = RouterClient.defaultPort

    var body: some View {
        Form {
            Section("Router") {
                TextField("Port", value: $port, format: .number.grouping(.never))
                    .onChange(of: port) { _, new in Task { await store.repoint(port: new) } }
                LabeledContent("Endpoint") {
                    Text("http://127.0.0.1:\(String(port))")
                        .font(Theme.Font.rowMono)
                        .textSelection(.enabled)
                }
                LabeledContent("Status") {
                    switch store.connection {
                    case .up: Text("Connected").foregroundStyle(Theme.ok)
                    case .connecting: Text("Connecting…").foregroundStyle(.secondary)
                    case .down(let why): Text(why).foregroundStyle(Theme.failed)
                    }
                }
                LabeledContent("Control token") {
                    Text(RouterClient.tokenPath)
                        .font(Theme.Font.secondary.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Section {
                Text("This app only talks to the router over loopback HTTP, using the token the router writes at 0600. It never edits ~/.claude.json — the router's watcher owns that, and two writers would race.")
                    .font(Theme.Font.secondary)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 300)
    }
}
