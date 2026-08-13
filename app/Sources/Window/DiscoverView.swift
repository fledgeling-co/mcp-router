import SwiftUI

/// Search the two public MCP indexes and install from the result.
///
/// The router merges the official registry with Smithery and dedupes on repository, so
/// one server listed in both appears once with Smithery's usage count and the official
/// install command. That merge happens in the router, not here — the app shows what it
/// is told and says which index each row came from.
struct DiscoverView: View {
    @Environment(RouterStore.self) private var store
    @State private var query = ""
    @State private var results: [RegistryEntry] = []
    @State private var sources: RegistryResponse.Sources?
    @State private var warnings: [String] = []
    @State private var searching = false
    @State private var searched = false
    @State private var installing: RegistryEntry?

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(
                title: "Discover",
                subtitle: sources.map { "\($0.merged) results · \($0.official) official · \($0.smithery) Smithery" }
                    ?? "Search the official MCP registry and Smithery"
            )

            searchField
            if !warnings.isEmpty { warningBand }
            Divider()

            if searching {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if results.isEmpty {
                ContentUnavailableView {
                    Label(searched ? "Nothing found" : "Find an MCP server", systemImage: "sparkle.magnifyingglass")
                } description: {
                    Text(searched
                         ? "No server in either index matched \"\(query)\"."
                         : "Search by what you want it to do — \"github\", \"postgres\", \"browser\".")
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(results) { entry in
                            RegistryRow(entry: entry, installed: isInstalled(entry)) { installing = entry }
                        }
                    }
                }
            }
        }
        .sheet(item: $installing) { entry in
            InstallSheet(entry: entry) { installing = nil }
                .environment(store)
        }
    }

    private func isInstalled(_ e: RegistryEntry) -> Bool {
        e.installed == true || store.servers.contains { $0.name == e.name || $0.name == e.displayName }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.tertiary)
            TextField("Search MCP servers", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .onSubmit { run() }
            if searching { ProgressView().controlSize(.mini) }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    /// Rate limits and a partly-answered merge are reported rather than swallowed. A
    /// short list caused by GitHub's 60-requests-an-hour ceiling looks identical to a
    /// short list caused by there being little to find, and those are different answers.
    private var warningBand: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(warnings, id: \.self) { w in
                Label(w, systemImage: "info.circle")
                    .font(Theme.Font.secondary)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private func run() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        searching = true
        Task {
            let res = await store.search(q)
            results = res?.results ?? []
            sources = res?.sources
            warnings = res?.warnings ?? []
            searching = false
            searched = true
        }
    }
}

struct RegistryRow: View {
    let entry: RegistryEntry
    let installed: Bool
    let install: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.displayName)
                        .font(Theme.Font.row.weight(.semibold))
                        .lineLimit(1)
                    if entry.verified == true {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .help("Verified on Smithery")
                    }
                    if entry.archived == true {
                        Text("ARCHIVED")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.attention)
                    }
                }
                Text(entry.description)
                    .font(Theme.Font.secondary)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                // Badges and numbers on one line, because they are read together: how
                // popular, how fresh, and where it came from is one judgment, not three.
                HStack(spacing: 10) {
                    if let n = entry.useCount { Metric("person.2", "\(n.formatted(.number.notation(.compactName)))", "installs on Smithery") }
                    if let n = entry.stars { Metric("star", "\(n.formatted(.number.notation(.compactName)))", "GitHub stars") }
                    if let at = entry.pushedAt ?? entry.updatedAt { Metric("clock", shortAgo(iso: at), "last updated") }
                    Text(entry.source)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                .padding(.top, 1)
            }

            Spacer(minLength: 8)

            if installed {
                Label("Installed", systemImage: "checkmark")
                    .font(Theme.Font.secondary)
                    .foregroundStyle(.secondary)
            } else if entry.install != nil {
                Button("Install", action: install).controlSize(.small)
            } else {
                Text("No install info")
                    .font(Theme.Font.secondary)
                    .foregroundStyle(.tertiary)
                    .help("Neither index says how to run this one.")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .rowDivider()
    }

    private func Metric(_ icon: String, _ value: String, _ help: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 9))
            Text(value).font(Theme.Font.secondary)
        }
        .foregroundStyle(.tertiary)
        .help(help)
    }
}

/// Installing is a decision, so it gets a sheet rather than a one-click row button:
/// the command about to be added to your machine is shown in full, and anything it
/// needs from you is asked for before it runs.
struct InstallSheet: View {
    @Environment(RouterStore.self) private var store
    let entry: RegistryEntry
    let done: () -> Void

    @State private var name: String = ""
    @State private var values: [String: String] = [:]
    @State private var busy = false
    @State private var failure: String?
    @State private var offerForce = false

    private var requirements: [RegistryInstall.Requirement] { entry.install?.requires ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Install \(entry.displayName)").font(.system(size: 15, weight: .semibold))
                Text(entry.description).font(Theme.Font.secondary).foregroundStyle(.secondary)
            }

            Form {
                TextField("Name in the router", text: $name)
                    .help("How this server's tools will be namespaced")

                if let cmd = entry.install?.command {
                    LabeledContent("Runs") {
                        Text(([cmd] + (entry.install?.args ?? [])).joined(separator: " "))
                            .font(Theme.Font.rowMono)
                            .textSelection(.enabled)
                    }
                }
                if let url = entry.install?.url {
                    LabeledContent("URL") { Text(url).font(Theme.Font.rowMono) }
                }

                if !requirements.isEmpty {
                    Section("Needs from you") {
                        ForEach(requirements, id: \.name) { r in
                            if r.isSecret == true {
                                SecureField(r.name, text: binding(r.name))
                            } else {
                                TextField(r.name, text: binding(r.name))
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)

            if let failure {
                Label(failure, systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.Font.secondary)
                    .foregroundStyle(Theme.failed)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // The router indexes a server before writing it to config, so a typo'd command
            // never enters the router's world at all. Forcing is available and explicit.
            if offerForce {
                Text("The router couldn't start it, so nothing was saved. Install anyway and it'll be listed with the failure until it works.")
                    .font(Theme.Font.secondary)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Cancel", role: .cancel) { done() }
                Spacer()
                if offerForce {
                    Button("Install anyway") { go(force: true) }
                }
                Button("Install") { go(force: false) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(busy || name.isEmpty)
            }
        }
        .padding(18)
        .frame(width: 460)
        .overlay { if busy { Color.black.opacity(0.05); ProgressView() } }
        .onAppear { if name.isEmpty { name = entry.name } }
    }

    private func binding(_ key: String) -> Binding<String> {
        .init(get: { values[key] ?? "" }, set: { values[key] = $0 })
    }

    private func go(force: Bool) {
        guard let install = entry.install else { return }
        busy = true; failure = nil

        var spec = InstallSpec()
        if let c = install.command {
            spec.command = c
            spec.args = install.args ?? []
        }
        if let u = install.url {
            spec.url = u
            spec.type = install.type == "sse" ? "sse" : "http"
        }
        let supplied = values.filter { !$0.value.isEmpty }
        if !supplied.isEmpty { spec.env = supplied }

        let name = name
        Task {
            let ok = await store.install(name: name, spec: spec, force: force)
            busy = false
            if ok { done() } else {
                failure = store.actionError
                store.actionError = nil
                offerForce = true
            }
        }
    }
}

