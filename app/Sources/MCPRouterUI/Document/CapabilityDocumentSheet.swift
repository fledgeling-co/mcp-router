#if os(macOS)
    import MCPRouterKit
    import SwiftUI

    /// The capability document panel: three tabs over one sheet.
    ///
    /// The surface `design/mcp-router-console.html`'s `sh-readme` draws — a titlebar with the
    /// capability's name, its version and three tabs; a product header carrying the mark, name,
    /// publisher and pitch; a five-cell facts strip; then the document itself, scrolling inside a
    /// capped body.
    ///
    /// **The header does not scroll away**, which is the mock's own recorded reason for it
    /// (`:1160-1162`): the reader's question eight paragraphs into a read me is still "and do I
    /// install it". So it sits between the titlebar and the scroll rather than inside it.
    ///
    /// **The actions are the caller's, and the sheet fabricates none.** The mock draws `Install…`,
    /// `What changed…` and `Update to 1.5.0`; this panel can perform none of the three, and the
    /// install flow belongs to the item that owns the sheet inventory. `actions` is the seam that
    /// item passes them through. Rendered with none — which is what the measurement harness and the
    /// gallery do — the foot carries `Close` and, where the capability declares an `https`
    /// repository, one link out to it.
    public struct CapabilityDocumentSheet: View {
        /// What the panel has to draw. Three states rather than one: `DESIGN.md` §5 is that a
        /// populated-only screen is a third of a design, and the two unhappy ones here are real —
        /// a source that has not answered, and a source that cannot.
        public enum Content: Equatable, Sendable {
            case loading
            case document(CapabilityDocument)
            case unavailable(CapabilityDocumentError)
        }

        /// A press the caller can perform. The sheet renders it and knows nothing about it.
        public struct Action: Identifiable, Sendable {
            public var id: String { label }
            public var label: String
            public var isProminent: Bool
            public var run: @MainActor @Sendable () -> Void

            public init(
                label: String,
                isProminent: Bool = false,
                run: @escaping @MainActor @Sendable () -> Void
            ) {
                self.label = label
                self.isProminent = isProminent
                self.run = run
            }
        }

        let content: Content
        var actions: [Action] = []
        var dismiss: (@MainActor @Sendable () -> Void)?

        @State private var tab: CapabilityDocument.Tab

        /// Which tab the panel opens on.
        ///
        /// `.readMe` for every caller in the product — a reader arrives at a capability to decide
        /// whether to install it, and the read me is that document. The parameter exists for the
        /// measurement harness: the tab is `@State` and switching it is a press, which a headless
        /// render has no way to perform, so a frame of the changelog could not be taken at all and
        /// the panel's other two tabs had never been photographed carrying a document.
        public init(
            content: Content,
            actions: [Action] = [],
            initialTab: CapabilityDocument.Tab = .readMe,
            dismiss: (@MainActor @Sendable () -> Void)? = nil
        ) {
            self.content = content
            self.actions = actions
            self.dismiss = dismiss
            _tab = State(initialValue: initialTab)
        }

        public var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                titlebar
                if case let .document(document) = content {
                    CapabilityDocumentHeader(identity: document.identity)
                    CapabilityFactsStrip(facts: document.facts)
                }
                body(for: content)
                foot
            }
            .frame(width: DocumentMetrics.sheetWidth)
            .background(ColorToken.ground.color)
            // `Esc` dismisses the sheet (`DESIGN.md` §8). Supplied by the caller, because a sheet
            // does not know whether it is presented or hosted — the measurement harness hosts it.
            .onExitCommand { dismiss?() }
            .measured("readme-sheet", role: "sheet", kind: .vstack, alignment: "leading")
        }

        // MARK: - Titlebar and tabs

        private var titlebar: some View {
            HStack(spacing: DocumentMetrics.gap) {
                Text(name)
                    .typeRole(.body, monospaced: true)
                    .foregroundStyle(ColorToken.t1.color)
                if let version {
                    VersionPill(text: version)
                }
                Spacer(minLength: 0)
                ForEach(CapabilityDocument.Tab.allCases) { candidate in
                    tabButton(candidate)
                }
            }
            .padding(.horizontal, DocumentMetrics.bandPadding)
            .frame(height: DocumentMetrics.titlebarHeight)
            .background(ColorToken.chrome.color)
            .overlay(alignment: .bottom) {
                Rectangle().fill(ColorToken.line.color).frame(height: DocumentMetrics.hairline)
            }
            .measured(
                "sheet-titlebar", role: "titlebar", kind: .hstack,
                tokens: ["background": .chrome], text: name
            )
        }

        /// A tab, not a segmented control: `DESIGN.md` §3 rule 6 reserves segmented controls for
        /// switching views in place, and this is switching **documents** inside one view — the same
        /// distinction the mock draws by giving the sheet `role="tab"` buttons.
        private func tabButton(_ candidate: CapabilityDocument.Tab) -> some View {
            let isSelected = candidate == tab
            return Button { tab = candidate } label: {
                Text(candidate.title)
                    .typeRole(.body)
                    .foregroundStyle((isSelected ? ColorToken.t1 : ColorToken.t2).color)
                    .padding(.horizontal, DocumentMetrics.quoteInset)
                    .frame(height: DocumentMetrics.tabHeight)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill((isSelected ? ColorToken.accentInk : ColorToken.line).color)
                            .frame(height: isSelected ? DocumentMetrics.tabUnderline : 0)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
            .measured(
                "tab-\(candidate.rawValue)", role: "tab", kind: .leaf,
                tokens: ["foreground": isSelected ? .t1 : .t2], type: .body, text: candidate.title
            )
        }

        private var name: String {
            if case let .document(document) = content { return document.identity.name }
            return "Documentation"
        }

        private var version: String? {
            guard case let .document(document) = content else { return nil }
            return document.identity.version
        }

        // MARK: - The body

        private func body(for content: Content) -> some View {
            ScrollView {
                Group {
                    switch content {
                    case .loading:
                        DocumentSkeleton()
                    case let .document(document):
                        if let blocks = document.blocks(for: tab) {
                            blockStack(blocks, document: document)
                        } else {
                            note(tab.absentSentence)
                        }
                    case let .unavailable(error):
                        unavailable(error)
                    }
                }
                .padding(DocumentMetrics.bodyPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: DocumentMetrics.bodyMaxHeight)
            .background(ColorToken.ground.color)
            .measured("sheet-body", role: "detail", kind: .scroll, alignment: "leading")
        }

        private func blockStack(_ blocks: [MarkdownBlock], document: CapabilityDocument) -> some View {
            VStack(alignment: .leading, spacing: DocumentMetrics.blockGap) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { offset, block in
                    MarkdownBlockView(
                        block: block, index: offset,
                        images: document.images, refusals: document.refusedImages
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        /// A tab the capability published nothing for. Names the document rather than saying "no
        /// content", and says the other tabs are still there — the reader arrived to make a
        /// decision and one missing document does not end it (`DESIGN.md` §6).
        private func note(_ sentence: String) -> some View {
            Text(sentence)
                .typeRole(.body)
                .foregroundStyle(ColorToken.t2.color)
                .fixedSize(horizontal: false, vertical: true)
                .measured("state-detail", role: "state-detail", kind: .text, type: .body, text: sentence)
        }

        /// Nothing this app can reach serves documentation. Stated in its own words, adjacent to
        /// where it would have been, with no invented next step where there is none.
        private func unavailable(_ error: CapabilityDocumentError) -> some View {
            VStack(alignment: .leading, spacing: DocumentMetrics.tightGap) {
                Text(error.headline)
                    .typeRole(.title3)
                    .foregroundStyle(ColorToken.t1.color)
                    .measured(
                        "state-title", role: "state-title", kind: .text,
                        type: .title3, text: error.headline
                    )
                Text(error.advice)
                    .typeRole(.body)
                    .foregroundStyle(ColorToken.t2.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .measured(
                        "state-detail", role: "state-detail", kind: .text,
                        type: .body, text: error.advice
                    )
            }
        }

        // MARK: - The foot

        /// Cancel leads, one prominent action trails (`DESIGN.md` §3 rule 4).
        private var foot: some View {
            HStack(spacing: DocumentMetrics.tightGap) {
                if case let .document(document) = content, let repository = document.identity.repository {
                    // **"Open in your browser", not the mock's "Open on GitHub".** The destination
                    // is whatever the capability declared, and this app does not know it is
                    // GitHub — naming a host it has not checked is the honesty rule pointed
                    // outward. Declared in `planning/fidelity/readme.layers.json` as D7.
                    Link(Self.openLabel, destination: repository)
                        .buttonStyle(StandardButtonStyle())
                        .measured(
                            "open-repository", role: "state-action", kind: .leaf,
                            type: .body, text: Self.openLabel
                        )
                }
                Spacer(minLength: 0)
                Button("Close") { dismiss?() }
                    .buttonStyle(StandardButtonStyle())
                    .keyboardShortcut(.cancelAction)
                    .measured("close", role: "state-action", kind: .leaf, type: .body, text: "Close")
                ForEach(actions) { action in
                    button(for: action)
                }
            }
            .padding(.horizontal, DocumentMetrics.bandPadding)
            .padding(.vertical, DocumentMetrics.quoteInset)
            .background(ColorToken.panel.color)
            .overlay(alignment: .top) {
                Rectangle().fill(ColorToken.line.color).frame(height: DocumentMetrics.hairline)
            }
            .measured("sheet-foot", role: "action-bar", kind: .hstack, tokens: ["background": .panel])
        }

        static let openLabel = "Open in your browser"

        /// One caller-supplied press. Two branches rather than a type-erased style: `AnyView` is
        /// not `Sendable`, so erasing a `ButtonStyle` behind one does not compile under strict
        /// concurrency, and a `Group` with two arms is the shorter thing anyway.
        @ViewBuilder
        private func button(for action: Action) -> some View {
            if action.isProminent {
                Button(action.label) { action.run() }
                    .buttonStyle(ProminentButtonStyle())
            } else {
                Button(action.label) { action.run() }
                    .buttonStyle(StandardButtonStyle())
            }
        }
    }

    /// The version chip beside the capability's name, at the mock's own pill shape.
    struct VersionPill: View {
        let text: String

        var body: some View {
            Text(text)
                .typeRole(.subheadline)
                .foregroundStyle(ColorToken.t2.color)
                .padding(.horizontal, DocumentMetrics.tightGap)
                .frame(height: DocumentMetrics.shieldHeight)
                .background {
                    Capsule().fill(ColorToken.raised.color)
                }
                .overlay {
                    Capsule().strokeBorder(ColorToken.line.color, lineWidth: DocumentMetrics.hairline)
                }
        }
    }

    /// The loading state: bands at the geometry the real content occupies, so nothing moves when the
    /// document lands. Never a spinner over a blank pane (`DESIGN.md` §5).
    struct DocumentSkeleton: View {
        var body: some View {
            VStack(alignment: .leading, spacing: DocumentMetrics.blockGap) {
                bar(fraction: 0.45, height: TypeToken.title1.lineHeight)
                bar(fraction: 1.0, height: TypeToken.body.lineHeight)
                bar(fraction: 0.9, height: TypeToken.body.lineHeight)
                bar(fraction: 0.6, height: TypeToken.body.lineHeight)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("Loading this capability's documentation")
        }

        private func bar(fraction: Double, height: Double) -> some View {
            RoundedRectangle(cornerRadius: DocumentMetrics.shieldRadius, style: .continuous)
                .fill(ColorToken.f2.color)
                .frame(width: DocumentMetrics.sheetWidth * fraction * 0.8, height: height)
        }
    }
#endif
