import XCTest

/// Drives the app in the simulator: vertical paging, carousel swipe, product click-out.
final class FeedFlowUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "-use-fixtures", "-skip-onboarding"]
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

        // Video post (4th) should show the player; snapshot for review.
        app.swipeUp()
        XCTAssertTrue(app.otherElements["video-player"].firstMatch.waitForExistence(timeout: 8), "video post should render the player")
        sleep(8)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/video-post.png"))

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

final class ProfileFlowUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "-use-fixtures", "-skip-onboarding"]
        app.launch()
    }

    func testAuthorProfileAndPager() {
        let handle = app.staticTexts["mia.styles"].firstMatch
        XCTAssertTrue(handle.waitForExistence(timeout: 10))
        handle.tap()
        XCTAssertTrue(app.staticTexts["Followers"].waitForExistence(timeout: 5), "profile header should show")
        let data = XCUIScreen.main.screenshot().pngRepresentation
        try? data.write(to: URL(fileURLWithPath: ProcessInfo.processInfo.environment["SNAP_DIR"] ?? "/tmp").appendingPathComponent("author-profile.png"))
        let follow = app.buttons["follow-button"].firstMatch
        XCTAssertTrue(follow.exists)
        follow.tap()
        XCTAssertEqual(follow.label, "Following")
        // Tap the first grid cell → pager opens on that post.
        let cell = app.images.firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 5))
        app.buttons["back-button"].firstMatch.exists ? () : ()
        app.swipeUp() // ensure grid is visible
        let grid = app.otherElements.containing(.staticText, identifier: "Followers").firstMatch
        _ = grid
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.17, dy: 0.62)).tap()
        XCTAssertTrue(app.buttons["like-button"].firstMatch.waitForExistence(timeout: 5), "pager should show a post with the action rail")
        app.buttons["back-button"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Followers"].waitForExistence(timeout: 5))
    }

    func testOwnProfileTabAndSettings() {
        app.tabBars.buttons["Profile"].tap()
        XCTAssertTrue(app.staticTexts["Guest"].waitForExistence(timeout: 5))
        snap("own-profile")
        XCTAssertTrue(app.buttons["profile-sign-in"].exists)
        app.buttons["profile-sign-in"].tap()
        XCTAssertTrue(app.textFields["auth-email"].waitForExistence(timeout: 5))
        snap("auth-sheet")
        app.buttons["auth-close"].firstMatch.tap()
        let settings = app.buttons["profile-settings"].firstMatch
        let hittable = NSPredicate(format: "isHittable == true")
        let exp = XCTNSPredicateExpectation(predicate: hittable, object: settings)
        XCTAssertEqual(XCTWaiter().wait(for: [exp], timeout: 8), .completed, "sheet should dismiss and reveal the settings button")
        settings.tap()
        snap("after-settings-tap")
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] 'Fixtures'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "settings should show the data source row")
        snap("settings")
    }

    /// Writes a PNG to the shared scratch directory so screenshots can be reviewed outside Xcode.
    private func snap(_ name: String) {
        let dir = ProcessInfo.processInfo.environment["SNAP_DIR"] ?? "/tmp"
        let data = XCUIScreen.main.screenshot().pngRepresentation
        try? data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }
}


final class CommentsUITests: XCTestCase {
    func testCommentSheetOptimisticInsert() {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "-use-fixtures", "-skip-onboarding"]
        app.launch()
        let comments = app.buttons["comments-button"].firstMatch
        XCTAssertTrue(comments.waitForExistence(timeout: 10))
        let before = Int(comments.value as? String ?? "") ?? -1
        comments.tap()
        let field = app.textFields["comment-field"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["need this immediately 😭"].waitForExistence(timeout: 5))
        field.tap()
        if !app.keyboards.firstMatch.waitForExistence(timeout: 3) { field.tap() }
        field.typeText("where is the coat from?")
        app.buttons["comment-send"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["where is the coat from?"].waitForExistence(timeout: 5))
        let data = XCUIScreen.main.screenshot().pngRepresentation
        try? data.write(to: URL(fileURLWithPath: "/tmp/comments.png"))
        app.swipeDown(velocity: .fast)
        XCTAssertTrue(comments.waitForExistence(timeout: 5))
        XCTAssertEqual(Int(comments.value as? String ?? "") ?? -1, before + 1, "comment count on the cell should increment")
    }
}


final class ComposeUITests: XCTestCase {
    func testComposeEditAndPublishWithSeededDraft() {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "-use-fixtures", "-skip-onboarding", "-seed-compose"]
        app.launch()
        XCTAssertTrue(app.staticTexts["mia.styles"].firstMatch.waitForExistence(timeout: 10))
        app.tabBars.buttons.element(boundBy: 2).tap()
        let caption = app.textViews["compose-caption"].firstMatch.exists ? app.textViews["compose-caption"].firstMatch : app.textFields["compose-caption"].firstMatch
        XCTAssertTrue(caption.waitForExistence(timeout: 8), "seeded draft should open the edit step")
        caption.tap()
        caption.typeText("test fit from the simulator")
        let urlField = app.textFields["compose-product-url"].firstMatch
        urlField.tap()
        urlField.typeText("https://www.everlane.com/products/box-cut-tee")
        app.buttons["compose-add-product"].firstMatch.tap()
        XCTAssertTrue(app.textFields["product-title"].firstMatch.waitForExistence(timeout: 8), "scraped product card should appear")
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/compose-edit.png"))
        let post = app.buttons["compose-post"].firstMatch
        XCTAssertTrue(post.isEnabled)
        post.tap()
        // Publishing dismisses the composer; the new post lands at the top of For You (fixtures mode).
        XCTAssertTrue(app.staticTexts["test fit from the simulator"].firstMatch.waitForExistence(timeout: 15))
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/compose-published.png"))
    }
}


final class OnboardingUITests: XCTestCase {
    func testConversationSkipsInbox() {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "-use-fixtures", "-force-onboarding"]
        app.launch()
        let name = app.textFields["onboarding-name"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 10), "conversation should ask for a name")
        name.tap()
        if !app.keyboards.firstMatch.waitForExistence(timeout: 3) { name.tap() }
        name.typeText("Tim")
        app.buttons["onboarding-name-send"].firstMatch.tap()
        XCTAssertTrue(app.buttons["audience-womens"].waitForExistence(timeout: 8))
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/onb-1.png"))
        app.buttons["audience-womens"].tap()
        XCTAssertTrue(app.buttons["band-premium"].waitForExistence(timeout: 8))
        app.buttons["band-premium"].tap()
        XCTAssertTrue(app.buttons["style-minimalist"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["quiz-continue"].exists, "continue only appears once 3 styles are picked")
        app.buttons["style-minimalist"].tap(); app.buttons["style-old_money"].tap(); app.buttons["style-scandi"].tap()
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/onb-2.png"))
        let cont = app.buttons["quiz-continue"].firstMatch
        XCTAssertTrue(cont.waitForExistence(timeout: 3)); cont.tap()
        XCTAssertTrue(app.buttons["brand-Toteme"].waitForExistence(timeout: 8))
        app.buttons["brand-Toteme"].tap()
        app.buttons["brands-continue"].firstMatch.tap()
        let skip = app.buttons["import-skip"].firstMatch
        XCTAssertTrue(skip.waitForExistence(timeout: 10), "inbox step should follow the brands")
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/onb-3.png"))
        skip.tap()
        let finish = app.buttons["onboarding-finish"].firstMatch
        XCTAssertTrue(finish.waitForExistence(timeout: 10), "taste card + finish should appear")
        XCTAssertTrue(app.otherElements["taste-profile-card"].firstMatch.exists || app.staticTexts["Tim's taste"].exists)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/onb-4.png"))
        finish.tap()
        XCTAssertTrue(app.staticTexts["mia.styles"].firstMatch.waitForExistence(timeout: 10), "feed shows after onboarding")
    }
}

final class PurchaseImportUITests: XCTestCase {
    func testConversationImportsInboxAndSettingsDelete() {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "-use-fixtures", "-force-onboarding"]
        app.launch()
        let name = app.textFields["onboarding-name"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        name.tap()
        if !app.keyboards.firstMatch.waitForExistence(timeout: 3) { name.tap() }
        name.typeText("Tim"); app.buttons["onboarding-name-send"].firstMatch.tap()
        XCTAssertTrue(app.buttons["audience-womens"].waitForExistence(timeout: 8)); app.buttons["audience-womens"].tap()
        XCTAssertTrue(app.buttons["band-mid"].waitForExistence(timeout: 8)); app.buttons["band-mid"].tap()
        XCTAssertTrue(app.buttons["style-minimalist"].waitForExistence(timeout: 8))
        app.buttons["style-minimalist"].tap(); app.buttons["style-old_money"].tap(); app.buttons["style-scandi"].tap()
        let cont = app.buttons["quiz-continue"].firstMatch; XCTAssertTrue(cont.waitForExistence(timeout: 3)); cont.tap()
        XCTAssertTrue(app.buttons["brands-continue"].waitForExistence(timeout: 8)); app.buttons["brands-continue"].firstMatch.tap()
        let connect = app.buttons["import-connect-fixture"].firstMatch
        XCTAssertTrue(connect.waitForExistence(timeout: 10)); connect.tap()
        let apply = app.buttons["import-apply"].firstMatch
        XCTAssertTrue(apply.waitForExistence(timeout: 40), "review card should appear inline after scanning")
        XCTAssertTrue(app.switches["import-brand-Everlane"].firstMatch.exists)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/onb-review.png"))
        app.switches["import-brand-Aritzia"].firstMatch.tap()
        apply.tap()
        let finish = app.buttons["onboarding-finish"].firstMatch
        XCTAssertTrue(finish.waitForExistence(timeout: 15))
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/onb-profile.png"))
        finish.tap()
        XCTAssertTrue(app.staticTexts["mia.styles"].firstMatch.waitForExistence(timeout: 15))
        app.tabBars.buttons["Profile"].tap()
        let settings = app.buttons["profile-settings"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 5)); settings.tap()
        let row = app.buttons["settings-imported-purchases"].firstMatch.exists ? app.buttons["settings-imported-purchases"].firstMatch : app.staticTexts["Imported purchases"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        let del = app.buttons["import-delete"].firstMatch
        XCTAssertTrue(del.waitForExistence(timeout: 8)); del.tap()
        app.buttons["Delete"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Not connected"].waitForExistence(timeout: 8))
    }
}

final class DiscoverUITests: XCTestCase {
    func testTrendingAndSearch() {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "-use-fixtures", "-skip-onboarding"]
        app.launch()
        XCTAssertTrue(app.staticTexts["mia.styles"].firstMatch.waitForExistence(timeout: 10))
        app.tabBars.buttons["Discover"].tap()
        XCTAssertTrue(app.staticTexts["Trending products"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["trending-Double-faced wool wrap coat"].firstMatch.waitForExistence(timeout: 8))
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/discover.png"))
        let field = app.textFields["discover-search"].firstMatch
        field.tap()
        field.typeText("cargo")
        XCTAssertTrue(app.staticTexts["2 posts"].waitForExistence(timeout: 8), "two fixture posts mention cargo")
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/discover-search.png"))
    }
}
