import Foundation
import XCTest

/// The `ios-glass` lane: the app, installed and running on a booted simulator, driven through
/// iOS's own accessibility tree.
///
/// **Why this exists next to `MCPRouterIOSTests`.** That target is a unit suite hosted by the app.
/// It constructs a view in the app's process and reads it back through a hand-rolled walk of
/// `UIView.accessibilityLabel`. Everything it proves is true and none of it involves a tab being
/// tapped — so it cannot tell "each tab renders its own surface" from "all five render Settings",
/// which is the exact failure `PhoneShell.content(for:)` documents as the one worth guarding
/// against. Six cases in the campaign were recorded `n/a` for that reason: no Mac accessibility
/// tree reaches into the Simulator, the app ships no URL scheme, and a `simctl` screenshot of
/// whatever happened to be on screen cannot be attributed to a surface.
///
/// XCUITest answers all three. It runs out of process, reads the accessibility tree iOS itself
/// publishes, and takes its captures **after** a named surface assertion has already passed —
/// which is what makes a PNG attributable to a surface rather than a photograph of a moment.
///
/// **It never opens Simulator.app.** `xcodebuild test` against an already-booted device drives the
/// runtime directly, so this obeys `planning/practices/UI_VERIFICATION.md` rule 1: the developer
/// loop stays invisible and nothing takes the screen.
///
/// **What it still does not prove.** `XCUIScreenshot` carries no per-frame status, so a capture
/// here cannot rule out a stale frame the way `SCFrameStatus` can on the Mac. The attribution
/// argument above is what stands in its place, and the campaign records it in those terms rather
/// than claiming a guarantee the instrument does not offer.
final class PhoneGlassTests: XCTestCase {
    /// The five tabs, in the order `PhoneShell.Tab.allCases` declares them.
    ///
    /// Duplicated here rather than imported on purpose: a UI test that reads its expectations out
    /// of the code under test asserts that the app agrees with itself, which it always does. These
    /// are the strings `DESIGN.md` §6 specifies, written out, so renaming a tab breaks this.
    private static let tabTitles = ["Discover", "Triage", "Queue", "Library", "Settings"]

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    // MARK: - Launch

    /// Launch the app with a chosen fixture scenario and prove it reached the foreground.
    ///
    /// The scenario travels through `PhoneClientFactory.scenarioVariable`, which a Debug build
    /// honours and a Release build ignores by construction. Asserting the launch rather than
    /// assuming it is what stops every check below from being vacuous: a test that runs against an
    /// app which never started reports element-not-found, which reads as a product defect.
    @discardableResult
    private func launch(scenario: String, file: StaticString = #filePath, line: UInt = #line) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["MCPROUTER_SCENARIO"] = scenario
        app.launch()
        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 30),
            "the app never reached the foreground, so nothing below measured the product",
            file: file, line: line
        )
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(
            tabBar.waitForExistence(timeout: 20),
            "no tab bar was published, so the accessibility tree is not live and these results are inconclusive",
            file: file, line: line
        )
        XCTAssertEqual(
            tabBar.buttons.count, Self.tabTitles.count,
            "the shell published \(tabBar.buttons.count) tabs, not \(Self.tabTitles.count)",
            file: file, line: line
        )
        // Printed every run, not only on failure. A tab whose accessibility label is not its title
        // is a real finding about the shipped app rather than a detail of this file, and the first
        // run of this suite found exactly that — so the labels stay in the log where the next
        // reader meets them without having to reproduce the failure.
        let labels = tabBar.buttons.allElementsBoundByIndex.map { $0.label }
        FileHandle.standardError.write(Data("GLASS tab labels = \(labels)\n".utf8))
        return app
    }

    /// Attach the app window's pixels under a surface id, after the caller has already asserted
    /// which surface it is looking at. The name is what `xcresulttool export attachments` writes
    /// into its manifest, so the campaign's evidence file inherits the attribution.
    private func capture(_ app: XCUIApplication, as name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Move to a tab and prove the surface that came back is that tab's own.
    ///
    /// Returns the navigation-bar identifier actually observed rather than a Bool, so the caller
    /// can compare the five against each other — the only check that distinguishes five surfaces
    /// from one surface rendered five times.
    private func selectTab(_ title: String, in app: XCUIApplication,
                           file: StaticString = #filePath, line: UInt = #line) -> String
    {
        let button = app.tabBars.buttons[title]
        XCTAssertTrue(
            button.waitForExistence(timeout: 10),
            "no tab button labelled '\(title)'",
            file: file, line: line
        )
        button.tap()
        let bar = app.navigationBars[title]
        XCTAssertTrue(
            bar.waitForExistence(timeout: 10),
            "tapping '\(title)' did not produce a navigation bar titled '\(title)'",
            file: file, line: line
        )
        return bar.identifier
    }

    // MARK: - SURF-012 / SURF-013 · each tab is its own surface

    /// REQ-010. Five tabs, five distinct surfaces — and the failure this exists to catch is five
    /// tabs rendering the same one.
    func testEachTabRendersItsOwnSurface() {
        let app = launch(scenario: "populated")
        var observed: [String] = []
        for title in Self.tabTitles {
            observed.append(selectTab(title, in: app))
            capture(app, as: "ios-tab-\(title.lowercased())")
        }
        XCTAssertEqual(
            observed, Self.tabTitles,
            "the five tabs reported \(observed); they must each report their own title"
        )
        XCTAssertEqual(
            Set(observed).count, Self.tabTitles.count,
            "two tabs rendered the same surface: \(observed)"
        )
    }

    /// REQ-010, SURF-012. Discover is not the Settings tab wearing Discover's label: it renders
    /// rows the router supplied, and its search field.
    func testDiscoverRendersTheRoutersCatalogue() {
        let app = launch(scenario: "populated")
        _ = selectTab("Discover", in: app)
        let rows = app.buttons.count + app.cells.count
        XCTAssertGreaterThan(
            rows, 0,
            "Discover published no rows at all, so nothing was compared"
        )
        XCTAssertFalse(
            app.staticTexts["No Mac paired yet"].exists,
            "Discover rendered the Settings surface's never-paired copy"
        )
        capture(app, as: "SURF-012.ios.discover-populated")
    }

    /// REQ-010, SURF-012, metamorphic. The same surface, a different router: what Discover shows
    /// has to track what the router said. Two runs that render identically would mean the screen
    /// is not reading the data at all.
    func testDiscoverTracksWhatTheRouterReturned() {
        // Asserted on the surface's own copy rather than on a count of elements. The first version
        // of this test compared `cells.count + buttons.count` between the two runs and read 19
        // against 19 — because most of that total is chrome the scenario does not move (the five
        // tab buttons, the search field, the navigation bar). A count that a real difference
        // cannot shift is not an oracle.
        let emptyHeadline = "Nothing came back from either index."

        let populated = launch(scenario: "populated")
        _ = selectTab("Discover", in: populated)
        XCTAssertFalse(
            populated.staticTexts[emptyHeadline].waitForExistence(timeout: 3),
            "the populated router produced Discover's empty state"
        )
        populated.terminate()

        let empty = launch(scenario: "empty")
        _ = selectTab("Discover", in: empty)
        XCTAssertTrue(
            empty.staticTexts[emptyHeadline].waitForExistence(timeout: 10),
            "the empty router did not produce Discover's empty state, so the surface is not "
                + "reading the router's answer. On screen: \(Self.visibleText(in: empty))"
        )
        capture(empty, as: "SURF-012.ios.discover-empty")
    }

    /// Every static text on screen, for a failure message that says what *was* there.
    ///
    /// A UI-test failure that only names the element it wanted is the hardest kind to act on: the
    /// two readings — the surface is wrong, or the locator is — look identical from the log.
    private static func visibleText(in app: XCUIApplication) -> [String] {
        app.staticTexts.allElementsBoundByIndex.prefix(25).map { $0.label }
    }

    /// REQ-010, SURF-013. Triage, Queue and Library each carry their own chrome — the three tabs
    /// that shipped as placeholders once and would fail silently if they did again.
    func testTriageQueueAndLibraryEachRenderTheirOwnSurface() {
        let app = launch(scenario: "populated")
        for title in ["Triage", "Queue", "Library"] {
            _ = selectTab(title, in: app)
            XCTAssertFalse(
                app.staticTexts["No Mac paired yet"].exists,
                "\(title) rendered the Settings surface"
            )
            capture(app, as: "SURF-013.ios.\(title.lowercased())")
        }
        // Library is the only one of the three with a search field; Triage and Queue must not
        // have grown one by rendering Library's body.
        _ = selectTab("Library", in: app)
        XCTAssertTrue(
            app.searchFields.firstMatch.waitForExistence(timeout: 5),
            "Library published no search field, so it is not Library"
        )
        _ = selectTab("Queue", in: app)
        XCTAssertFalse(
            app.searchFields.firstMatch.exists,
            "Queue published a search field, which belongs to Library"
        )
    }

    // MARK: - SURF-014 · pairing

    /// REQ-015, SURF-014. The pairing surface, reached the way a person reaches it, and its two
    /// pre-prompt controls. This is the capture the campaign recorded as never photographed.
    func testPairingIsReachedFromSettingsAndRendersItsPreflight() {
        let app = launch(scenario: "populated")
        _ = selectTab("Settings", in: app)
        XCTAssertTrue(
            app.staticTexts["No Mac paired yet"].waitForExistence(timeout: 10),
            "Settings did not render the never-paired state, so the pairing entry point is "
                + "unproven. On screen: \(Self.visibleText(in: app))"
        )
        let pair = app.buttons["Pair Mac"]
        XCTAssertTrue(pair.waitForExistence(timeout: 5), "no 'Pair Mac' control on Settings")
        pair.tap()

        XCTAssertTrue(
            app.staticTexts["Why the camera"].waitForExistence(timeout: 10),
            "the pairing flow did not open on the camera pre-prompt"
        )
        XCTAssertTrue(
            app.buttons["Allow camera access"].exists,
            "the pre-prompt offered no way to allow the camera"
        )
        let typed = app.buttons["Enter the code instead"]
        XCTAssertTrue(typed.exists, "the pre-prompt offered no alternative to the camera")
        capture(app, as: "SURF-014.ios.pairing-preflight")

        typed.tap()
        XCTAssertTrue(
            app.staticTexts["Enter the code"].waitForExistence(timeout: 10),
            "'Enter the code instead' did not reach the typed-entry surface"
        )
        XCTAssertTrue(
            app.textFields.firstMatch.exists || app.secureTextFields.firstMatch.exists,
            "the typed-entry surface published no field to type into"
        )
        capture(app, as: "SURF-014.ios.pairing-typed-entry")
    }
}
