import XCTest
@testable import Feed

final class SmokeTests: XCTestCase {
    func testTabsExist() {
        XCTAssertNotEqual(AppTab.feed, AppTab.profile)
    }
}
