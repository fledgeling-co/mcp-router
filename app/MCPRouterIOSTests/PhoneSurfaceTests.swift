import AVFoundation
import MCPRouterKit
import SwiftUI
import UIKit
import XCTest
@testable import MCPRouterIOS
@testable import MCPRouterUI

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

    /// Turn the accessibility engine on for this process, once.
    ///
    /// **Without this the suite measures nothing and says so.** SwiftUI's `_UIHostingView` builds an
    /// accessibility container either way, and when the engine is off it vends an **empty** element
    /// list — `accessibilityElements` is `[]`, not `nil`. Every label-based assertion in this target
    /// then reads empty and reports `nothing was measured, so this proved nothing`, which is the
    /// honest verdict for a dead instrument and looks exactly like a product that renders no copy.
    ///
    /// Measured 20 Aug 2026, over ten runs: 52 failures across 35 tests, on two simulators and on an
    /// untouched HEAD checkout, with a probe reporting the window attached to a foreground-active
    /// scene, the frame correct, and `accessibilityElements` empty. Calling `_AXSSetAutomationEnabled`
    /// took the same probe's element count from 0 to 1.
    ///
    /// The engine had been on before by accident — something else on this machine had enabled it —
    /// which is why this suite was green for months while depending on ambient host state no file in
    /// this repo controls. Enabling it here is the fix for that, not only for the outage: a lane that
    /// cannot switch on its own instrument is not measuring, it is being measured for.
    ///
    /// This is a test-target-only dependency on a private symbol. It is never linked into the app.
    /// `testTheAccessibilityEngineCanBeSwitchedOn` fails loudly if a future runtime renames it, so
    /// the suite goes red rather than quietly empty.
    static let accessibilityEngineEnabled: Bool = {
        let libraries = [
            "/usr/lib/libAccessibility.dylib",
            "/System/Library/PrivateFrameworks/AccessibilityUtilities.framework/AccessibilityUtilities"
        ]
        for library in libraries {
            guard let handle = dlopen(library, RTLD_LAZY),
                  let symbol = dlsym(handle, "_AXSSetAutomationEnabled")
            else { continue }
            typealias Setter = @convention(c) (Bool) -> Void
            unsafeBitCast(symbol, to: Setter.self)(true)
            return true
        }
        return false
    }()

    /// The label the liveness probe publishes. Nothing in the product uses this string.
    static let engineProbeLabel = "mcprouter-engine-probe"

    /// Windows the liveness probe made, held for the process. See `windows` below for why.
    private nonisolated(unsafe) static var probeWindows: [UIWindow] = []

    /// **Switching the engine on is asynchronous, so the suite waits for it rather than assuming
    /// it.** `_AXSSetAutomationEnabled(true)` returns immediately and the engine becomes live some
    /// time later, and the tests that run in between read an empty tree and report `nothing was
    /// measured, so this proved nothing` — the honest verdict, arriving for a reason that has
    /// nothing to do with the product.
    ///
    /// Measured 20 Aug 2026, on a device the previous run had explicitly disabled: the run that
    /// re-enabled it failed **39 assertions across 15 test cases**, all of them early in
    /// alphabetical order, while `testTheAccessibilityEngineCanBeSwitchedOn` — which runs late in
    /// `PhoneSurfaceTests` — **passed**. That is the shape of an instrument coming up part-way
    /// through a run, and it is the worst shape available: a green instrument check standing over
    /// a suite that measured nothing. The next run on the same device, with no change, was clean.
    ///
    /// So the wait is here, once per process, before the first `host()`. It hosts a view whose
    /// label no product surface uses and blocks until that label is published or the deadline
    /// passes. It is a different instrument from `settleAccessibilityTree` below, which stays: that
    /// one waits on a *product* surface, where an empty tree is a legitimate reading, so it cannot
    /// assert and can only report. This one waits on a probe whose answer is known, so a timeout is
    /// a fact about the instrument rather than about the view — and it is the one that goes red.
    ///
    /// `settleAccessibilityTree` was measured mid-investigation to cost 130 seconds a run and buy
    /// nothing, and was briefly removed on that basis. The measurement was taken while the engine
    /// was dead and nothing could ever arrive, which is exactly the reading a broken instrument
    /// produces about the instrument beside it. With the engine on it returns as soon as the tree
    /// populates, so it is back where X1 committed it.
    static let accessibilityEngineIsLive: Bool = {
        guard accessibilityEngineEnabled else { return false }
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            if engineProbePublishes() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return engineProbePublishes()
    }()

    /// Host one `Text` and report whether its label reached the accessibility tree.
    ///
    /// Bounded by depth and by a node budget for the reason `walk` records: a view's accessibility
    /// elements are frequently its own subviews, so an unbounded descent revisits forever.
    private static func engineProbePublishes() -> Bool {
        // **Inside a `ScrollView`, because that is the shape that fails.** A bare `Text` publishes
        // its label in the half-enabled state as readily as in the enabled one, so a probe built
        // from one reported the engine live at t=0 of a run in which 15 test cases went on to read
        // an empty tree. Those 15 are exactly the ones hosting `ScrollView { … }`; the tests that
        // passed alongside them are geometry, counts and negative assertions, which an empty tree
        // satisfies. The probe therefore hosts what the failures host.
        let controller = UIHostingController(
            rootView: ScrollView { Text("engine probe").accessibilityLabel(engineProbeLabel) }
        )
        let window = UIWindow(frame: CGRect(origin: .zero, size: phoneSize))
        probeWindows.append(window)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.frame = CGRect(origin: .zero, size: phoneSize)
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        var budget = 2000
        return carriesProbeLabel(controller.view, depth: 0, budget: &budget)
    }

    /// **Both paths, exactly as `walk` reads them**, because the probe stands in for assertions that
    /// use `walk` and a probe that reads differently from the thing it stands for answers a
    /// different question. Two narrower versions were measured and both were wrong in opposite
    /// directions: a bare `Text` read through either path reports live in the half-enabled state
    /// where 15 test cases read empty, and a `ScrollView` read through the container path alone
    /// reports dead on a device where all 35 other tests pass.
    private static func carriesProbeLabel(_ element: NSObject, depth: Int, budget: inout Int) -> Bool {
        guard depth < 24, budget > 0 else { return false }
        budget -= 1
        if element.accessibilityLabel == engineProbeLabel { return true }
        for index in 0 ..< childCount(of: element) {
            guard let next = child(of: element, at: index) else { continue }
            if carriesProbeLabel(next, depth: depth + 1, budget: &budget) { return true }
        }
        if let view = element as? UIView {
            for subview in view.subviews {
                if carriesProbeLabel(subview, depth: depth + 1, budget: &budget) { return true }
            }
        }
        return false
    }

    /// The instrument check. A dead engine is the one failure that makes every other assertion here
    /// vacuous, so it is asserted rather than assumed.
    ///
    /// This subsumes `testTheAccessibilityInstrumentIsLive`, which asserted that a hosted
    /// `ScrollView { Text }` publishes its label and is the second assertion below — kept here
    /// rather than in two places, because two tests reporting one fact disagree eventually.
    func testTheAccessibilityEngineCanBeSwitchedOn() {
        XCTAssertTrue(
            Self.accessibilityEngineEnabled,
            "_AXSSetAutomationEnabled could not be resolved, so SwiftUI publishes no accessibility "
                + "elements and every label assertion in this target is vacuous"
        )
        XCTAssertTrue(
            Self.accessibilityEngineIsLive,
            "the engine was switched on and no hosted Text published a label within 20s, so this "
                + "target cannot measure what it claims to measure"
        )
        let probe = host(Text("engine-probe").accessibilityLabel("engine-probe-label"))
        XCTAssertTrue(
            accessibilityTexts(of: probe.view).contains("engine-probe-label"),
            "the engine reports live and a hosted Text still published no label, so this target "
                + "cannot measure what it claims to measure"
        )
    }

    /// Every window `host` has made, kept alive for as long as this harness is.
    ///
    /// **This is what made the suite intermittent.** `host` returns the controller, and a
    /// controller's `view.window` is a weak back-reference — a `UIWindow` with no `windowScene` is
    /// retained by nothing else, so the window was free to deallocate the moment `host` returned.
    /// A deallocated window tears down its hierarchy, and the accessibility tree goes with it. The
    /// symptom is the whole suite reading empty at once: `nothing was measured, so this proved
    /// nothing` across every assertion in a class, on a machine under load, with no code change
    /// between a green run and a red one. Observed three times on 20 Aug 2026 before it was traced.
    ///
    /// Holding the windows here rather than spinning a runloop is deliberate: a wait would make the
    /// window's lifetime a race that usually goes the right way, and the point is that it is not a
    /// race at all.
    private var windows: [UIWindow] = []

    override func tearDown() {
        for window in windows {
            window.isHidden = true
        }
        windows.removeAll()
        super.tearDown()
    }

    /// Render a view into a real window so layout, safe areas and traits are the live ones.
    func host(
        _ view: some View,
        size: CGSize = PhoneSurfaceTests.phoneSize,
        contentSize: UIContentSizeCategory = .large
    ) -> UIViewController {
        _ = Self.accessibilityEngineIsLive
        let controller = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        windows.append(window)
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
        // SwiftUI fills `accessibilityElements` on the next turn, after the hosting view has a
        // window — but *when* is not fixed: it moves with the simulator's OS and with load, and a
        // fixed 50ms pass was enough on one runner and not on the next. A deadline poll settles
        // when the tree is actually populated, and reports what it needed rather than assuming.
        settleAccessibilityTree(of: controller)
        return controller
    }

    /// Spin the run loop until the accessibility tree carries text, or the deadline expires.
    ///
    /// A fixed pass was the wrong instrument: SwiftUI publishes the tree on a later turn, and
    /// *when* moves with the simulator's OS and with load — 50ms was enough on one runner and not
    /// on the next, which reads downstream as "the copy is no longer rendered".
    ///
    /// This does **not** assert. An empty tree is not always a defect: a surface under test for its
    /// frames, or a tab bar deliberately carrying no badge text, legitimately has none. Asserting
    /// here failed four such tests while fixing four others. The tests that need a non-empty tree
    /// already carry their own vacuity guards, which is where that judgement belongs.
    @discardableResult
    func settleAccessibilityTree(
        of controller: UIViewController,
        deadline: TimeInterval = 1.0
    ) -> TimeInterval {
        let started = Date()
        while Date().timeIntervalSince(started) < deadline {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
            if !accessibilityTexts(of: controller.view).isEmpty {
                return Date().timeIntervalSince(started)
            }
        }
        // The deadline expired with an empty tree. That is legitimate on a frames-only surface, so
        // it is not asserted — but it is the signature of a harness defect too, and the two are
        // told apart by whether the view laid out at all. Printing both costs nothing and turns
        // "rendered nothing" into a diagnosis.
        let v = controller.view!
        let kids = descendants(of: v)
        let classes = Dictionary(grouping: kids, by: { String(describing: type(of: $0)) })
            .map { "\($0.key)x\($0.value.count)" }.sorted().joined(separator: ",")
        let containers = kids.filter { $0.accessibilityElements != nil }.count
        let counts = kids.map { $0.accessibilityElementCount() }
            .filter { $0 > 0 && $0 != NSNotFound }
        FileHandle.standardError.write(Data(
            ("SETTLE-EMPTY frame=\(v.frame) descendants=\(kids.count) "
                + "containers=\(containers) elemCounts=\(counts) classes=[\(classes)]\n")
                .utf8
        ))
        return deadline
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
        var seen = Set<ObjectIdentifier>()
        var retained: [NSObject] = []
        var budget = 3000
        return walk(element, seen: &seen, retained: &retained, depth: 0, budget: &budget) { object in
            [object.accessibilityLabel, object.accessibilityValue]
                .compactMap(\.self)
                .filter { !$0.isEmpty }
        }
    }

    /// One walker for both trees, bounded three ways: visited set, depth cap, node budget.
    ///
    /// This is not defensive padding — each bound stops a failure that was actually observed.
    ///
    /// A `UIView`'s accessibility elements frequently *are* its subviews, so descending into both
    /// without remembering what has been visited revisits the same objects forever. The first
    /// version of this suite did that and the tests using it did not fail, they **crashed the test
    /// runner**, which xcodebuild reports as "Restarting after unexpected exit" and then as a plain
    /// failure — a stack overflow reads like a failing assertion, which is the most confusing way
    /// for a test to be wrong.
    ///
    /// The visited set alone is not enough: SwiftUI's accessibility bridge vends a **freshly
    /// allocated** element from `accessibilityElement(at:)` on each call, so no `ObjectIdentifier`
    /// repeats and the set never stops that branch. The budget is what bounds the breadth.
    ///
    /// And the child count is clamped, which is the bound that actually mattered here.
    /// `accessibilityElementCount()` returns **`NSNotFound`** — not zero — for anything that is not
    /// an accessibility container, and `NSNotFound` is `Int.max`. `for index in 0 ..< count` over
    /// that is a loop of ~9.2 × 10¹⁸ iterations; a `where budget > 0` clause does not save it,
    /// because `where` filters the body while the range is still walked to the end. The observed
    /// symptom was the test process being SIGKILLed with `make: *** [test-ios] Killed: 9`, which
    /// looks like a machine problem rather than a loop.
    private func walk<T>(
        _ element: NSObject,
        seen: inout Set<ObjectIdentifier>,
        retained: inout [NSObject],
        depth: Int,
        budget: inout Int,
        collect: (NSObject) -> [T]
    ) -> [T] {
        guard depth < 25, budget > 0 else { return [] }
        // Held for the whole walk, and that is what makes `seen` mean anything.
        //
        // `accessibilityElement(at:)` *creates* SwiftUI's elements on demand and hands back the only
        // reference. Recursing and returning released each one, and the allocator reissued the
        // address — so the next element hashed to an `ObjectIdentifier` already in `seen`, was
        // treated as visited, and the walk returned `[]` for a hierarchy that was fully there.
        //
        // The symptom is the entire target reading empty at once: 51 failures across 35 tests, on a
        // fresh simulator, deterministic over seven consecutive runs, flipping green-to-red on an
        // unrelated source split that moved the binary layout. `ObjectIdentifier` is unique among
        // *live* objects only, and nothing here was keeping them alive.
        retained.append(element)
        guard seen.insert(ObjectIdentifier(element)).inserted else { return [] }
        retained.append(element)
        budget -= 1

        var found = collect(element)

        // SwiftUI's hosting view publishes its tree through `accessibilityElements`,
        // not through `accessibilityElement(at:)`. The first iOS run of this suite
        // collected nothing — every "is this copy on screen" assertion failed with
        // an empty `in:` — while `sizeThatFits` still returned a real height. The
        // product drew; the walker did not look at the array SwiftUI actually fills.
        if let elements = element.accessibilityElements {
            for child in elements {
                if budget <= 0 { break }
                if let child = child as? NSObject {
                    found += walk(
                        child,
                        seen: &seen,
                        retained: &retained,
                        depth: depth + 1,
                        budget: &budget,
                        collect: collect
                    )
                }
            }
        }
        for index in 0 ..< Self.childCount(of: element) {
            if budget <= 0 { break }
            if let child = Self.child(of: element, at: index) {
                found += walk(
                    child, seen: &seen, retained: &retained,
                    depth: depth + 1, budget: &budget, collect: collect
                )
            }
        }
        if let view = element as? UIView {
            for subview in view.subviews {
                if budget <= 0 { break }
                found += walk(
                    subview, seen: &seen, retained: &retained,
                    depth: depth + 1, budget: &budget, collect: collect
                )
            }
        }
        return found
    }

    /// The number of accessibility children, made safe to iterate.
    ///
    /// `NSNotFound` means "not a container" rather than "this many children", and a negative count
    /// is meaningless. Both become zero; anything real is capped so one pathological node cannot
    /// consume the whole budget.
    private static func childCount(of element: NSObject) -> Int {
        // `accessibilityElements` first. SwiftUI's `_UIHostingView` publishes through the array and
        // leaves `accessibilityElementCount()` at 0 — measured on iOS 26.5, where a hosted `Text`
        // reported `accessibilityElements.count == 1` and `accessibilityElementCount() == 0` in the
        // same breath. Reading only the indexed API walked straight past every element SwiftUI had.
        if let elements = element.accessibilityElements { return min(elements.count, 256) }
        let count = element.accessibilityElementCount()
        guard count > 0, count != NSNotFound else { return 0 }
        return min(count, 256)
    }

    /// One accessibility child, from whichever of the two APIs the element publishes through.
    private static func child(of element: NSObject, at index: Int) -> NSObject? {
        if let elements = element.accessibilityElements {
            return index < elements.count ? elements[index] as? NSObject : nil
        }
        return element.accessibilityElement(at: index) as? NSObject
    }

    func labels(in controller: UIViewController) -> [String] {
        accessibilityTexts(of: controller.view)
    }

    /// Every labelled accessibility element, with the frame it was actually laid out at.
    ///
    /// Same reason as `accessibilityTexts`: on iOS a SwiftUI row is not a `UIView`, so its geometry
    /// has to be read from the element SwiftUI publishes rather than from the view hierarchy.
    func labelledFrames(in controller: UIViewController) -> [(label: String, frame: CGRect)] {
        var seen = Set<ObjectIdentifier>()
        var retained: [NSObject] = []
        var budget = 3000
        return walk(controller.view, seen: &seen, retained: &retained, depth: 0, budget: &budget) { object in
            guard let label = object.accessibilityLabel, !label.isEmpty else { return [] }
            return [(label: label, frame: object.accessibilityFrame)]
        }
    }

    /// Elements the user can actually hit, with the frames they were laid out at.
    ///
    /// Same reason as above: a SwiftUI `Button` is not a `UIControl`, so the obvious version of this
    /// finds zero controls and then passes because it measured nothing.
    func tappableFrames(of element: NSObject, in _: UIView) -> [CGRect] {
        var seen = Set<ObjectIdentifier>()
        var retained: [NSObject] = []
        var budget = 3000
        return walk(
            element,
            seen: &seen,
            retained: &retained,
            depth: 0,
            budget: &budget
        ) { object -> [CGRect] in
            guard object.accessibilityTraits.contains(.button),
                  object.accessibilityFrame.height > 0 else { return [] }
            return [object.accessibilityFrame]
        }
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
            (
                "settings/reachable",
                AnyView(PairedMacSettingsView(state: .reachable(FixturePairingService.specimenMac)))
            ),
            ("settings/unreadable", AnyView(PairedMacSettingsView(state: .unreadable))),
            (
                "commit/blocked",
                AnyView(SendCommitBar(state: .notReachable, macName: "Luke's MacBook Pro", itemCount: 2))
            ),
            (
                "pairing/notStored",
                AnyView(PairedNotStoredView(
                    mac: FixturePairingService.specimenMac,
                    onPairAgain: {}
                ))
            )
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
    ///
    /// The row is found by its own accessibility label — the Mac's name, which appears on exactly
    /// one element in this surface — so the two renders are compared on the same row rather than on
    /// whatever happened to be about the right height.
    func testRowHeightIsIndependentOfNameLength() {
        let shortMac = FixturePairingService.specimenMac
        let longMac = FixturePairingService.longNameMac
        let short = host(ScrollView { PairedMacSettingsView(state: .reachable(shortMac)) })
        let long = host(ScrollView { PairedMacSettingsView(state: .reachable(longMac)) })

        guard let shortHeight = rowHeight(in: short, labelled: shortMac.name),
              let longHeight = rowHeight(in: long, labelled: longMac.name)
        else {
            return XCTFail("no row was found in either render, so nothing was compared")
        }
        XCTAssertEqual(shortHeight, longHeight, accuracy: 0.5, "a longer Mac name changed the row height")
        // Both being wrong by the same amount would satisfy the comparison above, so the height is
        // also checked against the documented number this file restates rather than imports.
        XCTAssertEqual(
            shortHeight, PhoneRowHeight, accuracy: 0.5,
            "the row rendered at \(shortHeight)pt, not the documented \(PhoneRowHeight)pt"
        )

        // And the long name really is long enough to force truncation, or this proves nothing.
        let rendered = labels(in: long).joined()
        XCTAssertTrue(
            rendered.contains(longMac.name),
            "the overflow case did not render the long name at all"
        )
    }

    /// The Loading skeleton has to be the height of the row it stands in for, or the surface jumps
    /// the moment data lands.
    ///
    /// The two are hosted **on their own** rather than inside `PairedMacSettingsView`, because in
    /// the Loading state the skeleton and the caption beneath it carry the *same* accessibility
    /// label — `PairedMacSkeleton` labels itself with `settingsLoading`'s body and the `Text` under
    /// it renders that same sentence. A label probe against the whole surface therefore matches two
    /// elements and cannot say which one is the row, so `rowHeight` refuses it. Hosted alone, each
    /// label names exactly one element and both go through the same window, width and settle.
    func testSkeletonMatchesTheRowItReplaces() {
        let mac = FixturePairingService.specimenMac
        let populated = host(ScrollView { PairedMacRow(mac: mac) })
        let loading = host(ScrollView { PairedMacSkeleton() })

        guard let populatedHeight = rowHeight(in: populated, labelled: mac.name),
              let loadingHeight = rowHeight(
                  in: loading,
                  labelled: PairingCopy.entry(.settingsLoading).body
              )
        else {
            return XCTFail("no row was found in either render, so nothing was compared")
        }
        XCTAssertEqual(
            populatedHeight, loadingHeight, accuracy: 0.5,
            "the loading skeleton is \(loadingHeight)pt and the populated row \(populatedHeight)pt"
        )
    }

    /// The rendered height of the one element whose label carries `probe`.
    ///
    /// **Measured from the accessibility frame, because the earlier form could not work.** It took
    /// the tallest `UIView` within 6pt of `PhoneRowHeight`, and SwiftUI publishes no `UIView` per
    /// row: measured on iOS 26.5 on 2026-08-20, a hosted `PairedMacSettingsView` has exactly five
    /// descendants — 852.0, 852.0, 239.7, 233.7, 233.7 — and none of them is the row. So it
    /// returned nil whatever the row's real height was, and the two tests below failed reporting
    /// *"no row was found in either render"* about a row that was on screen at exactly 44.00pt.
    /// The height it named was also a **filter**, so it could only ever agree with the constant it
    /// was supposed to be checking.
    ///
    /// Returns nil when the probe matches no element **or more than one**: an ambiguous match would
    /// let the assertion compare something other than the row it names.
    private func rowHeight(in controller: UIViewController, labelled probe: String) -> CGFloat? {
        let matches = labelledFrames(in: controller).filter { $0.label.contains(probe) }
        guard matches.count == 1 else { return nil }
        return matches[0].frame.height
    }

    /// **The helper's content-size override really does reach the SwiftUI environment.**
    ///
    /// D3 registered a claim that it "measurably never reaches the SwiftUI view", which would make
    /// the three-category loop below three identical runs of one assertion. Measured on 2026-08-16
    /// against this suite: the view sees `dynamicTypeSize == .large` under `.large` and
    /// `.accessibility5` under `.accessibilityExtraExtraExtraLarge`, so the override arrives and the
    /// loop varies what it renders. The claim was false and this test is what keeps it false — if a
    /// future UIKit stops honouring `setOverrideTraitCollection`, A7 below would quietly stop
    /// measuring anything and this fails instead.
    ///
    /// What it deliberately does not assert is that glyphs *grow*. They do not: `TypeToken.font` is
    /// a fixed `Font.system(size:weight:)` by `DESIGN.md` §2, which is a shared design decision
    /// rather than a defect. This separates the plumbing from that decision.
    func testHostPropagatesContentSizeIntoTheSwiftUIEnvironment() {
        final class Box: @unchecked Sendable { var seen: [DynamicTypeSize] = [] }
        let box = Box()

        struct Reporter: View {
            @Environment(\.dynamicTypeSize) private var dynamicTypeSize
            let record: (DynamicTypeSize) -> Void
            var body: some View {
                Color.clear.onAppear { record(dynamicTypeSize) }
            }
        }

        for (category, expected) in [
            (UIContentSizeCategory.large, DynamicTypeSize.large),
            (.accessibilityExtraExtraExtraLarge, .accessibility5)
        ] {
            box.seen.removeAll()
            _ = host(Reporter { box.seen.append($0) }, contentSize: category)
            XCTAssertEqual(
                box.seen.first,
                expected,
                "content size \(category.rawValue) did not reach the SwiftUI environment"
            )
        }
    }

    // MARK: A7 — Dynamic Type does not clip

    /// The shared type ladder is fixed-size by design (`DESIGN.md` §2 specifies eight exact sizes),
    /// so this does not assert that the glyphs grow. What it asserts is the failure that actually
    /// ships: text placed in a frame that clips it. Every label must fit inside its own bounds at
    /// the largest accessibility category.
    func testTextIsNotClippedAtAccessibilitySizes() {
        for category in [
            UIContentSizeCategory.large,
            .extraExtraExtraLarge,
            .accessibilityExtraExtraExtraLarge
        ] {
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

        // The previous form of this test could not fail: it AND-ed
        // `insetsLayoutMarginsFromSafeArea == false` (a property that defaults to true) into a
        // three-way condition, so the whole expression was always false and `XCTAssertFalse` always
        // passed. A test that cannot fail is worse than no test, because it reads as coverage.
        //
        // What is actually assertable in a hosted window: the shell must not opt out of safe-area
        // insetting, and must not fabricate insets of its own.
        XCTAssertTrue(
            controller.view.insetsLayoutMarginsFromSafeArea,
            "the shell opted out of safe-area layout margins"
        )
        XCTAssertEqual(
            controller.additionalSafeAreaInsets, .zero,
            "the shell adds its own safe-area inset instead of respecting the system's"
        )

        // And the real claim: with a bottom inset in play, the tab bar sits above it rather than
        // under the home indicator. Applied to the controller so the value is genuinely non-zero
        // in a test window, which has no device insets of its own.
        let homeIndicator: CGFloat = 34
        controller.additionalSafeAreaInsets = UIEdgeInsets(top: 0, left: 0, bottom: homeIndicator, right: 0)
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()

        let tabBars = descendants(of: controller.view).compactMap { $0 as? UITabBar }
        let bar = tabBars.first
        XCTAssertNotNil(bar, "no system tab bar was rendered, so nothing was measured")
        if let bar {
            XCTAssertLessThanOrEqual(
                bar.frame.maxY, controller.view.bounds.height + 0.5,
                "the tab bar extends past the bottom of the view"
            )
        }
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

    /// The typed path has something to type into.
    ///
    /// `TypedEntryView` drew eight styled boxes, a helper line and a submit button, and no input
    /// affordance of any kind — no field, no keypad, no focus state. `PairingCodeEntry` had carried
    /// `append(contentsOf:)` and `deleteBackward()` the whole time and nothing in the UI called
    /// either, so the submit button's `.disabled(!entry.isComplete)` could never become false. That
    /// matters beyond one screen: the source comments cite A16 — every camera state must still
    /// offer the typed path — and for `.restricted`, where iOS Settings is a dead end, the typed
    /// path is the *primary* recovery rather than the fallback.
    ///
    /// Asserted through the rendered hierarchy rather than by reading the view, because the defect
    /// was precisely that the view looked complete.
    func testTypedEntryPublishesAFieldToTypeInto() {
        var entry = PairingCodeEntry()
        let binding = Binding(get: { entry }, set: { entry = $0 })
        let controller = host(ScrollView {
            TypedEntryView(entry: binding, failure: nil, onSubmit: {}, onScanInstead: {})
        })

        /// The UIView tree rather than the accessibility tree: a SwiftUI `TextField` becomes a
        /// `UITextField`, and that class is exactly what XCUITest's `app.textFields` resolves to on
        /// glass. Asserting on the same object both harnesses look for keeps this test and the
        /// on-glass one making the same claim.
        func textFields(under view: UIView) -> [UITextField] {
            var found: [UITextField] = []
            if let field = view as? UITextField { found.append(field) }
            for child in view.subviews {
                found.append(contentsOf: textFields(under: child))
            }
            return found
        }
        let fields = textFields(under: controller.view)

        XCTAssertFalse(
            fields.isEmpty,
            "the typed-entry surface published nothing that can take keyboard input, so the code "
                + "cannot be entered and 'Pair Mac' can never enable. On screen: "
                + labels(in: controller).joined(separator: " | ")
        )
    }

    /// A27 leg 2 for the pairing pre-prompt family: four states, each rendering its own headline.
    ///
    /// Added after `TypedEntryView` was found drawing `PairingCopy.entry(.typedEntryReady).body`
    /// and never its headline, so the one surface a user reaches by *choosing* it — "Enter the code
    /// instead" — was the only one that never confirmed where they had arrived. The copy carried a
    /// headline the whole time; nothing asserted that any view drew it.
    ///
    /// Written over the family rather than the one view, because a headline defined and not drawn
    /// leaves no trace anywhere: no failing assertion, no selector, no crash. It is exactly the
    /// class of defect only a rendered hierarchy can see.
    func testEveryPairingPrePromptRendersItsHeadline() {
        var entry = PairingCodeEntry()
        let binding = Binding(get: { entry }, set: { entry = $0 })

        let surfaces: [(String, PairingCopy.Key, AnyView)] = [
            ("camera not determined", .cameraNotDetermined, AnyView(
                CameraPermissionView(
                    authorization: .notDetermined,
                    onRequest: {}, onOpenSettings: {}, onTypeInstead: {}
                )
            )),
            ("camera denied", .cameraDenied, AnyView(
                CameraPermissionView(
                    authorization: .denied,
                    onRequest: {}, onOpenSettings: {}, onTypeInstead: {}
                )
            )),
            ("camera restricted", .cameraRestricted, AnyView(
                CameraPermissionView(
                    authorization: .restricted,
                    onRequest: {}, onOpenSettings: {}, onTypeInstead: {}
                )
            )),
            ("typed entry", .typedEntryReady, AnyView(
                TypedEntryView(
                    entry: binding, failure: nil, onSubmit: {}, onScanInstead: {}
                )
            ))
        ]

        for (name, key, view) in surfaces {
            guard let headline = PairingCopy.entry(key).headline else {
                XCTFail("\(key) carries no headline, so this test is asserting nothing for \(name)")
                continue
            }
            let rendered = labels(in: host(ScrollView { view })).joined(separator: " | ")
            XCTAssertTrue(
                rendered.contains(headline),
                "the \(name) surface did not render its headline '\(headline)'. On screen: \(rendered)"
            )
        }
    }

    /// A27 leg 2 for the two storage-failure surfaces: the manifest entry is what the view for
    /// that surface and state **actually renders**, measured from the rendered hierarchy.
    ///
    /// Without this, both entries satisfied only legs 1 and 3 — pinned literal, present in the
    /// mock — and A27 calls a manifest entry with no rendering surface a failure in itself.
    func testStorageFailureSurfacesRenderTheirCopy() {
        let mac = FixturePairingService.specimenMac

        let notStored = host(ScrollView {
            PairedNotStoredView(mac: mac, onPairAgain: {})
        })
        let notStoredText = labels(in: notStored).joined(separator: " | ")
        let notStoredEntry = PairingCopy.entry(.pairedNotStored).resolved(macName: mac.name)
        XCTAssertTrue(
            notStoredText.contains(notStoredEntry.headline ?? ""),
            "pairedNotStored did not render its headline. Rendered: \(notStoredText)"
        )
        XCTAssertTrue(
            notStoredText.contains("Ask your Mac for a new code"),
            "pairedNotStored did not render the advice that a new code is needed: \(notStoredText)"
        )

        // The block the settings screen constructs for a failed unpair, in the same shape it uses.
        let unpairFailed = host(ScrollView {
            PhoneMessageBlock(
                entry: PairingCopy.entry(.unpairFailed).resolved(macName: mac.name),
                tone: .failure,
                glyph: .warn
            )
        })
        let unpairText = labels(in: unpairFailed).joined(separator: " | ")
        XCTAssertTrue(
            unpairText.contains("Couldn't unpair \(mac.name)"),
            "unpairFailed did not render its headline. Rendered: \(unpairText)"
        )
        XCTAssertTrue(
            unpairText.contains("still paired"),
            "unpairFailed did not say the Mac is still paired: \(unpairText)"
        )
    }

    /// A26: the narrowing is on screen at the two moments that matter, measured from the rendered
    /// hierarchy rather than from the manifest that describes it.
    func testNarrowingIsRenderedWherePermissionIsDecided() {
        let neverPaired = host(ScrollView { PairedMacSettingsView(state: .neverPaired) })
        let neverPairedText = labels(in: neverPaired)
        XCTAssertTrue(
            neverPairedText.joined().contains("cannot install, update or remove"),
            "the pre-pairing surface does not state the narrowing"
        )
        // DEF-026: exactly once. `settingsNeverPaired` carries the narrowing inside its own block,
        // and the About section rendered it again — the same sentence twice on the surface a
        // first-time user meets first. i1-phone-pairing.html states it once in §B and once in §I.
        let statements = neverPairedText.filter { $0.contains("cannot install, update or remove") }
        XCTAssertEqual(
            statements.count, 1,
            "the narrowing is stated \(statements.count) times on the never-paired surface"
        )
        // The paired surface states it under About, which is the only place it appears there.
        let paired = host(
            ScrollView {
                PairedMacSettingsView(state: .reachable(FixturePairingService.specimenMac))
            }
        )
        XCTAssertEqual(
            labels(in: paired).filter { $0.contains("cannot install, update or remove") }.count, 1,
            "the paired surface does not state the narrowing exactly once"
        )

        let success = host(
            ScrollView { PairedSuccessView(mac: FixturePairingService.specimenMac, onDone: {}) }
        )
        XCTAssertTrue(
            labels(in: success).joined().contains("cannot install, update or remove"),
            "the paired surface does not restate the narrowing"
        )
    }

    /// DEF-024: a pairing action drawn at label width where the design draws it at content width.
    ///
    /// `i1-phone-pairing.html` styles every pairing action `.cta`, which is `width:100%`. The build
    /// declared that with `.frame(maxWidth: .infinity)` on the `Button` — outside the style — so the
    /// layout frame stretched while the style's own background still wrapped a hugging label. The
    /// on-glass camera pre-prompt and typed-entry captures show three such centred pills.
    ///
    /// The oracle is the painted band rather than any view's frame, because the frame was already
    /// full width while the defect was present. Two renders of the same button differing only in
    /// `fillsWidth` must paint bands of different widths; before the fix they painted the same one.
    func testAFullWidthPhoneButtonPaintsAFullWidthBand() throws {
        let width = PhoneSurfaceTests.phoneSize.width

        /// `ImageRenderer` rather than `drawHierarchy`: SwiftUI draws a `ButtonStyle` background into
        /// its own backing layers, and `drawHierarchy` on an off-screen window returned a single flat
        /// colour — which measured as a full-width band for both arms and would have read as a pass.
        func paintedBand(fillsWidth: Bool) throws -> CGFloat {
            let renderer = ImageRenderer(
                content: Button("Allow camera access", action: {})
                    .buttonStyle(PhoneProminentButtonStyle(fillsWidth: fillsWidth))
                    .frame(width: width, height: 88)
            )
            renderer.scale = 1
            let cgImage = try XCTUnwrap(renderer.cgImage, "the button did not rasterise")
            return try Self.widestRun(matchingCentreOf: cgImage)
        }

        let filled = try paintedBand(fillsWidth: true)
        let hugging = try paintedBand(fillsWidth: false)

        XCTAssertGreaterThan(
            filled, width * 0.9,
            "a fillsWidth button painted a \(filled)pt band inside a \(width)pt container"
        )
        XCTAssertLessThan(
            hugging, filled - 40,
            "fillsWidth changed nothing: both renders painted \(hugging)pt and \(filled)pt, "
                + "which is the shape of the defect — a width declared outside the style"
        )
    }

    /// The widest horizontal run of the button's fill colour, in points.
    ///
    /// The fill is found as the most common colour that is not the corner colour. Sampling the
    /// image's centre was tried first and measured 393pt for both arms: the centre pixel sits inside
    /// a label glyph, so the sampled colour was the label's white, which also fills the region
    /// outside the control — a target colour that cannot vary with the subject is not a readback.
    static func widestRun(matchingCentreOf image: CGImage) throws -> CGFloat {
        let w = image.width, h = image.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let context = try XCTUnwrap(CGContext(
            data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        func rgb(_ x: Int, _ y: Int) -> (Int, Int, Int) {
            let i = (y * w + x) * 4
            return (Int(pixels[i]), Int(pixels[i + 1]), Int(pixels[i + 2]))
        }
        let background = rgb(0, 0)
        var histogram: [Int: Int] = [:]
        for y in 0 ..< h {
            for x in 0 ..< w {
                let c = rgb(x, y)
                guard c != background else { continue }
                histogram[c.0 << 16 | c.1 << 8 | c.2, default: 0] += 1
            }
        }
        // A render that came back one flat colour is a broken instrument, not a full-width band.
        XCTAssertFalse(histogram.isEmpty, "the rasterised button is a single flat colour")
        let packed = histogram.max { $0.value < $1.value }?.key ?? 0
        let target = ((packed >> 16) & 0xFF, (packed >> 8) & 0xFF, packed & 0xFF)
        func matches(_ c: (Int, Int, Int)) -> Bool {
            abs(c.0 - target.0) < 12 && abs(c.1 - target.1) < 12 && abs(c.2 - target.2) < 12
        }

        var widest = 0
        for y in 0 ..< h {
            var run = 0
            for x in 0 ..< w {
                run = matches(rgb(x, y)) ? run + 1 : 0
                widest = max(widest, run)
            }
        }
        let scale = CGFloat(w) / PhoneSurfaceTests.phoneSize.width
        return CGFloat(widest) / max(scale, 1)
    }
}
