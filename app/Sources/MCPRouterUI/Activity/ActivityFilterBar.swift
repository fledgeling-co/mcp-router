#if os(macOS)
    import MCPRouterKit
    import SwiftUI

    /// The two filters, as pop-up buttons.
    ///
    /// `DESIGN.md` §3.6: a pop-up button shows a value and offers an exclusive set; a pull-down has
    /// a static title; a segmented control switches views in place and is never primary navigation.
    /// Each of these shows the current choice, so each is a pop-up.
    ///
    /// **Every option is built from the loaded records.** An option cannot exist without at least
    /// one record behind it, because the options are produced by grouping the records — so the menu
    /// can never offer a choice that would return nothing, and the count beside each is a count the
    /// router observed rather than one this view estimated.
    struct ActivityFilterBar: View {
        @Bindable var model: ActivityModel

        var body: some View {
            VStack(alignment: .leading, spacing: MetricToken.selectionInset.leadingScalar) {
                HStack(spacing: MetricToken.selectionRadius.leadingScalar - 1) {
                    sessionMenu
                    directoryMenu

                    if model.filter.isActive {
                        // A plain text button, not the view's prominent action: it undoes a view
                        // choice rather than committing anything (§3.4 — one prominent accent-filled
                        // action per view, and this board's states own it).
                        Button(ActivityCopy.clearFilters) { model.clearFilters() }
                            .buttonStyle(.plain)
                            .typeRole(.callout)
                            .foregroundStyle(ColorToken.accent.color)
                            .accessibilityIdentifier(Self.clearIdentifier)

                        Spacer(minLength: 0)

                        // The only place a filtered board states what it is hiding. Without it a
                        // filter matching nothing looks exactly like a router with nothing to say.
                        Text(
                            ActivityCopy.filteredCount(
                                visible: model.result.visible.count,
                                total: model.result.total
                            )
                        )
                        .typeRole(.subheadline, monospaced: true)
                        .foregroundStyle(ColorToken.t3.color)
                        .accessibilityIdentifier(Self.countIdentifier)
                    } else {
                        Spacer(minLength: 0)
                    }
                }

                if !model.filtersEnabled {
                    // §3.4: dims in place with a discoverable reason, never hidden. One sentence for
                    // two controls, because they share one cause.
                    Text(ActivityCopy.disabledFilters)
                        .typeRole(.callout)
                        .foregroundStyle(ColorToken.t2.color)
                        .accessibilityIdentifier(Self.disabledReasonIdentifier)
                }
            }
            .padding(.horizontal, ActivityColumn.inset)
            .padding(.bottom, MetricToken.selectionRadius.leadingScalar)
        }

        static let sessionIdentifier = "activity-filter-session"
        static let directoryIdentifier = "activity-filter-project"
        static let clearIdentifier = "activity-clear-filters"
        static let countIdentifier = "activity-filter-count"
        static let disabledReasonIdentifier = "activity-filters-disabled-reason"

        static let allSessions = "All sessions"
        static let allProjects = "All projects"
        static let sessionLabel = "Session"
        static let directoryLabel = "Project"

        private var sessionMenu: some View {
            FilterPopUp(
                label: Self.sessionLabel,
                value: model.filter.session?.label ?? Self.allSessions,
                isEnabled: model.filtersEnabled,
                identifier: Self.sessionIdentifier
            ) {
                Button(Self.allSessions) { model.filter.session = nil }
                Divider()
                ForEach(model.sessions) { option in
                    Button("\(option.label)  ·  \(option.calls)") {
                        model.filter.session = option.key
                    }
                }
            }
        }

        private var directoryMenu: some View {
            FilterPopUp(
                label: Self.directoryLabel,
                value: model.filter.directory?.label ?? Self.allProjects,
                isEnabled: model.filtersEnabled,
                identifier: Self.directoryIdentifier
            ) {
                Button(Self.allProjects) { model.filter.directory = nil }
                Divider()
                ForEach(model.directories) { option in
                    Button("\(option.label)  ·  \(option.calls)") {
                        model.filter.directory = option.key
                    }
                }
            }
        }
    }

    /// A pop-up button drawn from the tokens: a quiet label, the current value, and the double
    /// chevron that tells a Mac user this shows a value rather than performing an action.
    struct FilterPopUp<Content: View>: View {
        let label: String
        let value: String
        let isEnabled: Bool
        let identifier: String
        @ViewBuilder let content: () -> Content

        @State private var isHovered = false

        var body: some View {
            Menu {
                content()
            } label: {
                HStack(spacing: MetricToken.selectionInset.leadingScalar + 2) {
                    Text(label)
                        .typeRole(.callout)
                        .foregroundStyle(isEnabled ? ColorToken.t3.color : ColorToken.t4.color)
                    Text(value)
                        .typeRole(.callout)
                        .foregroundStyle(isEnabled ? ColorToken.t1.color : ColorToken.t4.color)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    // `chevron.up.chevron.down` is the kit's own pop-up indicator. §3.6 turns on the
                    // difference between this and a single chevron, so it is drawn from the system
                    // set rather than approximated.
                    Image(systemName: "chevron.up.chevron.down")
                        .font(TypeToken.caption.font)
                        .foregroundStyle(isEnabled ? ColorToken.t2.color : ColorToken.t4.color)
                }
                .padding(.horizontal, MetricToken.selectionRadius.leadingScalar)
                .frame(height: MetricToken.controlRegular.leadingScalar)
                .background(
                    RoundedRectangle(cornerRadius: MetricToken.selectionInset.leadingScalar + 1)
                        .fill(background)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: MetricToken.selectionInset.leadingScalar + 1)
                        .strokeBorder(
                            isEnabled ? ColorToken.lineStrong.color : ColorToken.line.color
                        )
                )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(!isEnabled)
            .onHover { isHovered = $0 }
            .accessibilityIdentifier(identifier)
            .accessibilityLabel(label)
            .accessibilityValue(value)
        }

        private var background: Color {
            guard isEnabled else { return ColorToken.f3.color }
            return isHovered ? ColorToken.raised2.color : ColorToken.raised.color
        }
    }
#endif
