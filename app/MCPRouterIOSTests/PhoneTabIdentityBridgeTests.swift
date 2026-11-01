import UIKit
import XCTest
@testable import MCPRouterUI

@MainActor
final class PhoneTabIdentityBridgeTests: XCTestCase {
    private let titles = ["Discover", "Triage", "Queue", "Library", "Settings"]
    private let identifiers = ["tab-discover", "tab-triage", "tab-queue", "tab-library", "tab-settings"]

    func testChangesOnlyIdentifiersOnItsOwnEnclosingController() throws {
        let own = controller()
        let other = controller()
        own.selectedIndex = 2
        own.tabBar.tintColor = .magenta
        own.tabBar.items?.first?.badgeValue = "fixture"
        let beforeOther = itemIdentifiers(other)
        let bridge = try attach(to: own)
        bridge.applyIdentifiers()
        XCTAssertEqual(itemIdentifiers(own), identifiers.map(Optional.some))
        XCTAssertEqual(itemIdentifiers(other), beforeOther)
        XCTAssertEqual(own.selectedIndex, 2)
        XCTAssertEqual(own.tabBar.tintColor, .magenta)
        XCTAssertEqual(own.tabBar.items?.first?.badgeValue, "fixture")
        own.tabBar.items?.first?.accessibilityIdentifier = "replaced-by-framework"
        bridge.viewDidLayoutSubviews()
        XCTAssertEqual(own.tabBar.items?.first?.accessibilityIdentifier, "tab-discover")
    }

    func testWrongTitlesOrCountLeaveEveryItemUntouched() throws {
        let wrongTitles = controller()
        wrongTitles.tabBar.items?[2].title = "Not Queue"
        let beforeTitles = itemIdentifiers(wrongTitles)
        try attach(to: wrongTitles).applyIdentifiers()
        XCTAssertEqual(itemIdentifiers(wrongTitles), beforeTitles)
        let wrongCount = controller(count: 4)
        let beforeCount = itemIdentifiers(wrongCount)
        try attach(to: wrongCount).applyIdentifiers()
        XCTAssertEqual(itemIdentifiers(wrongCount), beforeCount)
    }

    private func controller(count: Int = 5) -> UITabBarController {
        let controller = UITabBarController()
        controller.viewControllers = (0 ..< count).map { index in
            let child = UIViewController()
            child.tabBarItem = UITabBarItem(title: titles[index], image: nil, selectedImage: nil)
            child.tabBarItem.accessibilityIdentifier = "untouched-\(index)"
            return child
        }
        controller.loadViewIfNeeded()
        return controller
    }

    private func itemIdentifiers(_ controller: UITabBarController) -> [String?]? {
        // swiftformat:disable:next preferKeyPath
        controller.tabBar.items?.map { $0.accessibilityIdentifier }
    }

    @discardableResult
    private func attach(to controller: UITabBarController) throws -> PhoneTabIdentityBridge.Controller {
        let bridge = PhoneTabIdentityBridge.Controller(titles: titles, identifiers: identifiers)
        let child = try XCTUnwrap(controller.viewControllers?.first)
        child.addChild(bridge)
        child.view.addSubview(bridge.view)
        bridge.didMove(toParent: child)
        return bridge
    }
}
