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
/// Surface identity and surface state are two assertions, and the capture belongs between them.
/// `selectTab` proves *which* surface is on screen; the checks after it prove *what state* it is
/// in. Shooting once identity is established and before state is judged keeps the attribution
/// argument intact and still yields a picture when the state assertion is the one that fails —
/// the first run of this suite produced a full description of a wrong Settings state and no
/// photograph of it, and the campaign had to record the surface as inconclusive with the
/// instrument sitting right there.
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
    private func launch(
        scenario: String,
        camera: String? = nil,
        file: StaticString = #filePath, line: UInt = #line
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["MCPROUTER_SCENARIO"] = scenario
        // Left unset by every test but the pairing one, so those runs exercise the real
        // `LiveCameraAuthorization`. `PhoneCameraFactory` carries the measurement that makes this
        // necessary: the simulator answers `.authorized` and no `simctl` verb changes it.
        if let camera { app.launchEnvironment["MCPROUTER_CAMERA"] = camera }
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
        // `\.label` and `\.identifier` are main-actor isolated on `XCUIElement`, and a key
        // path to one does not compile — "cannot form key path to main actor-isolated
        // property". The closure is the form that builds, so the rule is switched off on
        // the one line rather than the code bent to satisfy it.
        // swiftformat:disable:next preferKeyPath
        let labels = tabBar.buttons.allElementsBoundByIndex.map { $0.label }
        FileHandle.standardError.write(Data("GLASS tab labels = \(labels)\n".utf8))
        return app
    }

    /// Attach the app window's pixels under a surface id, after the caller has already asserted
    /// which surface it is looking at. The name is what `xcresulttool export attachments` writes
    /// into its manifest, so the campaign's evidence file inherits the attribution.
    /// The prefix that separates a capture this suite took from a diagnostic XCTest took.
    ///
    /// A failing run attaches its own artifacts — `UI Snapshot`, `Screen Recording`,
    /// `App UI hierarchy`, and a `Debug description` per failed query — and those arrive in the
    /// same export as the captures. `name-glass-attachments.py` used to treat all of them as
    /// evidence, and on the first red run two of XCTest's `Debug description` files were
    /// byte-identical (they describe the same query, twice), which tripped its shared-image check
    /// and stopped the export half-renamed. The check is right; its population was wrong.
    ///
    /// Marking ours makes the split explicit rather than inferred from filename shape, so a
    /// diagnostic XCTest adds in a future Xcode cannot be mistaken for a capture.
    /// Hyphen-separated and punctuation-free on purpose. The first version ended in a colon and
    /// XCTest silently dropped it, so every capture arrived as `GLASS-CAPTURESURF-012.ios…` and the
    /// naming script matched none of them — a marker the export can edit is not a marker.
    static let captureMarker = "GLASS-CAPTURE-"

    /// The prefix on the lineage record that travels with each capture.
    ///
    /// The campaign's rule is that provenance is written by the capturing process at shutter time;
    /// a manifest assembled afterwards is reconstruction, and reconstruction cannot distinguish a
    /// picture of the right thing from a picture filed under the right name. So each capture is
    /// accompanied by a second attachment carrying what only this process knows at that instant:
    /// which surface was claimed, and what the app itself reported being on when the shutter fired.
    static let lineageMarker = "GLASS-LINEAGE-"

    /// Photograph the app, and record what it said it was showing while doing so.
    ///
    /// `target` is a **readback**, not a label: it is the navigation bar's own identifier at the
    /// moment of capture. That is what makes the picture attributable — a capture whose recorded
    /// target does not tie to its subject's route is a capture of something else, and the lineage
    /// gate is built to catch exactly that.
    private func capture(_ app: XCUIApplication, as name: String) {
        let shot = app.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = Self.captureMarker + name
        attachment.lifetime = .keepAlways
        add(attachment)

        let bar = app.navigationBars.firstMatch
        let readback = bar.exists ? bar.identifier : "no-navigation-bar"
        let lineage: [String: String] = [
            "subject": String(name.prefix(while: { $0 != "." })),
            "name": name,
            "target": "app://ios/\(readback.lowercased().replacingOccurrences(of: " ", with: "-"))",
            "targetReadback": readback,
            "channel": "XCUIScreenshot via XCTAttachment, in-test, after this surface's assertion",
            "derivedFrom": "\(Self.self)/\(self.name)",
            "appState": String(app.state.rawValue)
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: lineage, options: [.sortedKeys])
        else { return }
        let record = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        record.name = Self.lineageMarker + name
        record.lifetime = .keepAlways
        add(record)
    }

    /// Move to a tab and prove the surface that came back is that tab's own.
    ///
    /// Returns the navigation-bar identifier actually observed rather than a Bool, so the caller
    /// can compare the five against each other — the only check that distinguishes five surfaces
    /// from one surface rendered five times.
    ///
    /// **Why the tap is retried, and why the retry watches the navigation bar.** The first version
    /// tapped as soon as the button *existed* and then waited on the navigation bar once. That
    /// passed on a freshly installed app and failed on the next two runs, because iOS restores the
    /// last tab: run 1 launched on Discover, so the opening `selectTab("Discover")` asked for the
    /// tab already showing and no tap had to land for the assertion to hold. Runs 2 and 3 launched
    /// on Settings, the opening tap went to a tab bar that existed but was not yet hittable, and
    /// the app stayed on Settings — the tree at the failure showed `NavigationBar identifier:
    /// 'Settings'` with the Settings tab still `Selected`. Existence is not hittability, and a
    /// suite whose first action is a tap that can silently miss is not measuring the product.
    ///
    /// The retry that fixed it first gated on `isSelected`, and that was the wrong oracle. Under
    /// load — two `swift build`s beside the simulator — three taps in a row were observed leaving
    /// `isSelected` false on a tab whose surface had in fact arrived, on three different tabs
    /// across two runs. `isSelected` is the tab bar's own bookkeeping and it republishes on its own
    /// schedule; the navigation bar is the claim this suite actually makes. So the loop taps until
    /// the *destination* appears, and `isSelected` is read only to decide whether a tap is needed
    /// at all and to describe a failure. A precondition stricter than the assertion turns a busy
    /// machine into a red run about nothing.
    private func selectTab(
        _ title: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> String {
        let button = app.tabBars.buttons[title]
        XCTAssertTrue(
            button.waitForExistence(timeout: 10),
            "no tab button labelled '\(title)'",
            file: file, line: line
        )
        // `expectation(for:evaluatedWith:)` and `waitForExpectations` are main-actor isolated on
        // the XCTestCase instance, and this helper is called from a task-isolated context, so the
        // pair does not compile here. XCTWaiter takes the same predicate without the isolation.
        let hittable = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == true"), object: button
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [hittable], timeout: 10), .completed,
            "the tab button labelled '\(title)' never became hittable",
            file: file, line: line
        )

        let bar = app.navigationBars[title]
        var arrived = bar.exists
        for attempt in 1 ... 3 where !arrived {
            // Skip the tap when the tab bar already says we are here — the app restores its last
            // tab, so the first selectTab of a run is often a no-op and tapping the current tab
            // would pop its stack instead.
            if !button.isSelected || !bar.exists { button.tap() }
            let present = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "exists == true"), object: bar
            )
            arrived = XCTWaiter().wait(for: [present], timeout: 8) == .completed
            if !arrived {
                let note = "GLASS tap \(attempt) on '\(title)' did not produce its navigation "
                    + "bar (isSelected=\(button.isSelected))\n"
                FileHandle.standardError.write(Data(note.utf8))
            }
        }
        // The app's own state is named in the failure, because the most confusing way this can go
        // red is not a defect at all: on a shared simulator another project's app can take the
        // foreground mid-test, and every tap after that lands somewhere else. Measured 20 Aug 2026,
        // and the fix is that the lane now owns its device — this line is what would have said so
        // in one read instead of five runs.
        XCTAssertTrue(
            arrived,
            "three taps on '\(title)' never produced a navigation bar titled '\(title)', so the "
                + "surface below is not this tab's. The tab bar reports "
                + "isSelected=\(button.isSelected) for it, and the app under test is in state "
                + "\(app.state.rawValue) (4 = runningForeground; anything else means these taps "
                + "did not reach it).",
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
        }
        // **No captures here, deliberately.** This test's claim is that the five tabs differ from
        // *each other*, and the two assertions below are what prove it — five identifiers, five
        // distinct. The pictures it used to take were of the same five surfaces the surface-named
        // tests photograph (`SURF-012.ios.*`, `SURF-013.ios.*`, `SURF-018.ios.*`), byte-identical
        // to them, and the export's shared-image check caught the pair: `ios-tab-library.png`
        // against `SURF-013.ios.library.png`. Two names over one picture means one of the two was
        // never photographed, so the generic set went and the surface-named set stayed — those are
        // the ones the campaign's inventory can tie a subject to.
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
        // `\.label` and `\.identifier` are main-actor isolated on `XCUIElement`, and a key
        // path to one does not compile — "cannot form key path to main actor-isolated
        // property". The closure is the form that builds, so the rule is switched off on
        // the one line rather than the code bent to satisfy it.
        // swiftformat:disable:next preferKeyPath
        app.staticTexts.allElementsBoundByIndex.prefix(25).map { $0.label }
    }

    /// REQ-010, SURF-013. Triage, Queue and Library each carry their own chrome — the three tabs
    /// that shipped as placeholders once and would fail silently if they did again.
    func testTriageQueueAndLibraryEachRenderTheirOwnSurface() {
        let app = launch(scenario: "populated")
        // One surface id each. These three shipped enumerated as a single SURF-013, and the
        // campaign's tie pass caught it: two of the three captures named targets — app://ios/queue
        // and app://ios/library — that do not resolve to SURF-013's route. Three screens counted as
        // one understate the denominator, and this test was already asserting that all three
        // differ, so all three were being exercised while one was being counted.
        // Each surface names a string only it renders. "not Settings" was the whole of this
        // assertion before, and a not-that predicate is satisfied by every other screen in the app
        // — including a blank one, which is the shape a missing body actually takes.
        let surfaces = [
            ("Triage", "SURF-013", "Undecided"),
            ("Queue", "SURF-019", "Nothing waiting"),
            ("Library", "SURF-020", "Skills are not listed here.")
        ]
        for (title, surface, ownText) in surfaces {
            _ = selectTab(title, in: app)
            XCTAssertFalse(
                app.staticTexts["No Mac paired yet"].exists,
                "\(title) rendered the Settings surface"
            )
            XCTAssertTrue(
                app.staticTexts[ownText].waitForExistence(timeout: 8),
                "\(title) did not render '\(ownText)', which is its own and no other surface's. "
                    + "On screen: \(Self.visibleText(in: app))"
            )
            capture(app, as: "\(surface).ios.\(title.lowercased())")
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
        // `notDetermined` is asked for rather than assumed. Measured 20 Aug 2026: this simulator
        // reports the camera as `.authorized` on a fresh install and after `simctl privacy reset
        // all`, so tapping 'Pair Mac' went straight to the scanner and this test failed on an
        // assertion that was correct about the product — the pre-prompt exists, and the instrument
        // could not produce the state that shows it. What this proves is that the surface renders
        // the pre-prompt for a given authorization state; that `AVAuthorizationStatus` maps to that
        // state is `CameraAuthorizationTests`' claim, on the host, and the two are kept apart.
        let app = launch(scenario: "populated", camera: "notDetermined")
        _ = selectTab("Settings", in: app)
        // `selectTab` has already proved this is the Settings surface, so the capture is
        // attributed. What follows judges its state, and that is the assertion that has been
        // failing — so the shot goes here, where it survives a red run.
        // Named for what it shows. It was `settings-paired-state`, and the picture is the
        // *never*-paired state — a filename claiming a subject it does not show is the hazard this
        // campaign's capture lineage exists to close.
        capture(app, as: "SURF-018.ios.settings-never-paired")
        XCTAssertTrue(
            app.staticTexts["No Mac paired yet"].waitForExistence(timeout: 10),
            "Settings did not render the never-paired state, so the pairing entry point is "
                + "unproven. On screen: \(Self.visibleText(in: app))"
        )
        let pair = app.buttons["Pair Mac"]
        XCTAssertTrue(pair.waitForExistence(timeout: 5), "no 'Pair Mac' control on Settings")
        pair.tap()

        // No surface assertion has passed for this one yet — it is whatever tapping 'Pair Mac'
        // produced. The name says so, and the campaign files it as a moment rather than as
        // SURF-014's picture until the assertion below has run.
        capture(app, as: "UNASSERTED.ios.after-tapping-pair-mac")
        XCTAssertTrue(
            app.staticTexts["Why the camera"].waitForExistence(timeout: 10),
            "the pairing flow did not open on the camera pre-prompt"
        )
        capture(app, as: "SURF-014.ios.camera-preflight")
        XCTAssertTrue(
            app.buttons["Allow camera access"].exists,
            "the pre-prompt offered no way to allow the camera"
        )
        let typed = app.buttons["Enter the code instead"]
        XCTAssertTrue(typed.exists, "the pre-prompt offered no alternative to the camera")
        // No capture here. This asserted three things about the surface `camera-preflight` already
        // photographed and changed none of them, so a second shot was byte-identical to the first —
        // caught by the export's shared-image check, which is exactly the case it exists for: two
        // names over one picture means one of the two was never photographed. The next capture is
        // the one below, after tapping through to a surface that is genuinely different.

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
