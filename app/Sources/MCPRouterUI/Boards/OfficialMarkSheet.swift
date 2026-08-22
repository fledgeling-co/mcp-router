#if os(macOS)
    import MCPRouterKit
    import SwiftUI

    /// What the Official mark asserts — opened from `What is official?` in Discover's controls.
    ///
    /// The mock's own reason for it, in the comment above `id="sh-official"`: *"A verified mark
    /// with no definition behind it is a trust signal the product has not earned; this is the
    /// definition."*
    ///
    /// It has one action and it is not destructive, so that one control is both the prominent
    /// action and the way out — `DESIGN.md` §3.4's one prominent action, and the brief's
    /// at-most-one-filled primary. The mock's publisher grid is absent and says so on the surface;
    /// `OfficialMarkCopy` carries why.
    ///
    /// **It carries Escape rather than Return, and that is a measured trade rather than a
    /// preference.** As drawn by M18 it held `.defaultAction` alone, so Escape did nothing at all
    /// on it — the M18 verdict's Finding 3, and `planning/evidence/M18-gapfix-2/` measures both
    /// that (`NEITHER` on a posted keycode 53) and why one control cannot simply hold both keys:
    /// SwiftUI keeps the innermost `.keyboardShortcut` and drops the other, whichever order they
    /// are written in. So one key was available and `DESIGN.md` §8 gives `Esc` to dismissing.
    /// The workaround that keeps both — a zero-size zero-opacity twin holding `.cancelAction` —
    /// was measured working and rejected: an invisible duplicate of the only control on the
    /// surface costs more than the key it buys.
    struct OfficialMarkSheet: View {
        @Bindable var board: DiscoverBoardModel

        var body: some View {
            SheetFrame(title: OfficialMarkCopy.title) {
                VStack(alignment: .leading, spacing: DiscoverBoardMetrics.gap) {
                    Text(OfficialMarkCopy.lede)
                        .typeRole(.body)
                        .foregroundStyle(ColorToken.t2.color)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(OfficialMarkCopy.conditionsHeading)
                        .typeRole(.caption)
                        .foregroundStyle(ColorToken.t3.color)

                    VStack(alignment: .leading, spacing: DiscoverBoardMetrics.tightGap) {
                        ForEach(Array(OfficialMarkCopy.conditions.enumerated()), id: \.offset) { pair in
                            HStack(alignment: .firstTextBaseline, spacing: DiscoverBoardMetrics.tightGap) {
                                Text("\(pair.offset + 1).")
                                    .typeRole(.body, monospaced: true)
                                    .foregroundStyle(ColorToken.t3.color)
                                Text(pair.element)
                                    .typeRole(.body)
                                    .foregroundStyle(ColorToken.t2.color)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    // §5's partial state: what did not arrive, and why. A section that simply
                    // vanished would read as a design that never had one. Same shape as
                    // `PartialIndexNote`, which reports the same class of thing.
                    Banner(icon: .bang, tint: .attention) {
                        Text(OfficialMarkCopy.publishersUnavailable)
                    }

                    Text(OfficialMarkCopy.limitsHeading)
                        .typeRole(.caption)
                        .foregroundStyle(ColorToken.t3.color)

                    Text(OfficialMarkCopy.limits)
                        .typeRole(.body)
                        .foregroundStyle(ColorToken.t2.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } actions: {
                Button(OfficialMarkCopy.dismiss) { board.sheet = nil }
                    .buttonStyle(ProminentButtonStyle())
                    .keyboardShortcut(.cancelAction)
            }
        }
    }

    /// Where the router's children look for their binaries — a refusal, and honestly so.
    ///
    /// Attached to the **Settings** window rather than the console, which is the brief's one
    /// requirement with no reference to build against: *"A sheet opened from the Settings window
    /// attaches to the Settings window"*, and the mock draws both windows on one page so it cannot
    /// demonstrate it. `ChildPathCopy` carries why the numbers are not drawn.
    struct ChildPathSheet: View {
        let dismiss: () -> Void

        var body: some View {
            SheetFrame(title: ChildPathCopy.title) {
                VStack(alignment: .leading, spacing: SettingsMetrics.gap) {
                    Text(ChildPathCopy.lede)
                        .typeRole(.body)
                        .foregroundStyle(ColorToken.t2.color)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(ChildPathCopy.unavailableHeading)
                        .typeRole(.caption)
                        .foregroundStyle(ColorToken.t3.color)

                    Text(ChildPathCopy.unavailable)
                        .typeRole(.body)
                        .foregroundStyle(ColorToken.t2.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } actions: {
                // Escape rather than Return, for the reason `OfficialMarkSheet` states above.
                Button(ChildPathCopy.dismiss, action: dismiss)
                    .buttonStyle(ProminentButtonStyle())
                    .keyboardShortcut(.cancelAction)
            }
        }
    }
#endif
