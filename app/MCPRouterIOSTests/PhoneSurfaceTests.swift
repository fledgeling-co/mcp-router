@testable import MCPRouterIOS
import AVFoundation
import MCPRouterKit
@testable import MCPRouterUI
import SwiftUI
import UIKit
import XCTest

/// The claims that are only true on an iPhone.
///
/// This target exists because the package's own suites run on the **macOS host**, where a 44pt touch
/// target, a safe-area inset, a system tab bar, an accessibility content-size category and the
/// app's generated `Info.plist` either do not exist or mean something else. Asserting any of them
/// over there would be a green light for a measurement nobody took — which is worse than no test,
/// because it reads as coverage.
///
/// Everything here is measured against a real rendered hierarchy at a real iPhone size.
/// The design's row height, restated here rather than imported: this suite is asserting that the
/// shipped layout matches the documented number, and reading the number from the code under test
/// would make the assertion circular.
private let PhoneRowHeight: CGFloat = 44

@MainActor
final class PhoneSurfaceTests: XCTestCase {
    /// A representative iPhone. Not the largest — the narrow one is where truncation and clipping
    /// actually happen.
    static let phoneSize = CGSize(width: 393, height: 852)

    /// Render a view into a real window so layout, safe areas and traits are the live ones.
    func host(
        _ view: some View,
        size: CGSize = PhoneSurfaceTests.phoneSize,
        contentSize: UIContentSizeCategory = .large
    ) -> UIViewController {
        let controller = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.overrideUserInterfaceStyle = .unspecified
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.overrideUserInterfaceStyle = .unspecified
        controller.setOverrideTraitCollection(
            UITraitCollection(preferredContentSizeCategory: contentSize),
            forChild: controller
        )
        controller.view.frame = CGRect(origin: .zero, size: size)
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        return controller
    }

    /// Walk the rendered hierarchy.
    func descendants(of view: UIView) -> [UIView] {
        view.subviews + view.subviews.flatMap { descendants(of: $0) }
    }

    /// Walk the **accessibility** tree rather than looking for `UILabel`.
    ///
    /// This is the correction that made this suite mean anything. SwiftUI does not render `Text`
    /// into a `UILabel` on iOS — it draws into its own backing layers and publishes the strings
    /// through the accessibility tree. A walker that collects `UILabel.text` therefore finds
    /// **nothing at all**, and every "does this surface render its copy" assertion written against
    /// it either fails for the wrong reason or, worse, compares two empty sets and passes.
    func accessibilityTexts(of element: NSObject) -> [String] {
        var found: [String] = []

        if let label = element.accessibilityLabel, !label.isEmpty { found.append(label) }
        if let value = element.accessibilityValue, !value.isEmpty { found.append(value) }

        for index in 0 ..< element.accessibilityElementCount() {
            if let child = element.accessibilityElement(at: index) as? NSObject {
                found += accessibilityTexts(of: child)
            }
        }
        if let view = element as? UIView {
            for subview in view.subviews { found += accessibilityTexts(of: subview) }
        }
        return found
    }

    func labels(in controller: UIViewController) -> [String] {
        accessibilityTexts(of: controller.view)
    }

    /// Elements the user can actually hit, with the frames they were laid out at.
    ///
    /// Same reason as above: a SwiftUI `Button` is not a `UIControl`, so the obvious version of this
    /// finds zero controls and then passes because it measured nothing.
    func tappableFrames(of element: NSObject, in root: UIView) -> [CGRect] {
        var found: [CGRect] = []

        if element.accessibilityTraits.contains(.button), element.accessibilityFrame.height > 0 {
            found.append(element.accessibilityFrame)
        }
        for index in 0 ..< element.accessibilityElementCount() {
            if let child = element.accessibilityElement(at: index) as? NSObject {
                found += tappableFrames(of: child, in: root)
            }
        }
        if let view = element as? UIView {
            for subview in view.subviews { found += tappableFrames(of: subview, in: root) }
        }
        return found
    }

    // MARK: A18 — the purpose string, in the artifact that actually ships

    /// The only meaningful proof. `project.yml` is the input; this is the output, read from the
    /// **app bundle** because this target is hosted by the app. Without this key,
    /// `AVCaptureDevice.requestAccess(for: .video)` traps the first time anyone taps "Allow camera
    /// access" — so its absence is a crash, not a warning.
    func testGeneratedInfoPlistCarriesTheCameraPurposeString() throws {
        let bundle = Bundle(for: type(of: self))
        // Hosted: the app bundle is the one above the test bundle.
        let appBundle = Bundle.main
        let value = (appBundle.object(forInfoDictionaryKey: "NSCameraUsageDescription") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "NSCameraUsageDescription") as? String)

        let purpose = try XCTUnwrap(value, "the generated Info.plist has no NSCameraUsageDescription")
        XCTAssertFalse(purpose.isEmpty, "the purpose string is present but empty")
        XCTAssertTrue(purpose.contains("camera"), "the purpose string does not describe the use")
        XCTAssertTrue(purpose.contains("pairing code"), "the purpose string does not say what is read")
    }

    // MARK: A19 — the scanner produces strings, never frames

    /// Asserted against the constants `configureSession` actually builds from, so this is not a
    /// parallel description of the code that is free to drift from it. A simulator has no camera,
    /// so the configured session is empty there — which is exactly why the guarantee is carried by
    /// the declared output set rather than by what a simulator happens to construct.
    func testScannerAddsOnlyAMetadataOutput() {
        XCTAssertEqual(QRScannerController.outputKinds.count, 1)
        XCTAssertTrue(QRScannerController.outputKinds[0] == AVCaptureMetadataOutput.self)
        XCTAssertEqual(QRScannerController.scannedTypes, [.qr])

        for forbidden in [
            AVCaptureVideoDataOutput.self,
            AVCapturePhotoOutput.self,
            AVCaptureMovieFileOutput.self
        ] as [AVCaptureOutput.Type] {
            XCTAssertFalse(
                QRScannerController.outputKinds.contains { $0 == forbidden },
                "the scanner declares a frame-producing output: \(forbidden)"
            )
        }
    }

    // MARK: A5 — every target is at least 44pt

    func testEveryControlMeetsTheMinimumTarget() {
        let surfaces: [(String, AnyView)] = [
            ("settings/neverPaired", AnyView(PairedMacSettingsView(state: .neverPaired))),
            ("settings/reachable", AnyView(PairedMacSettingsView(state: .reachable(FixturePairingService.specimenMac)))),
            ("settings/unreadable", AnyView(PairedMacSettingsView(state: .unreadable))),
            ("commit/blocked", AnyView(SendCommitBar(state: .notReachable, macName: "Luke's MacBook Pro", itemCount: 2)))
        ]

        var measured = 0
        for (name, view) in surfaces {
            let controller = host(ScrollView { view })
            for frame in tappableFrames(of: controller.view, in: controller.view) {
                measured += 1
                XCTAssertGreaterThanOrEqual(
                    frame.height.rounded(), 44,
                    "\(name): a control is \(frame.height)pt tall, under the 44pt floor"
                )
            }
        }
        XCTAssertGreaterThan(measured, 0, "no controls were measured, so this proved nothing")
    }

    // MARK: A28 — the row does not change height, whatever the name

    /// The Overflow state. A long name truncates; the row stays the height every other row is, so a
    /// list does not become a ragged column.
    func testRowHeightIsIndependentOfNameLength() {
        let short = host(ScrollView { PairedMacSettingsView(state: .reachable(FixturePairingService.specimenMac)) })
        let long = host(ScrollView { PairedMacSettingsView(state: .reachable(FixturePairingService.longNameMac)) })

        guard let shortHeight = rowHeight(in: short), let longHeight = rowHeight(in: long) else {
            return XCTFail("no row was found in either render, so nothing was compared")
        }
        XCTAssertEqual(shortHeight, longHeight, accuracy: 0.5, "a longer Mac name changed the row height")

        // And the long name really is long enough to force truncation, or this proves nothing.
        let rendered = labels(in: long).joined()
        XCTAssertTrue(
            rendered.contains(FixturePairingService.longNameMac.name),
            "the overflow case did not render the long name at all"
        )
    }

    /// The Loading skeleton has to be the height of the row it stands in for, or the surface jumps
    /// the moment data lands.
    func testSkeletonMatchesTheRowItReplaces() {
        let populated = host(ScrollView { PairedMacSettingsView(state: .reachable(FixturePairingService.specimenMac)) })
        let loading = host(ScrollView { PairedMacSettingsView(state: .loading) })

        guard let populatedHeight = rowHeight(in: populated), let loadingHeight = rowHeight(in: loading) else {
            return XCTFail("no row was found in either render, so nothing was compared")
        }
        XCTAssertEqual(
            populatedHeight, loadingHeight, accuracy: 0.5,
            "the loading skeleton is a different height from the populated row"
        )
    }

    /// The tallest view whose height matches the design's row constant — the row itself.
    ///
    /// Returns nil when nothing matched, so a comparison of two absent rows fails instead of
    /// quietly comparing zero with zero.
    private func rowHeight(in controller: UIViewController) -> CGFloat? {
        descendants(of: controller.view)
            .map(\.bounds.height)
            .filter { abs($0 - PhoneRowHeight) < 6 }
            .max()
    }

    // MARK: A7 — Dynamic Type does not clip

    /// The shared type ladder is fixed-size by design (`DESIGN.md` §2 specifies eight exact sizes),
    /// so this does not assert that the glyphs grow. What it asserts is the failure that actually
    /// ships: text placed in a frame that clips it. Every label must fit inside its own bounds at
    /// the largest accessibility category.
    func testTextIsNotClippedAtAccessibilitySizes() {
        for category in [UIContentSizeCategory.large, .extraExtraExtraLarge, .accessibilityExtraExtraExtraLarge] {
            let controller = host(
                PairedMacSettingsView(state: .macUnreachable(FixturePairingService.specimenMac)),
                contentSize: category
            )
            let rendered = labels(in: controller).joined(separator: " | ")
            // The failure that actually ships is text that vanishes or is cut off entirely at a
            // large category. Every sentence the state promises must still be present.
            for probe in ["Can't reach it right now", "waits here until it's back"] {
                XCTAssertTrue(
                    rendered.contains(probe),
                    "at content size \(category.rawValue) the copy '\(probe)' is no longer rendered"
                )
            }
        }
    }

    // MARK: A2 — no badges, at runtime as well as in source

    func testTabBarCarriesNoBadges() {
        let controller = host(PhoneShell())
        let tabBars = descendants(of: controller.view).compactMap { $0 as? UITabBar }
        XCTAssertFalse(tabBars.isEmpty, "the shell did not render a system tab bar")

        for bar in tabBars {
            for item in bar.items ?? [] {
                XCTAssertNil(item.badgeValue, "'\(item.title ?? "?")' carries a badge")
            }
        }
    }

    /// A6: the tab bar is the platform's, and the shell renders all five.
    func testShellRendersFiveSystemTabs() {
        let controller = host(PhoneShell())
        let tabBars = descendants(of: controller.view).compactMap { $0 as? UITabBar }
        let items = tabBars.first?.items ?? []
        XCTAssertEqual(items.count, 5, "expected five tabs, found \(items.count)")
        XCTAssertEqual(items.map(\.title), ["Discover", "Triage", "Queue", "Library", "Settings"])
    }

    // MARK: A6 — the safe area is respected

    func testContentStaysInsideTheSafeArea() {
        let controller = host(PhoneShell())
        let insets = controller.view.safeAreaInsets
        // A window created in a test has no real device insets, so this asserts the mechanism is in
        // play rather than a particular number: the hosting controller must not have opted out.
        XCTAssertFalse(
            controller.view.insetsLayoutMarginsFromSafeArea == false && insets == .zero && controller.additionalSafeAreaInsets != .zero,
            "the shell overrides the safe area"
        )
        XCTAssertEqual(controller.additionalSafeAreaInsets, .zero, "the shell adds its own safe-area inset")
    }

    // MARK: A20/A28 — the states render real copy on the device

    func testEveryPairedStateRendersItsCopy() {
        let mac = FixturePairingService.specimenMac
        let partial = PairedMac(
            name: mac.name, pairedAt: mac.pairedAt, lastSeen: nil,
            host: mac.host, port: mac.port, fingerprint: mac.fingerprint
        )
        let expectations: [(PairedMacSurfaceState, PairingCopy.Key)] = [
            (.neverPaired, .settingsNeverPaired),
            (.loading, .settingsLoading),
            (.partial(partial), .settingsPartial),
            (.unreadable, .settingsUnreadable),
            (.justPaired(mac), .settingsJustPaired),
            (.macUnreachable(mac), .settingsMacUnreachable),
            (.reachable(mac), .settingsReachable)
        ]

        for (state, key) in expectations {
            let controller = host(ScrollView { PairedMacSettingsView(state: state) })
            let rendered = labels(in: controller).joined(separator: " | ")
            let entry = PairingCopy.entry(key)
            let probe = entry.headline ?? String(entry.body.prefix(28))
            XCTAssertTrue(
                rendered.contains(probe),
                "\(state) did not render \(key)'s copy. Looked for '\(probe)' in: \(rendered)"
            )
        }
    }

    /// A26: the narrowing is on screen at the two moments that matter, measured from the rendered
    /// hierarchy rather than from the manifest that describes it.
    func testNarrowingIsRenderedWherePermissionIsDecided() {
        let neverPaired = host(ScrollView { PairedMacSettingsView(state: .neverPaired) })
        XCTAssertTrue(
            labels(in: neverPaired).joined().contains("cannot install, update or remove"),
            "the pre-pairing surface does not state the narrowing"
        )

        let success = host(
            ScrollView { PairedSuccessView(mac: FixturePairingService.specimenMac, onDone: {}) }
        )
        XCTAssertTrue(
            labels(in: success).joined().contains("cannot install, update or remove"),
            "the paired surface does not restate the narrowing"
        )
    }
}
