import XCTest

/// Drives the app in the simulator: vertical paging, carousel swipe, product click-out.
final class FeedFlowUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "-use-fixtures"]
        app.launch()
    }

    func testFeedPagesAndOpensProduct() {
        let firstCaption = app.staticTexts["the perfect camel coat for fall 🍂 wearing it with my go-to loafers and straight jeans"]
        XCTAssertTrue(firstCaption.waitForExistence(timeout: 10), "first fixture post should render")

        // Carousel: swipe left inside the post and expect the same caption (still post 1).
        app.swipeLeft()
        XCTAssertTrue(firstCaption.exists)

        // Vertical paging: swipe up twice, expect a later post's caption.
        app.swipeUp()
        app.swipeUp()
        let third = app.staticTexts["The Oversized Blazer, back in camel. Layer it over everything."]
        XCTAssertTrue(third.waitForExistence(timeout: 5), "third fixture post should be active after two swipes")

        // Chips: switch to Following.
        app.buttons["Following"].tap()
        XCTAssertTrue(firstCaption.waitForExistence(timeout: 5), "following fixture starts with the camel coat post")

        // Product click-out opens SFSafariViewController (has a Done/Close button in its toolbar).
        app.staticTexts["Double-faced wool wrap coat"].firstMatch.tap()
        let safariDone = app.buttons["Done"].firstMatch
        let safariClose = app.buttons["Close"].firstMatch
        XCTAssertTrue(safariDone.waitForExistence(timeout: 10) || safariClose.waitForExistence(timeout: 2), "Safari view should open for product")
        if safariClose.exists { safariClose.tap() } else { safariDone.tap() }
        XCTAssertTrue(firstCaption.waitForExistence(timeout: 5))

        // Like toggles the heart count optimistically.
        let like = app.buttons["like-button"].firstMatch
        XCTAssertTrue(like.waitForExistence(timeout: 5))
        let before = Int(like.value as? String ?? "") ?? -1
        like.tap()
        let after = Int(like.value as? String ?? "") ?? -1
        XCTAssertEqual(after, before + 1, "like count should increment")
        XCTAssertEqual(like.label, "Unlike")
    }
}
