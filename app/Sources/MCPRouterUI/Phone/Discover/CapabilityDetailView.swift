import MCPRouterKit
import SwiftUI

/// One capability, in full, with the security fact before the commit.
///
/// **Detail performs no fetch of its own** (A11). Every field it renders — `install`, `requires`,
/// `archived`, `pushedAt`, `stars`, `source` — already arrived inside the search row, so no new
/// endpoint is added and three of `DESIGN.md` §5's nine states are structurally unreachable here.
/// See `DetailState` for which three and why each cannot occur; they are absent rather than stubbed
/// because writing plausible copy for a state that cannot happen is scaffolding wearing a design's
/// clothes.
struct CapabilityDetailView: View {
    let entry: RegistryEntry
    @Bindable var model: DiscoverModel

    private var plateLines: [CapabilityPlate.Line] {
        CapabilityPlate.lines(install: entry.install, archived: entry.archived)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PhoneMetric.section) {
                header
                chips
                repositoryFact

                // Above the commit, always (A12).
                CapabilityPlateView(
                    lines: plateLines,
                    invocation: CapabilityPlate.invocation(install: entry.install)
                )

                if model.connection == .neverPaired || model.connection == .notReachable {
                    offlineNote
                }
            }
            .padding(PhoneMetric.loose)
        }
        .background(ColorToken.ground.color)
        .safeAreaInset(edge: .bottom) {
            QueueCommitBar(
                state: model.commitState(for: entry),
                entry: commitCopy,
                failure: model.queueFailure,
                action: { Task { await model.enqueue(entry) } }
            )
        }
        .navigationTitle(entry.displayName)
        // iOS-only, and the host tests build this file for macOS. Overflow's "truncates in the
        // collapsed navigation bar" is an iOS behaviour, so the modifier is guarded rather than
        // the file — the rest of Detail is identical on both and is what the host tests exercise.
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await model.refreshQueuedState(for: entry) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: PhoneMetric.normal) {
            RoundedRectangle(cornerRadius: PhoneMetric.detailTileRadius)
                .fill(ColorToken.raised.color)
                .frame(width: PhoneMetric.detailTile, height: PhoneMetric.detailTile)
                .overlay {
                    IconView(.discover, size: PhoneMetric.detailTile / 2)
                        .foregroundStyle(ColorToken.t3.color)
                }
                .accessibilityHidden(true)

            // Overflow: a long name wraps to two lines here and truncates in the collapsed
            // navigation bar. The full value is always readable on this surface.
            Text(entry.displayName)
                .typeRole(.title1)
                .foregroundStyle(ColorToken.t1.color)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Text(entry.description)
                .typeRole(.body)
                .foregroundStyle(ColorToken.t2.color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The fact chips are enumerated, and `verified` is **not** among them (A15).
    ///
    /// `verified` is Smithery's claim about itself, the router verifies nothing, and a bare
    /// "Verified" chip displays an assurance nobody established.
    private var chips: some View {
        HStack(spacing: PhoneMetric.snug) {
            chip(DiscoverCopy.entry(sourceKey).body)
            if entry.archived == true {
                chip(DiscoverCopy.entry(.chipArchived).body)
            }
            if let stars = DiscoverPresentation.starsText(entry) {
                chip(stars)
            }
            Spacer(minLength: 0)
        }
    }

    private var sourceKey: DiscoverCopy.Key {
        switch entry.source {
        case .official: .chipSourceOfficial
        case .smithery: .chipSourceSmithery
        case .both: .chipSourceBoth
        }
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .typeRole(.caption, monospaced: true)
            .foregroundStyle(ColorToken.t2.color)
            .padding(.horizontal, PhoneMetric.snug)
            .frame(height: PhoneMetric.chipHeight)
            .background(
                RoundedRectangle(cornerRadius: PhoneMetric.chipRadius)
                    .fill(ColorToken.f3.color)
            )
    }

    /// The repository activity the third band would have ranked on, as a per-entry fact.
    ///
    /// Where it is missing, the reason is stated rather than the row silently disappearing — and
    /// the two reasons are different states. A26: a Smithery-hosted entry is a **fact**, because
    /// GitHub was never asked; a rate limit is a **partial**, because it was asked and refused.
    @ViewBuilder
    private var repositoryFact: some View {
        if let lastCommit = DiscoverPresentation.lastCommitText(entry) {
            Text(lastCommit)
                .typeRole(.callout, monospaced: true)
                .foregroundStyle(ColorToken.t2.color)
        } else {
            let key: DiscoverCopy.Key = entry.source == .smithery
                ? .detailPartialNoRepository
                : .detailPartialGitHubLimited
            let copy = DiscoverCopy.entry(key)
            VStack(alignment: .leading, spacing: PhoneMetric.tight) {
                if let headline = copy.headline {
                    Text(headline)
                        .typeRole(.callout)
                        .foregroundStyle(ColorToken.t1.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(copy.body)
                    .typeRole(.caption)
                    .foregroundStyle(ColorToken.t3.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// A27 on Detail: the router being down does not stop a local save, so this states where the
    /// item goes rather than refusing the act.
    private var offlineNote: some View {
        let copy = model.copy(.detailOffline)
        return VStack(alignment: .leading, spacing: PhoneMetric.tight) {
            if let headline = copy.headline {
                Text(headline)
                    .typeRole(.callout)
                    .foregroundStyle(ColorToken.t1.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(copy.body)
                .typeRole(.caption)
                .foregroundStyle(ColorToken.t2.color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var commitCopy: DiscoverCopy.Entry {
        model.copy(model.commitState(for: entry).copyKey, extra: [.name: entry.displayName])
    }
}
