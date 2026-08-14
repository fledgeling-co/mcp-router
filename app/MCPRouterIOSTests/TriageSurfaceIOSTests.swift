import SwiftUI
import UIKit
import XCTest
@testable import MCPRouterKit
@testable import MCPRouterUI

/// The claims about Triage, Queue and Library that only a device can make.
///
/// The package's own suites run on the **macOS host**, where a 44pt touch target, a wrapped line
/// and a safe-area inset are all unmeasurable. This target measures them. It reuses
/// `PhoneSurfaceTests`' hosting helpers rather than restating them.
///
/// **It asserts nothing about appearance.** The harness leaves the interface style `.unspecified`,
/// and an earlier iOS assertion in this fleet pinned dark unconditionally and failed reporting
/// `#ECECEE` — the *light* ground rendering perfectly correctly. Appearance is asserted against the
/// appearance actually set, or not at all.
@MainActor
final class TriageSurfaceIOSTests: XCTestCase {
    private let harness = PhoneSurfaceTests()

    // MARK: - Specimens

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
            source: .official,
            repository: nil,
            version: nil,
            updatedAt: nil,
            useCount: nil,
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

    /// A stdio entry, which is the row that carries the most clauses and therefore the longest
    /// capability line — the one that would truncate if anything did.
    private static let stdio = entry(
        id: "official:stdio",
        displayName: "obsidian-github-mcp",
        install: RegistryInstall(
            type: .stdio,
            command: "npx",
            args: ["-y", "obsidian-github-mcp"],
            url: nil,
            requires: [RegistryRequirement(name: "TOKEN", description: nil, isSecret: true)]
        )
    )

    /// A name wider than the column. The Overflow row of the state matrix.
    private static let longName = entry(
        id: "official:long",
        displayName: "an-extremely-long-server-name-that-cannot-possibly-fit-on-one-line-of-a-phone",
        install: RegistryInstall(
            type: .http,
            command: nil,
            args: nil,
            url: "https://mcp.example.com/thing",
            requires: nil
        )
    )

    private func row(
        _ entry: RegistryEntry,
        selected: Bool = false,
        expanded: Bool = false,
        width: CGFloat = PhoneSurfaceTests.phoneSize.width
    ) -> some View {
        TriageRow(
            entry: entry,
            bucket: .undecided,
            isSelected: selected,
            isExpanded: expanded,
            onToggleSelection: {},
            onToggleExpansion: {},
            onRestore: {}
        )
        .frame(width: width)
    }

    /// A view's own intrinsic height at a given width.
    ///
    /// Measured with `sizeThatFits` rather than by taking the tallest laid-out subview, for the
    /// reason `DiscoverSurfaceIOSTests` records: the subview version reported `PhoneMetric.tile` —
    /// the fixed icon plate — at every size, which measures the wrong thing and would report a real
    /// regression as a pass.
    private func height(_ view: some View, width: CGFloat) -> CGFloat {
        let controller = UIHostingController(rootView: AnyView(view))
        let window = UIWindow(frame: CGRect(origin: .zero, size: CGSize(width: width, height: 852)))
        window.overrideUserInterfaceStyle = .unspecified
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()

        let fitted = controller.sizeThatFits(
            in: CGSize(width: width, height: .greatestFiniteMagnitude)
        )
        XCTAssertGreaterThan(fitted.height, 0, "the view rendered nothing, so its height means nothing")
        return fitted.height
    }

    // MARK: - A3 / A27: every target is at least 44pt

    /// The row is **two** targets, each doing exactly one thing: a row that both selects and expands
    /// from one tap makes the more consequential act an accident of where the thumb landed.
    ///
    /// Measured through the accessibility tree, not through `UIControl`. SwiftUI does not render a
    /// `Button` into a `UIControl` on iOS — it publishes the button trait and frame — so a walker
    /// looking for `UIControl` finds nothing at all and the assertion passes vacuously.
    func testRowTargetsMeetTheFloor() {
        let controller = harness.host(ScrollView { self.row(Self.stdio) })
        let frames = harness.tappableFrames(of: controller.view, in: controller.view)

        XCTAssertGreaterThanOrEqual(
            frames.count, 2,
            "the row does not present two separate targets — it presents \(frames.count)"
        )
        for frame in frames {
            XCTAssertGreaterThanOrEqual(
                frame.height.rounded(), 44,
                "a row control is \(frame.height)pt tall, under the 44pt floor"
            )
        }
    }

    // MARK: - A5: the capability line never truncates

    /// The second prototype bug, inverted. This is the one line on the row carrying the security
    /// fact, so truncating it hides exactly what the row exists to show. It **wraps**; the row
    /// grows.
    ///
    /// Measured as a height comparison rather than by reading a `lineLimit`: a row whose capability
    /// line is forced narrow must get **taller**, which is only true if the line wraps. A row that
    /// truncated would stay the same height at both widths.
    func testCapabilityLineWrapsRatherThanTruncating() {
        let wide = height(row(Self.stdio, width: 393), width: 393)
        let narrow = height(row(Self.stdio, width: 240), width: 240)

        XCTAssertGreaterThan(
            narrow, wide,
            "the row did not grow when narrowed (\(narrow) vs \(wide)) — the capability line is truncating"
        )
    }

    /// The whole clause text reaches the accessibility tree, which is where SwiftUI publishes it.
    /// A truncated line publishes a truncated string.
    func testCapabilityLineIsRenderedWhole() {
        let controller = harness.host(row(Self.stdio))
        let texts = harness.accessibilityTexts(of: controller.view).joined(separator: " ")
        let expected = TriagePresentation.summaryText(CapabilitySummary.resolve(for: Self.stdio))

        XCTAssertFalse(expected.isEmpty, "the specimen produced no capability line at all")
        for clause in expected.components(separatedBy: " · ") {
            XCTAssertTrue(
                texts.contains(clause),
                "the capability line lost a clause: \(clause) not in \(texts)"
            )
        }
    }

    // MARK: - A24: the list does not jump when data lands

    /// "The list does not jump when data lands" is an equality between two rendered heights, so it
    /// is asserted as one. Left as prose it is a claim no reviewer could check and no regression
    /// could fail.
    func testSkeletonMatchesTheRowItReplaces() {
        let skeleton = height(TriageSkeletonRow().frame(width: 393), width: 393)
        let real = height(row(Self.stdio), width: 393)

        // Not exact equality: the skeleton is three fixed bars and the row is real text, so the
        // claim is that the list does not visibly jump, which is a tolerance rather than a value.
        XCTAssertEqual(
            skeleton, real, accuracy: 12,
            "the skeleton is \(skeleton)pt and the row it replaces is \(real)pt — the list jumps"
        )
    }

    // MARK: - A30: each tab is real, asserted per tab by its own copy

    /// **Positive and per tab.** The mechanism an earlier draft described could not distinguish
    /// three shipped surfaces from three tabs rendering Settings, because routing all three to a
    /// final `else` left every "no awaiting copy is compiled" check green. So each tab is hosted and
    /// its **own** pinned copy is looked for in the rendered tree.
    ///
    /// Polled rather than slept on: every surface loads in a `.task`, and a fixed delay is a bet on
    /// scheduler latency that loses under a parallel fleet. The failure message carries what was
    /// actually rendered, because "the copy was not found" and "the surface rendered nothing at all"
    /// are different faults and a bare assertion cannot tell them apart.
    func testEachTabRendersItsOwnSurface() {
        // Each needle is that surface's **own** copy constant, taken from the manifest rather than
        // written out here, and each is absent from Settings — which is the distinction A30 exists
        // to make. Chrome that only renders in the populated state is deliberately not used: the
        // fixture's Queue is empty, and a needle that depends on which state the surface reached
        // would fail for a reason that has nothing to do with the dispatch.
        let expectations: [(PhoneShell<EmptyView>.Tab, String)] = [
            (.triage, TriageCopy.entry(.control(.selectAll)).body),
            (.queue, QueueCopy.entry(.state(.empty)).headline ?? ""),
            (.library, LibraryCopy.entry(.chrome(.filterPlaceholder)).body)
        ]

        for (tab, copy) in expectations {
            let shell = PhoneShell(
                client: FixtureControlAPIClient(.populated),
                queue: InMemoryCapabilityQueue(),
                dismissals: InMemoryDismissalStore(),
                initialTab: tab
            )
            let controller = harness.host(shell)
            let needle = String(copy.prefix(20))

            var texts = ""
            var found = false
            // ~4s of real run-loop turns, which is what lets a `.task` actually resolve.
            for _ in 0 ..< 40 {
                RunLoop.current.run(until: Date().addingTimeInterval(0.1))
                controller.view.setNeedsLayout()
                controller.view.layoutIfNeeded()
                texts = harness.accessibilityTexts(of: controller.view).joined(separator: " | ")
                if texts.contains(needle) {
                    found = true
                    break
                }
            }

            XCTAssertTrue(
                found,
                "\(tab) did not render its own copy. Looked for: \(needle)\nRendered: \(texts)"
            )
        }
    }
}
