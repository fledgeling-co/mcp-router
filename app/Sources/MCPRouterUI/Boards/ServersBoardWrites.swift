#if os(macOS)
    import Foundation
    import MCPRouterKit

    /// Every request the Servers board can issue, in one place.
    ///
    /// Split from the model's own state for length, and the split is a useful one: this is the
    /// whole of what this surface can ask the router to do, so `A13`'s claim about what may reach
    /// the wire is checkable by reading one file.
    @MainActor
    public extension ServersBoardModel {
        // MARK: - Writing

        /// Runs one write, holding the row's in-flight mark and recording a typed failure against it.
        ///
        /// Every write goes through here so that "mark, call, unmark, record" cannot be written four
        /// slightly different ways. The error is stored rather than logged: `SWIFT_PRACTICES.md` §3
        /// forbids swallowing one to keep a surface tidy.
        internal func write(_ name: String, _ operation: () async throws(ControlAPIError) -> Void) async {
            writesInFlight.insert(name)
            rowErrors[name] = nil
            defer { writesInFlight.remove(name) }
            do {
                try await operation()
            } catch {
                rowErrors[name] = error
            }
        }

        /// Clears a tripped server, by the operation that actually clears it.
        func reset(_ server: MCPServer) async {
            let kind: ResetKind = server.indexError != nil ? .reindex : .clearPlacard
            await write(server.name) { [client, tracker] () async throws(ControlAPIError) in
                switch kind {
                case .reindex:
                    // The result carries its own `error` for an index that failed again, which is a
                    // refusal the row has to keep showing rather than a success.
                    let result = try await client.reindex(server.name)
                    if let error = result.error {
                        throw ControlAPIError.server(status: 422, message: error, hint: nil)
                    }
                case .clearPlacard:
                    let updated = try await client.patch(server: server.name, ServerPatch(placard: .clear))
                    await tracker.apply(updated: updated)
                }
            }
        }

        /// The `Space` key and the Keep-warm toggle.
        ///
        /// `warm` is the only lever the control API offers over whether a child process stays up:
        /// there is no start operation and no stop operation on `ControlAPIClient`, and the router's
        /// design is that a server is spawned when a tool is called and reaped when idle. Setting it
        /// true does start one — the router calls its pool's warm-up (`src/control.ts`) — so this is
        /// a real lever and not a preference stored for later.
        ///
        /// **The asymmetry is worth stating rather than glossing:** `warm: true` starts a process,
        /// `warm: false` stops nothing — it clears the policy and lets the reaper take the server
        /// whenever it next goes idle. So one direction has an immediate visible effect and the
        /// other changes what will happen later. The subtitle reflects both immediately, because it
        /// reads `warm` rather than the lifecycle.
        func setWarm(_ name: String, to warm: Bool) async {
            await write(name) { [client, tracker] () async throws(ControlAPIError) in
                let updated = try await client.patch(server: name, ServerPatch(warm: warm))
                await tracker.apply(updated: updated)
            }
        }

        /// Stop serving a server entirely, or start serving it again.
        ///
        /// One PATCH, in the same shape as `setWarm`, and deliberately **not** confirmed: it is
        /// reversible in one press by the row's own `Enable` action and the state is visible on the
        /// row, which is `DESIGN.md` §9's test for what needs a gate. What the router does with it
        /// is a serving decision only — the manifest row, the digest and the approved tool surface
        /// all survive — so nothing here is destructive in the sense that `remove` is.
        func setDisabled(_ name: String, to disabled: Bool) async {
            await write(name) { [client, tracker] () async throws(ControlAPIError) in
                let updated = try await client.patch(server: name, ServerPatch(disabled: disabled))
                await tracker.apply(updated: updated)
            }
        }

        /// Restrict a server to a set of project directories, or clear the restriction.
        ///
        /// An empty array clears it; omitting the field would leave it unchanged, which is why the
        /// array is always sent explicitly in both directions.
        func setProjects(_ name: String, to projects: [String]) async {
            await write(name) { [client, tracker] () async throws(ControlAPIError) in
                let updated = try await client.patch(server: name, ServerPatch(projects: projects))
                await tracker.apply(updated: updated)
            }
        }

        /// Discards a server's stored credentials.
        func signOut(_ name: String) async {
            await write(name) { [client] () async throws(ControlAPIError) in
                _ = try await client.signOut(name)
            }
        }

        func approveHeldChange(_ name: String) async {
            await write(name) { [client] () async throws(ControlAPIError) in
                _ = try await client.approvePendingChange(server: name)
            }
            if rowErrors[name] == nil {
                sheet = nil
                heldChanges = nil
            }
        }

        func remove(_ name: String, keepHistory: Bool) async {
            await write(name) { [client] () async throws(ControlAPIError) in
                _ = try await client.remove(name, keepHistory: keepHistory)
            }
            if rowErrors[name] == nil {
                sheet = nil
                if selection == name { selection = nil }
            }
        }

        func beginAuthorization(_ name: String) async {
            await write(name) { [client, openURL] () async throws(ControlAPIError) in
                let start = try await client.beginAuthorization(for: name)
                await openURL(start.authorizationURL)
            }
        }

        func reopenAuthorizationPage(_ url: String) {
            openURL(url)
        }

        /// Performs a row's own action, whichever it is.
        func perform(_ action: ServerRowAction, on server: MCPServer) async {
            switch action {
            case .enable:
                await setDisabled(server.name, to: false)
            case .reset:
                await reset(server)
            case .reviewHeldChange:
                sheet = .heldChange(server: server.name)
                await loadHeldChanges(server.name)
            case .beginAuthorization:
                await beginAuthorization(server.name)
            case let .reopenAuthorizationPage(url):
                reopenAuthorizationPage(url)
            }
        }

        // MARK: - The held-change sheet's own request

        func loadHeldChanges(_ name: String) async {
            isLoadingHeldChanges = true
            heldChanges = nil
            heldChangesError = nil
            defer { isLoadingHeldChanges = false }
            do {
                heldChanges = try await client.heldChanges(for: name)
            } catch {
                heldChangesError = error
            }
        }

        // MARK: - Adding

        /// Declares a server, and surfaces the router's own advice when it refuses.
        ///
        /// The router replies to a refused add with `{error, hint}` where the hint is the sentence
        /// that turns a dead end into a next step. `Add it anyway` appears only when a hint arrived,
        /// so the app never invents the possibility of forcing.
        func add(_ server: NewServer, force: Bool = false) async {
            addFailure = nil
            addCanForce = false
            do {
                let added = try await client.add(server, force: force)
                // A server adopted with `needsAuth` is a success that still wants something; the
                // row's own action carries that, so the sheet closes.
                _ = added
                sheet = nil
            } catch {
                addFailure = error
                if case let .server(_, _, hint) = error, let hint, !hint.isEmpty {
                    addCanForce = true
                }
            }
        }
    }
#endif
