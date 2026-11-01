import Foundation
import XCTest

final class PhoneTabIdentifierTests: XCTestCase {
    private static let destinations = [
        (id: "tab-discover", title: "Discover"),
        (id: "tab-triage", title: "Triage"),
        (id: "tab-queue", title: "Queue"),
        (id: "tab-library", title: "Library"),
        (id: "tab-settings", title: "Settings")
    ]

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testIdentifiersLabelsAndDestinationsSurviveRevisitsAndRelaunch() {
        let app = XCUIApplication()
        app.launchEnvironment["MCPROUTER_SCENARIO"] = "populated"
        app.launch()
        defer { app.terminate() }
        assertTabInventory(app)
        visitEveryDestination(app, capturing: true)
        assertTabInventory(app)
        visitEveryDestination(app, capturing: false)
        app.terminate()
        app.launch()
        assertTabInventory(app)
        visitEveryDestination(app, capturing: false)
        assertTabInventory(app)
    }

    private func assertTabInventory(_ app: XCUIApplication) {
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 20))
        let buttons = tabBar.buttons.allElementsBoundByIndex
        XCTAssertEqual(buttons.count, 5)
        // swiftformat:disable:next preferKeyPath
        let identifiers = buttons.map { $0.identifier }
        // swiftformat:disable:next preferKeyPath
        let labels = buttons.map { $0.label }
        FileHandle.standardError.write(Data("TAB-IDENTITY ids=\(identifiers) labels=\(labels)\n".utf8))
        XCTAssertEqual(identifiers, Self.destinations.map(\.id))
        XCTAssertEqual(Set(identifiers).count, 5)
        XCTAssertEqual(labels, Self.destinations.map(\.title))
    }

    private func visitEveryDestination(_ app: XCUIApplication, capturing: Bool) {
        for destination in Self.destinations {
            let predecessor = destination.id == "tab-settings"
                ? (id: "tab-discover", title: "Discover")
                : (id: "tab-settings", title: "Settings")
            navigate(app, id: predecessor.id, title: predecessor.title)
            XCTAssertFalse(
                app.navigationBars[destination.title].exists,
                "the target is already visible, so a tap could prove nothing"
            )
            navigate(app, id: destination.id, title: destination.title)
            if capturing {
                let shot = XCTAttachment(screenshot: app.screenshot())
                shot.name = "TAB-IDENTITY-\(destination.id)"
                shot.lifetime = .keepAlways
                add(shot)
            }
        }
    }

    private func navigate(_ app: XCUIApplication, id: String, title: String) {
        let query = app.tabBars.buttons.matching(NSPredicate(format: "identifier == %@", id))
        let button = query.firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        XCTAssertEqual(query.count, 1, "an exact identifier must name one tab")
        XCTAssertEqual(button.label, title)
        let hittable = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == true"),
            object: button
        )
        XCTAssertEqual(XCTWaiter().wait(for: [hittable], timeout: 10), .completed)
        button.tap()
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 10))
        FileHandle.standardError.write(Data("TAB-TRANSITION id=\(id) destination=\(title)\n".utf8))
    }
}
