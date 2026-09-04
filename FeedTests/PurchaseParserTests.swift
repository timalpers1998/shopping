import XCTest
@testable import Feed

final class PurchaseParserTests: XCTestCase {
    private func fixture(_ name: String) throws -> MailMessage {
        let url = try XCTUnwrap(Bundle.main.url(forResource: name, withExtension: "json") ?? Bundle(for: Marker.self).url(forResource: name, withExtension: "json"))
        return try JSONDecoder.feed.decode(MailMessage.self, from: Data(contentsOf: url))
    }
    private final class Marker {}

    func testJSONLDOrder() throws {
        let o = try XCTUnwrap(PurchaseParser.parse(try fixture("email_everlane_jsonld")))
        XCTAssertEqual(o.extraction, .jsonld)
        XCTAssertEqual(o.merchant, "everlane.com")
        XCTAssertEqual(o.items.count, 2)
        XCTAssertEqual(o.items[0].title, "The Organic Cotton Box-Cut Tee")
        XCTAssertEqual(o.items[0].priceCents, 3500)
        XCTAssertEqual(o.items[0].brand, "Everlane")
        XCTAssertEqual(o.items[1].priceCents, 11800)
        XCTAssertNotNil(o.items[1].imageUrl)
        XCTAssertEqual(o.items[1].category, "fashion")
        XCTAssertEqual(o.orderTotalCents, 15300)
    }

    func testParcelDelivery() throws {
        let o = try XCTUnwrap(PurchaseParser.parse(try fixture("email_nordstrom_parceldelivery")))
        XCTAssertEqual(o.orderKind, .shipped)
        XCTAssertEqual(o.items.first?.title, "Toteme Signature Wool Cashmere Coat")
        XCTAssertEqual(o.items.first?.brand, "Toteme", "brand should come from the title prefix for marketplace senders")
        XCTAssertEqual(o.items.first?.category, "fashion")
    }

    func testAmazonSubjectOnly() throws {
        let o = try XCTUnwrap(PurchaseParser.parse(try fixture("email_amazon_shipped")))
        XCTAssertEqual(o.extraction, .heuristic)
        XCTAssertEqual(o.items.first?.title, "Levi\'s Men\'s 501 Original Fit Jeans, Medium Stonewash, 32W x 32L")
        XCTAssertEqual(o.items.first?.brand, "Levi\'s")
        XCTAssertEqual(o.orderTotalCents, 5950)
        XCTAssertEqual(o.items.first?.imageUrl, "https://images-na.ssl-images-amazon.com/images/P/B0000ABCDE.jpg", "tracking pixel must be skipped")
        XCTAssertEqual(o.items.first?.productUrl, "https://www.amazon.com/dp/B0000ABCDE")
    }

    func testHTMLTableWithQuantities() throws {
        let o = try XCTUnwrap(PurchaseParser.parse(try fixture("email_aritzia_table")))
        XCTAssertEqual(o.items.count, 2)
        XCTAssertEqual(o.items[0].title, "The Oversized Wool Blazer")
        XCTAssertEqual(o.items[0].priceCents, 22800)
        XCTAssertEqual(o.items[1].quantity, 2)
        XCTAssertEqual(o.items[1].brand, "Aritzia")
        XCTAssertEqual(o.orderTotalCents, 35235)
        XCTAssertEqual(o.items[0].imageUrl, "https://loremflickr.com/600/800/blazer?lock=5")
        XCTAssertTrue(o.items[0].productUrl?.contains("oversized-wool-blazer") ?? false)
    }

    func testPlainTextReceipt() throws {
        let o = try XCTUnwrap(PurchaseParser.parse(try fixture("email_lululemon_text")))
        XCTAssertEqual(o.items.map(\.title), ["Align High-Rise Pant 25\"", "Scuba Oversized Half-Zip"])
        XCTAssertEqual(o.items.map(\.priceCents), [9800, 11800])
        XCTAssertEqual(o.orderTotalCents, 23490)
    }

    /// Fashion-only: a beauty order still parses, but its items carry no category,
    /// so the review screen leaves them off and they never reach the taste vector.
    func testNonFashionItemsHaveNoCategory() throws {
        let o = try XCTUnwrap(PurchaseParser.parse(try fixture("email_sephora_beauty")))
        XCTAssertEqual(o.items.count, 2)
        XCTAssertNil(o.items[0].category)
        XCTAssertEqual(o.items[1].brand, "Glossier")
    }

    func testNegatives() throws {
        XCTAssertNil(PurchaseParser.parse(try fixture("email_newsletter_negative")))
        XCTAssertNil(PurchaseParser.parse(try fixture("email_return_negative")))
    }

    func testDivBasedReceipt() throws {
        let o = try XCTUnwrap(PurchaseParser.parse(try fixture("email_jcrew_outlook_shape")))
        XCTAssertEqual(o.items.map(\.title), ["Cable-Knit Cardigan Sweater", "Slim-Fit Chino Pant"])
        XCTAssertEqual(o.items.map(\.category), ["fashion", "fashion"])
    }

    func testDedupeConfirmationAndShipped() throws {
        let a = try XCTUnwrap(PurchaseParser.parse(try fixture("email_aritzia_table")))
        var shipped = a
        shipped = ParsedOrder(id: "x", fingerprint: "y", merchant: a.merchant, merchantBrand: a.merchantBrand, orderKind: .shipped, purchasedAt: a.purchasedAt.addingTimeInterval(86400 * 3),
                              orderTotalCents: nil, currency: "USD", items: a.items.map { var i = $0; i.priceCents = nil; return i }, extraction: .heuristic, confidence: 0.5)
        let merged = PurchaseParser.dedupe([a, shipped])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].items[0].priceCents, 22800, "the priced confirmation wins")
    }
}
