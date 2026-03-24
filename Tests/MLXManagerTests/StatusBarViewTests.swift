import AppKit
import XCTest
@testable import MLXManagerApp

@MainActor
final class StatusBarViewTests: XCTestCase {

    func test_statusBarView_placesArcIconAtTrailingEdge() {
        let subject = StatusBarView()

        guard
            let statusItem = reflectedValue(named: "statusItem", in: subject, as: NSStatusItem.self),
            let arcView = reflectedValue(named: "arcView", in: subject, as: NSView.self),
            let button = statusItem.button
        else {
            XCTFail("Expected StatusBarView internals to be available for layout verification")
            return
        }

        let hasTrailingConstraint = button.constraints.contains { constraint in
            constraint.firstAttribute == .trailing &&
                constraint.secondAttribute == .trailing &&
                (constraint.firstItem as AnyObject?) === arcView &&
                (constraint.secondItem as AnyObject?) === button &&
                abs(constraint.constant + 4) < 0.001
        }

        XCTAssertTrue(hasTrailingConstraint, "Expected the arc icon to be anchored to the trailing edge of the status item")
    }

    private func reflectedValue<T>(named label: String, in subject: Any, as type: T.Type) -> T? {
        Mirror(reflecting: subject).descendant(label) as? T
    }
}
