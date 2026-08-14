import MCPRouterKit
import SwiftUI

/// A tab whose content another item owns, drawn as a designed awaiting state.
///
/// Not a placeholder, and the distinction matters. A tab that opens onto a blank pane reads as a
/// broken app; a tab that opens onto invented rows is worse, because it is a lie that survives
/// until someone taps one. `DESIGN.md` §5's empty-state rule — an illustration, one sentence, one
/// action — applies here with the action omitted, since the action these four will eventually offer
/// does not exist yet and inventing a disabled one would be theatre.
public struct AwaitingTab: View {
    private let icon: Icon
    private let key: PairingCopy.Key

    public init(icon: Icon, key: PairingCopy.Key) {
        self.icon = icon
        self.key = key
    }

    public var body: some View {
        let entry = PairingCopy.entry(key)

        VStack(spacing: PhoneMetric.normal) {
            IconView(icon, size: PhoneMetric.emptyGlyph, weight: .light)
                .foregroundStyle(ColorToken.t3.color)
                .accessibilityHidden(true)

            if let headline = entry.headline {
                Text(headline)
                    .typeRole(.title3)
                    .foregroundStyle(ColorToken.t1.color)
                    .multilineTextAlignment(.center)
            }

            Text(entry.body)
                .typeRole(.body)
                .foregroundStyle(ColorToken.t2.color)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if entry.carriesNarrowing {
                Text(PairingCopy.neverInstalls)
                    .typeRole(.callout)
                    .foregroundStyle(ColorToken.t3.color)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, PhoneMetric.tight)
            }
        }
        .padding(.horizontal, PhoneMetric.section)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ColorToken.ground.color)
    }
}

/// The companion's root: five tabs, iOS grammar, Settings last.
///
/// **No badges anywhere, and their absence is a decision.** A badge is a count, a count is observed
/// data, and this feature observes none of it — I2 and I3 own the things that would be counted. A
/// plausible number on a tab is the fabricated figure `DESIGN.md` §6 forbids, and it is the kind
/// that survives review precisely because it looks like an implementation detail.
public struct PhoneShell<Preview: View>: View {
    @State private var selection: Tab = .settings

    private let pairing: any PairingService
    private let store: any PairingRecordStore
    private let camera: any CameraAuthorizing
    private let openSystemSettings: () -> Void
    private let cameraPreview: (@escaping @MainActor (String) -> Void) -> Preview

    /// The five tabs, in order. `Settings` is last, which is where iOS users look for it.
    public enum Tab: String, CaseIterable, Sendable {
        case discover, triage, queue, library, settings

        /// Sentence case, per `DESIGN.md` §6.
        public var title: String {
            switch self {
            case .discover: "Discover"
            case .triage: "Triage"
            case .queue: "Queue"
            case .library: "Library"
            case .settings: "Settings"
            }
        }

        /// Mapped onto the shared icon set rather than extending it. F2 owns `Icon`, its inventory
        /// is pinned by a count assertion, and growing a shared surface from inside a feature is
        /// how two features end up disagreeing about what the set contains.
        public var icon: Icon {
            switch self {
            case .discover: .discover
            case .triage: .inbox
            case .queue: .tray
            case .library: .book
            case .settings: .settings
            }
        }

        /// The awaiting copy, for the four whose content is another item's.
        public var awaitingKey: PairingCopy.Key? {
            switch self {
            case .discover: .discoverAwaiting
            case .triage: .triageAwaiting
            case .queue: .queueAwaiting
            case .library: .libraryAwaiting
            case .settings: nil
            }
        }
    }

    public init(
        pairing: any PairingService = FixturePairingService(),
        store: any PairingRecordStore = InMemoryPairingStore(),
        camera: any CameraAuthorizing = FixtureCameraAuthorization(),
        openSystemSettings: @escaping () -> Void = {},
        @ViewBuilder cameraPreview: @escaping (@escaping @MainActor (String) -> Void) -> Preview
    ) {
        self.pairing = pairing
        self.store = store
        self.camera = camera
        self.openSystemSettings = openSystemSettings
        self.cameraPreview = cameraPreview
    }

    public var body: some View {
        TabView(selection: $selection) {
            ForEach(Tab.allCases, id: \.self) { tab in
                content(for: tab)
                    .tabItem {
                        Label {
                            Text(tab.title)
                        } icon: {
                            IconView(tab.icon)
                        }
                    }
                    .tag(tab)
            }
        }
        .tint(ColorToken.accent.color)
    }

    @ViewBuilder
    private func content(for tab: Tab) -> some View {
        if let key = tab.awaitingKey {
            NavigationStack {
                AwaitingTab(icon: tab.icon, key: key)
                    .navigationTitle(tab.title)
            }
        } else {
            PhoneSettingsScreen(
                pairing: pairing,
                store: store,
                camera: camera,
                openSystemSettings: openSystemSettings,
                cameraPreview: cameraPreview
            )
        }
    }
}

public extension PhoneShell where Preview == EmptyView {
    /// The shell with no camera preview — what a macOS host test and a SwiftUI preview construct,
    /// since neither has a camera and neither needs one to exercise the surfaces.
    init(
        pairing: any PairingService = FixturePairingService(),
        store: any PairingRecordStore = InMemoryPairingStore(),
        camera: any CameraAuthorizing = FixtureCameraAuthorization(),
        openSystemSettings: @escaping () -> Void = {}
    ) {
        self.init(
            pairing: pairing,
            store: store,
            camera: camera,
            openSystemSettings: openSystemSettings,
            cameraPreview: { _ in EmptyView() }
        )
    }
}
