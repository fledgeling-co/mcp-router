import MCPRouterKit
import SwiftUI

/// An unhappy state, drawn the way `DESIGN.md` §5 asks: an illustration, one sentence, one action.
///
/// A phone-sized sibling of `MessageState` rather than a reuse of it. That view frames itself
/// against `MetricToken.sidebar` and `MetricToken.titlebar` — macOS chrome geometry, marked
/// `(specified)` against Apple's Mac kit — and a phone has neither a sidebar nor a titlebar.
/// Stretching those values over an iOS layout is exactly the "Mac app's chrome on a phone" the
/// product rules out. The illustration and spacing follow `AwaitingTab`, which is how I1 draws the
/// same shape.
struct DiscoverMessageState: View {
    let entry: DiscoverCopy.Entry
    var icon: Icon = .discover
    var tint: ColorToken = .t3
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: PhoneMetric.normal) {
            IconView(icon, size: PhoneMetric.emptyGlyph, weight: .light)
                .foregroundStyle(tint.color)
                .accessibilityHidden(true)

            if let headline = entry.headline {
                Text(headline)
                    .typeRole(.title3)
                    .foregroundStyle(ColorToken.t1.color)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(entry.body)
                .typeRole(.body)
                .foregroundStyle(ColorToken.t2.color)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let label = entry.actionLabel, let action {
                Button(label, action: action)
                    .buttonStyle(PhoneProminentButtonStyle())
                    .frame(minHeight: PhoneMetric.minimumTarget)
            }
        }
        .padding(.horizontal, PhoneMetric.section)
        .padding(.vertical, PhoneMetric.section)
        .frame(maxWidth: .infinity)
    }
}

/// One band: a sentence-case header, its note, and its rows — or its own empty state.
struct DiscoverBandSection: View {
    let band: DiscoverBand
    let entries: [RegistryEntry]
    /// Whether this band is empty **within a populated list** — the A5 case.
    ///
    /// Supplied by the model rather than derived from `entries.isEmpty` here, so the one guard
    /// that knows the difference between "this band has nothing" and "the search returned
    /// nothing" is the one that decides. Derived locally it was the same expression minus that
    /// distinction, and `DiscoverBands.isBandEmptyWithinResults` had no caller at all — a proven
    /// function guarding nothing while the view re-implemented it without the guard.
    let isEmptyWithinResults: Bool
    let window: RecencyWindow
    let onSelect: (RegistryEntry) -> Void
    let onResetWindow: () -> Void

    var body: some View {
        Section {
            if isEmptyWithinResults {
                // A5: one band empty while the other is populated is the common case, not an edge
                // case, and it is not the whole-list Empty state. Its own copy, and an action only
                // where one exists.
                DiscoverMessageState(
                    entry: DiscoverCopy.entry(bandEmptyKey).resolved(bandEmptySubstitutions),
                    icon: .discover,
                    action: bandEmptyKey == .list(.bandEmptyRecentlyChangedWindowed)
                        ? onResetWindow
                        : nil
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(entries) { entry in
                    Button { onSelect(entry) } label: {
                        DiscoverRow(entry: entry, band: band)
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            VStack(alignment: .leading, spacing: PhoneMetric.tight) {
                // Sentence case, system font, secondary colour — `DESIGN.md` §3.2. Tracked
                // uppercase is the loudest web tell, and the fix is removing it rather than
                // adjusting its tracking.
                Text(DiscoverCopy.entry(band.titleKey).body)
                    .typeRole(.subheadline)
                    .foregroundStyle(ColorToken.t3.color)
                    .textCase(nil)

                // One quiet secondary sentence under its control (`DESIGN.md` §6). Every note is
                // scoped to the results shown — the endpoint sorts by popularity and then
                // truncates, so no band may assert an index-wide fact (A3).
                Text(DiscoverCopy.entry(band.noteKey).body)
                    .typeRole(.caption)
                    .foregroundStyle(ColorToken.t3.color)
                    .textCase(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, PhoneMetric.tight)
        }
    }

    /// Which empty sentence this band gets.
    ///
    /// Three, not one. Most used does not respond to the window (A4), so a sentence about a
    /// window is false there and its "widen the window" action cannot change what is shown. And
    /// Recently changed under Any time has no window applied either, so the windowed sentence
    /// rendered "…in the last Any time days" — ungrammatical, false, and offering a reset to the
    /// window already selected.
    private var bandEmptyKey: DiscoverCopy.Key {
        switch band {
        case .mostUsed:
            .list(.bandEmptyMostUsed)
        case .recentlyChanged where window.days == nil:
            .list(.bandEmptyRecentlyChangedAnyTime)
        case .recentlyChanged:
            .list(.bandEmptyRecentlyChangedWindowed)
        }
    }

    /// Only the windowed sentence carries a substitution, and only there is `days` non-nil.
    private var bandEmptySubstitutions: [DiscoverCopy.Token: String] {
        guard let days = window.days else { return [:] }
        return [.window: String(days)]
    }
}

/// The window control: four options, filtering one band.
///
/// A pop-up button rather than a pull-down, because it shows a value (`DESIGN.md` §3.6). During a
/// search it **dims in place** with its reason beside it and is never hidden — §3.4 requires a
/// disabled control to dim in place with a discoverable reason, and hiding it would make the
/// asymmetry vanish exactly when the user is wondering where it went (A10).
struct DiscoverWindowControl: View {
    @Binding var window: RecencyWindow
    let isSearching: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: PhoneMetric.tight) {
            HStack(spacing: PhoneMetric.snug) {
                Text(DiscoverCopy.entry(.window(.label)).body)
                    .typeRole(.subheadline)
                    .foregroundStyle(ColorToken.t3.color)

                Picker(DiscoverCopy.entry(.window(.label)).body, selection: $window) {
                    ForEach(RecencyWindow.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .disabled(isSearching)
                .frame(minHeight: PhoneMetric.minimumTarget)

                Spacer(minLength: 0)
            }

            Text(reason)
                .typeRole(.caption)
                .foregroundStyle(isSearching ? ColorToken.t4.color : ColorToken.t3.color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// A4 and A10: the control says which band it drives, and says why it is inert during a search.
    /// Both asymmetries are stated rather than left to be discovered — the tidier alternatives
    /// (windowing both bands, hiding the control) are false.
    private var reason: String {
        DiscoverCopy.entry(isSearching ? .window(.disabledInSearch) : .window(.appliesTo)).body
    }
}
