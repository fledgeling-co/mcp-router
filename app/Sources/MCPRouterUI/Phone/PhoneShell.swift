import MCPRouterKit
import SwiftUI

/// The companion's root: five tabs, iOS grammar, Settings last.
///
/// **No badges anywhere, and their absence is a decision.** A badge is a count, a count is observed
/// data, and this shell observes none of it. A plausible number on a tab is the fabricated figure
/// `DESIGN.md` §6 forbids, and it is the kind that survives review precisely because it looks like
/// an implementation detail. Triage's bucket counts are a different thing: they are the sizes of
/// sets the user's own decisions produced, and they sit on the surface that produced them.
///
/// **`AwaitingTab` is gone as of I3**, along with `awaitingKey` and all four of `PairingCopy`'s
/// awaiting entries. Every tab now resolves to a real surface, which is the phone's analogue of the
/// Mac placeholder retiring at M6.
public struct PhoneShell<Preview: View>: View {
    @State private var selection: Tab

    private let pairing: any PairingService
    private let store: any PairingRecordStore
    private let camera: any CameraAuthorizing
    private let openSystemSettings: () -> Void
    private let cameraPreview: (@escaping @MainActor (String) -> Void) -> Preview

    /// The surfaces' dependencies. Defaulted so every existing preview and macOS host test keeps
    /// constructing the shell unchanged — callers that predate a feature should not have to learn
    /// about it to keep compiling.
    private let client: any ControlAPIClient
    private let queue: any CapabilityQueueWriter & CapabilityQueueReader
    private let dismissals: any DismissalStore
    private let connection: ConnectionState
    private let macName: String?

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
    }

    public init(
        pairing: any PairingService = FixturePairingService(),
        store: any PairingRecordStore = InMemoryPairingStore(),
        camera: any CameraAuthorizing = FixtureCameraAuthorization(),
        client: any ControlAPIClient = FixtureControlAPIClient(),
        queue: any CapabilityQueueWriter & CapabilityQueueReader = InMemoryCapabilityQueue(),
        dismissals: any DismissalStore = InMemoryDismissalStore(),
        connection: ConnectionState = .reachable,
        macName: String? = nil,
        initialTab: Tab = .settings,
        openSystemSettings: @escaping () -> Void = {},
        @ViewBuilder cameraPreview: @escaping (@escaping @MainActor (String) -> Void) -> Preview
    ) {
        self.pairing = pairing
        self.store = store
        self.camera = camera
        self.client = client
        self.queue = queue
        self.dismissals = dismissals
        self.connection = connection
        self.macName = macName
        // Seeded rather than hardcoded, so A30's per-tab assertion can host the shell *on* a tab.
        // The default is unchanged, so nothing about the shipped app moves: Settings is where a
        // phone with no paired Mac has to open, because pairing is the only useful act there.
        //
        // The criterion needs this. The claim is "each of Triage, Queue and Library renders its own
        // surface", and the failure it exists to catch — three tabs all rendering Settings — is
        // indistinguishable from success unless a test can select a tab and read what came back.
        _selection = State(initialValue: initialTab)
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

    /// **An exhaustive `switch`, one case per surface**, and the exhaustiveness is the guard.
    ///
    /// The previous shape was `if .discover { … } else if let key = awaitingKey { … } else {
    /// PhoneSettingsScreen }`. Under that shape, making `awaitingKey` return nil for the three
    /// remaining tabs would not have retired the placeholder — it would have routed Triage, Queue
    /// and Library to the **final `else`**, so all three would have rendered Settings while every
    /// "no awaiting copy is compiled" check stayed green. A `switch` cannot fail that way: a sixth
    /// tab added without a surface does not compile.
    @ViewBuilder
    private func content(for tab: Tab) -> some View {
        switch tab {
        case .discover:
            DiscoverScreen(
                client: client,
                queue: queue,
                connection: connection,
                macName: macName
            )
        case .triage:
            TriageScreen(
                client: client,
                queue: queue,
                dismissals: dismissals,
                connection: connection,
                macName: macName
            )
        case .queue:
            QueueScreen(queue: queue, connection: connection, macName: macName)
        case .library:
            LibraryScreen(client: client, macName: macName)
        case .settings:
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
        client: any ControlAPIClient = FixtureControlAPIClient(),
        queue: any CapabilityQueueWriter & CapabilityQueueReader = InMemoryCapabilityQueue(),
        dismissals: any DismissalStore = InMemoryDismissalStore(),
        connection: ConnectionState = .reachable,
        macName: String? = nil,
        initialTab: Tab = .settings,
        openSystemSettings: @escaping () -> Void = {}
    ) {
        self.init(
            pairing: pairing,
            store: store,
            camera: camera,
            client: client,
            queue: queue,
            dismissals: dismissals,
            connection: connection,
            macName: macName,
            initialTab: initialTab,
            openSystemSettings: openSystemSettings,
            cameraPreview: { _ in EmptyView() }
        )
    }
}
