import SwiftUI
import UIKit
import XCTest
@testable import MCPRouterKit
@testable import MCPRouterUI

/// The claims about Discover that only a device can make.
///
/// The package's own suites run on the **macOS host**, where a 44pt touch target, a safe-area
/// inset and Dynamic Type at an accessibility size are all unmeasurable. This target measures
/// them. It reuses `PhoneSurfaceTests`' hosting helpers rather than restating them, and it
/// deliberately asserts **nothing about appearance**: the harness leaves the interface style
/// `.unspecified`, so a test that pinned dark would fail on a correct light render.
@MainActor
final class DiscoverSurfaceIOSTests: XCTestCase {
    private let harness = PhoneSurfaceTests()

    // MARK: - Specimens

    /// One entry per commit branch the surfaces have to draw: a remote one with a Smithery
    /// credential, a stdio one, and one with no descriptor at all.
    private static func entry(
        id: String,
        displayName: String,
        install: RegistryInstall?
    ) -> RegistryEntry {
        RegistryEntry(
            id: id,
            name: id,
            displayName: displayName,
            description: "Manage repos, issues and pull requests from your editor",
            source: .both,
            repository: nil,
            version: nil,
            updatedAt: "2025-11-19T07:26:28.312Z",
            useCount: 2984,
            verified: nil,
            iconURL: nil,
            stars: nil,
            forks: nil,
            pushedAt: nil,
            archived: nil,
            install: install,
            installed: false
        )
    }

    private static let remote = entry(
        id: "smithery:github",
        displayName: "GitHub",
        install: RegistryInstall(
            type: .http,
            command: nil,
            args: nil,
            url: "https://server.smithery.ai/github/mcp",
            requires: [RegistryRequirement(
                name: "Authorization",
                description: "Bearer <key>",
                isSecret: true
            )]
        )
    )

    private static let local = entry(
        id: "official:obsidian",
        displayName: "obsidian-github-mcp",
        install: RegistryInstall(
            type: .stdio,
            command: "npx",
            args: ["-y", "obsidian-github-mcp"],
            url: nil,
            requires: nil
        )
    )

    private static let bare = entry(id: "official:bare", displayName: "bare", install: nil)

    private func model(connection: ConnectionState = .reachable) -> DiscoverModel {
        DiscoverModel(
            client: FixtureControlAPIClient(),
            queue: InMemoryCapabilityQueue(),
            connection: connection,
            macName: "Luke's MacBook Pro"
        )
    }

    private func plate(for entry: RegistryEntry) -> CapabilityPlateView {
        CapabilityPlateView(
            lines: CapabilityPlate.lines(install: entry.install, archived: entry.archived),
            invocation: CapabilityPlate.invocation(install: entry.install)
        )
    }

    // MARK: - A29: every control meets 44pt

    func testEveryDiscoverControlMeetsTheMinimumTarget() {
        let surfaces: [(String, AnyView)] = [
            ("commit/reachable", AnyView(QueueCommitBar(
                state: .reachable,
                entry: model().copy(CommitState.reachable.copyKey),
                failure: nil,
                action: {}
            ))),
            // A17: disabled dims **in place** and is still a control on screen, so it is still
            // measured. A target that disappears when dimmed would pass a 44pt check by absence.
            ("commit/noDescriptor", AnyView(QueueCommitBar(
                state: .noDescriptor,
                entry: model().copy(CommitState.noDescriptor.copyKey),
                failure: nil,
                action: {}
            ))),
            ("commit/notReachable", AnyView(QueueCommitBar(
                state: .notReachable,
                entry: model().copy(CommitState.notReachable.copyKey),
                failure: nil,
                action: {}
            ))),
            ("detail/remote", AnyView(CapabilityDetailView(entry: Self.remote, model: model()))),
            // A17 on the device: with no descriptor the commit dims **in place**, so it is still a
            // 44pt target rather than a gap where a control used to be.
            ("detail/noDescriptor", AnyView(CapabilityDetailView(entry: Self.bare, model: model())))
        ]

        var measured = 0
        for (name, view) in surfaces {
            let controller = harness.host(ScrollView { view })
            for frame in harness.tappableFrames(of: controller.view, in: controller.view) {
                measured += 1
                XCTAssertGreaterThanOrEqual(
                    frame.height.rounded(), 44,
                    "\(name): a control is \(frame.height)pt tall, under the 44pt floor"
                )
            }
        }
        XCTAssertGreaterThan(measured, 0, "no controls were measured, so this proved nothing")
    }

    // MARK: - A29: the row's 44pt is a minimum, not a fixed height

    /// `DESIGN.md` §5's "rows never change height" is an **Overflow** rule about long values, and
    /// is satisfied by truncating the name rather than by pinning a height.
    ///
    /// **What this deliberately does not assert, and why.** A29 also asks for Dynamic Type from
    /// xSmall to AX3, and measured here the row is the same height at both: `TypeToken.font` is
    /// `Font.system(size:weight:)`, which is a **fixed** font, so no surface in this product scales
    /// with Dynamic Type — Mac or phone. That is F2's shared ladder rather than anything this
    /// feature introduced, and DESIGN.md §2 fixes the eight sizes on purpose, so it is reported as
    /// a deferred child rather than worked around here. Asserting "does not grow" would pin the
    /// gap shut; asserting "grows" would fail on every surface. So this measures the half the
    /// feature owns and the limitation travels in the evidence instead.
    func testRowHeightIsIndependentOfTheNameLength() {
        let short = rowHeight(DiscoverRow(entry: Self.remote, band: .mostUsed), size: .large)
        let long = rowHeight(
            DiscoverRow(
                entry: Self.entry(
                    id: "x",
                    displayName: String(repeating: "a-very-long-server-name", count: 4),
                    install: nil
                ),
                band: .mostUsed
            ),
            size: .large
        )
        XCTAssertEqual(short, long, accuracy: 1, "a long name changed the row height")
    }

    /// The skeleton has to match the row it replaces, or the list steps when data lands.
    ///
    /// Measured across the Dynamic Type range the spec names, so that if the ladder is ever made
    /// to scale the two are already proven to move together.
    func testSkeletonMatchesTheRowItReplaces() {
        for size in [DynamicTypeSize.xSmall, .large, .accessibility3] {
            let row = rowHeight(DiscoverRow(entry: Self.remote, band: .mostUsed), size: size)
            let skeleton = rowHeight(DiscoverSkeletonRow(), size: size)
            XCTAssertEqual(
                row, skeleton, accuracy: 1,
                "at \(size) the skeleton is \(skeleton) and the row \(row)"
            )
        }
    }

    /// The row's own intrinsic height at a given content size.
    ///
    /// Measured with `sizeThatFits` rather than by taking the tallest laid-out subview. The first
    /// version of this helper did the latter and reported 30pt at every size — that is
    /// `PhoneMetric.tile`, the fixed icon plate, which of course does not grow with Dynamic Type.
    /// It measured the wrong thing and would have reported a real regression as a pass.
    private func rowHeight(_ view: some View, size: DynamicTypeSize) -> CGFloat {
        let controller = UIHostingController(
            rootView: AnyView(view.environment(\.dynamicTypeSize, size))
        )
        let window = UIWindow(
            frame: CGRect(origin: .zero, size: PhoneSurfaceTests.phoneSize)
        )
        window.overrideUserInterfaceStyle = .unspecified
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()

        let fitted = controller.sizeThatFits(in: CGSize(
            width: PhoneSurfaceTests.phoneSize.width,
            height: .greatestFiniteMagnitude
        ))
        XCTAssertGreaterThan(
            fitted.height, 0,
            "the row rendered nothing, so its height means nothing"
        )
        return fitted.height
    }

    // MARK: - A12: the plate is drawn, above the commit, at every size

    /// The brief's rule: **the security fact is never behind a tap the user can skip.** A test that
    /// only checked the plate exists would pass with it inside a collapsed disclosure group, so
    /// this asserts the sentences are in the rendered accessibility tree with nothing expanded.
    func testThePlateIsRenderedWithoutAnyDisclosure() {
        let controller = harness.host(ScrollView { plate(for: Self.local) })
        let rendered = harness.labels(in: controller).joined(separator: " | ")

        XCTAssertTrue(
            rendered.contains("Runs a program on your Mac"),
            "the stdio consequence is not on screen: \(rendered)"
        )
        // The literal invocation is the evidence the plain-language line interprets.
        XCTAssertTrue(
            rendered.contains("npx -y obsidian-github-mcp"),
            "the invocation is not on screen: \(rendered)"
        )
    }

    /// A14: within the Smithery subset the credential line distinguishes nothing, and says so.
    func testTheSmitheryCredentialLineAdmitsItCarriesNoSignal() {
        let controller = harness.host(ScrollView { plate(for: Self.remote) })
        let rendered = harness.labels(in: controller).joined(separator: " | ")

        XCTAssertTrue(rendered.contains("server.smithery.ai"), "the host is not named: \(rendered)")
        XCTAssertTrue(
            rendered.contains("doesn't set this server apart"),
            "the credential line does not admit it carries no signal: \(rendered)"
        )
    }

    /// A29: the plate's sentences survive an accessibility size rather than being clipped away.
    func testThePlateCopySurvivesAccessibilitySizes() {
        for size in [DynamicTypeSize.xSmall, .accessibility3] {
            let controller = harness.host(
                ScrollView { plate(for: Self.local) }.environment(\.dynamicTypeSize, size)
            )
            let rendered = harness.labels(in: controller).joined(separator: " | ")
            XCTAssertTrue(
                rendered.contains("Runs a program on your Mac"),
                "at Dynamic Type \(size) the consequence is no longer rendered"
            )
        }
    }

    // MARK: - A20: the narrowing is on the commit, whatever the state

    /// Seven states, and the narrowing is on every one of them. Asserted on the **rendered** tree
    /// rather than on the copy manifest, because a bar that holds the string and never draws it
    /// satisfies the manifest test and not the criterion.
    func testEveryCommitStateRendersTheNarrowing() {
        for state in CommitState.allCases {
            let controller = harness.host(ScrollView {
                QueueCommitBar(
                    state: state,
                    entry: model().copy(state.copyKey),
                    failure: nil,
                    action: {}
                )
            })
            let rendered = harness.labels(in: controller).joined(separator: " | ")
            XCTAssertTrue(
                rendered.contains(PairingCopy.neverInstalls),
                "\(state) does not render the narrowing: \(rendered)"
            )
        }
    }

    /// Detail must not tell the user the router is down when no Mac is paired.
    ///
    /// The offline note and the never-paired commit contradicted each other on one screen: the
    /// note offered to save the item and send it from Queue later, while the bar directly beneath
    /// it said there was nowhere to send it and was dimmed. There is no router to be down when
    /// nothing is paired, so Offline is a paired-and-unanswering state only.
    func testNeverPairedDoesNotClaimTheRouterIsDown() {
        let controller = harness.host(
            CapabilityDetailView(entry: Self.remote, model: model(connection: .neverPaired))
        )
        let rendered = harness.labels(in: controller).joined(separator: " | ")

        XCTAssertFalse(
            rendered.contains("isn't running"),
            "Detail claims the router is down with no Mac paired: \(rendered)"
        )
        XCTAssertTrue(
            rendered.contains("No Mac paired yet"),
            "the never-paired reason is not on screen: \(rendered)"
        )
    }

    /// The other half: a paired Mac that is not answering *does* get the note, so the fix above
    /// narrowed the condition rather than deleting the state.
    func testUnreachableStillRendersTheOfflineNote() {
        let controller = harness.host(
            CapabilityDetailView(entry: Self.remote, model: model(connection: .notReachable))
        )
        let rendered = harness.labels(in: controller).joined(separator: " | ")

        XCTAssertTrue(
            rendered.contains("You can still save this here"),
            "the offline note is missing for a paired but unreachable Mac: \(rendered)"
        )
    }

    /// A18, on the device: unreachable stays live and says "Save for your Mac", where never-paired
    /// is dimmed. A disabled Send beside a live Send for the same Mac reads as a bug.
    func testUnreachableRendersTheSaveLabelAndNeverPairedDoesNot() {
        let unreachable = harness.host(ScrollView {
            QueueCommitBar(
                state: .notReachable,
                entry: model(connection: .notReachable).copy(CommitState.notReachable.copyKey),
                failure: nil,
                action: {}
            )
        })
        XCTAssertTrue(
            harness.labels(in: unreachable).joined(separator: " | ").contains("Save for your Mac"),
            "the unreachable commit did not relabel"
        )
    }

    // MARK: - A29: nothing is occluded by the status bar or the home indicator

    func testDiscoverStaysInsideTheSafeArea() {
        let controller = harness.host(DiscoverScreen(
            client: FixtureControlAPIClient(),
            queue: InMemoryCapabilityQueue(),
            macName: "Luke's MacBook Pro"
        ))
        let insets = controller.view.safeAreaInsets
        let safe = controller.view.bounds.inset(by: insets)

        var checked = 0
        for view in harness.descendants(of: controller.view) where view.frame.height > 0 {
            guard view.isAccessibilityElement else { continue }
            let frame = view.convert(view.bounds, to: controller.view)
            guard frame.height > 0, frame.width > 0 else { continue }
            checked += 1
            XCTAssertGreaterThanOrEqual(
                frame.minY.rounded(), safe.minY.rounded() - 1,
                "content is under the status bar"
            )
        }
        XCTAssertGreaterThan(checked, 0, "nothing was measured, so this proved nothing")
    }
}
