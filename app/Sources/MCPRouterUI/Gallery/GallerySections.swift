#if DEBUG

    import MCPRouterKit
    import SwiftUI

    // MARK: - Colour

    /// Every token, with both authored appearances written out beside it.
    ///
    /// The two value columns are the point: "light is authored, not inverted" is a claim, and a
    /// reviewer can only check it by seeing the two numbers differ per token and the hierarchy hold
    /// in both. The swatch itself resolves dynamically, so switching the appearance switch moves it.
    struct ColourSection: View {
        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                GalleryGroup(title: "Grounds and lines") {
                    rows([.ground, .panel, .raised, .raised2, .line, .lineStrong])
                }
                GalleryGroup(title: "Label tiers") {
                    rows([.t1, .t2, .t3, .t4])
                }
                GalleryGroup(title: "Fills") {
                    rows([.f1, .f2, .f3])
                }
                GalleryGroup(title: "Meanings — exclusive") {
                    rows([.accent, .live, .attention, .fail, .onAccent])
                }
            }
        }

        private func rows(_ tokens: [ColorToken]) -> some View {
            VStack(spacing: 1) {
                ForEach(tokens, id: \.self) { ColourRow(token: $0) }
            }
        }
    }

    struct ColourRow: View {
        let token: ColorToken

        private var dark: (hex: String, opacity: Double) { token.components(for: .dark) }
        private var light: (hex: String, opacity: Double) { token.components(for: .light) }

        var body: some View {
            HStack(spacing: MetricToken.selectionRadius.leadingScalar) {
                RoundedRectangle(cornerRadius: MetricToken.focusRing.leadingScalar, style: .continuous)
                    .fill(token.color)
                    .overlay(
                        RoundedRectangle(cornerRadius: MetricToken.focusRing.leadingScalar)
                            .strokeBorder(ColorToken.line.color, lineWidth: 1)
                    )
                    .frame(
                        width: MetricToken.controlExtraLarge.leadingScalar,
                        height: MetricToken.controlRegular.leadingScalar
                    )

                Text(token.rawValue)
                    .typeRole(.body, monospaced: true)
                    .foregroundStyle(ColorToken.t1.color)
                    .frame(width: MetricToken.sidebar.leadingScalar / 2, alignment: .leading)

                Text(describe(dark))
                    .typeRole(.caption, monospaced: true)
                    .foregroundStyle(ColorToken.t2.color)
                    .frame(width: MetricToken.sidebar.leadingScalar / 2, alignment: .leading)

                Text(describe(light))
                    .typeRole(.caption, monospaced: true)
                    .foregroundStyle(ColorToken.t2.color)
                    .frame(width: MetricToken.sidebar.leadingScalar / 2, alignment: .leading)

                Spacer(minLength: 0)
            }
            .frame(height: MetricToken.controlLarge.leadingScalar)
        }

        private func describe(_ pair: (hex: String, opacity: Double)) -> String {
            pair.opacity == 1 ? pair.hex : "\(pair.hex) @\(Int(pair.opacity * 100))%"
        }
    }

    // MARK: - Type

    /// The eight roles at their real sizes. Rendering them as a ladder is the only way the
    /// 13pt-body decision is reviewable — a table of numbers proves the numbers, not the result.
    struct TypeSection: View {
        var body: some View {
            GalleryGroup(title: "The ramp — nothing renders off it") {
                VStack(alignment: .leading, spacing: MetricToken.selectionRadius.leadingScalar) {
                    ForEach(TypeToken.allCases, id: \.self) { token in
                        VStack(alignment: .leading, spacing: 0) {
                            Text("The reaper closes an idle server")
                                .typeRole(token)
                                .foregroundStyle(ColorToken.t1.color)
                            Text(caption(token))
                                .typeRole(.caption, monospaced: true)
                                .foregroundStyle(ColorToken.t3.color)
                        }
                    }
                }
            }
        }

        private func caption(_ token: TypeToken) -> String {
            "\(token.rawValue) · \(Int(token.size))/\(Int(token.lineHeight)) · \(token.emphasis.rawValue)"
        }
    }

    // MARK: - Icons

    /// All 21, drawn. A wrong SF Symbol name renders as nothing at all, so seeing the grid is the
    /// check that a name test cannot make.
    struct IconSection: View {
        private let columns = [GridItem(.adaptive(minimum: 88), spacing: 8)]

        var body: some View {
            GalleryGroup(title: "\(Icon.allCases.count) icons — drawn, never unicode") {
                LazyVGrid(columns: columns, spacing: MetricToken.selectionRadius.leadingScalar) {
                    ForEach(Icon.allCases, id: \.self) { icon in
                        VStack(spacing: MetricToken.selectionInset.leadingScalar) {
                            IconView(icon, size: TypeToken.title2.size)
                                .foregroundStyle(ColorToken.t1.color)
                            Text(icon.rawValue)
                                .typeRole(.caption, monospaced: true)
                                .foregroundStyle(ColorToken.t3.color)
                            if icon.isAuthored {
                                Text("authored")
                                    .typeRole(.caption)
                                    .foregroundStyle(ColorToken.accent.color)
                            }
                        }
                        .frame(height: MetricToken.serversRow.leadingScalar)
                    }
                }
            }
        }
    }

    // MARK: - Controls

    struct ControlSection: View {
        @State private var selected = true
        @State private var focused = true

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                GalleryGroup(title: "The ladder — mini 16 to extra large 36") {
                    VStack(alignment: .leading, spacing: MetricToken.selectionInset.leadingScalar) {
                        ForEach(ControlScale.allCases, id: \.self) { scale in
                            HStack(spacing: MetricToken.selectionRadius.leadingScalar) {
                                Button("Start") {}.buttonStyle(ProminentButtonStyle(scale: scale))
                                Button("Inspect") {}.buttonStyle(StandardButtonStyle(scale: scale))
                                Text("\(scale.rawValue) · \(Int(scale.height))pt")
                                    .typeRole(.caption, monospaced: true)
                                    .foregroundStyle(ColorToken.t3.color)
                            }
                        }
                    }
                }
                GalleryGroup(title: "Selection — inset rounded fill, accent label, never full bleed") {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Activity").typeRole(.body).padding(6).selectionFill(false)
                        Text("Servers").typeRole(.body).padding(6).selectionFill(selected)
                        Text("Skills").typeRole(.body).padding(6).selectionFill(false)
                    }
                    .frame(width: MetricToken.sidebar.leadingScalar)
                }
                GalleryGroup(title: "Focus ring — 2pt, accent-bound") {
                    Button("Add server…") {}
                        .buttonStyle(StandardButtonStyle())
                        .focusRing(focused)
                        .padding(MetricToken.selectionInset.leadingScalar)
                }
                GalleryGroup(title: "Disabled — dims in place, reason readable") {
                    DisabledAction()
                }
            }
        }
    }

    // MARK: - Breaker

    /// The signature element, and the one surface where its motion can actually be watched.
    struct BreakerSection: View {
        @State private var live: BreakerState = .dormant

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                GalleryGroup(title: "One dormant state, three lit") {
                    HStack(spacing: MetricToken.selectionRadius.leadingScalar * 2) {
                        ForEach(BreakerState.allCases, id: \.self) { state in
                            VStack(spacing: MetricToken.selectionInset.leadingScalar) {
                                Breaker(state: state)
                                Text(state.rawValue)
                                    .typeRole(.caption, monospaced: true)
                                    .foregroundStyle(ColorToken.t3.color)
                            }
                        }
                    }
                }
                GalleryGroup(title: "Flick it — fast with overshoot up, slow and settling down") {
                    HStack(spacing: MetricToken.selectionRadius.leadingScalar * 2) {
                        BreakerToggle(state: $live)
                            .accessibilityIdentifier("gallery-breaker-toggle")
                        Text(live.accessibilityDescription)
                            .typeRole(.body, monospaced: true)
                            .foregroundStyle(ColorToken.t2.color)
                    }
                }
                GalleryGroup(title: "In a row, at the board's real height") {
                    OverflowRow(state: live)
                        .background(ColorToken.panel.color)
                }
            }
        }
    }

    // MARK: - States

    /// All nine, with the servers board's real copy. Placeholder copy hides both layout and
    /// comprehension failures, so there is none here.
    struct StateSection: View {
        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                GalleryGroup(title: "Default — the populated board") {
                    VStack(spacing: 1) {
                        OverflowRow(name: "filesystem", state: .running)
                        OverflowRow(name: "github", state: .dormant)
                        OverflowRow(name: "sentry", state: .tripped)
                    }
                    .background(ColorToken.panel.color)
                }
                GalleryGroup(title: "Empty") {
                    MessageState(ServersBoardCopy.empty, icon: .conduit)
                }
                GalleryGroup(title: "Loading — skeleton at the real row geometry, never a spinner") {
                    SkeletonRows()
                }
                GalleryGroup(title: "Partial") {
                    MessageState(ServersBoardCopy.partial, icon: .warn, tint: .attention)
                }
                GalleryGroup(title: "Error") {
                    MessageState(ServersBoardCopy.error, icon: .bang, tint: .fail)
                }
                GalleryGroup(title: "Success — in place, no toast") {
                    OverflowRow(name: "filesystem", state: .running)
                        .background(ColorToken.panel.color)
                }
                GalleryGroup(title: "Offline — the router is not running") {
                    MessageState(ServersBoardCopy.offline, icon: .bolt, tint: .attention)
                }
                GalleryGroup(title: "Disabled") {
                    DisabledAction()
                }
                GalleryGroup(title: "Overflow — truncates, row height never moves") {
                    OverflowRow()
                        .background(ColorToken.panel.color)
                }
            }
        }
    }

#endif
