import XCTest
@testable import Synth

final class EmailParserTests: XCTestCase {
    func testParseSimpleEmail() {
        let emlContent = """
        From: alice@example.com
        Subject: Weekly Update
        Date: Mon, 10 Jun 2024 09:00:00 -0400

        Hello team,

        Here is the weekly update.

        Best,
        Alice
        """

        let parsed = EmailParser.parse(emlContent: emlContent)

        XCTAssertEqual(parsed.sender, "alice@example.com")
        XCTAssertEqual(parsed.subject, "Weekly Update")
        XCTAssertEqual(parsed.date, "Mon, 10 Jun 2024 09:00:00 -0400")
        XCTAssertTrue(parsed.body.contains("Hello team,"))
        XCTAssertTrue(parsed.body.contains("Best,"))
    }

    func testParseMultipartEmail() {
        let emlContent = """
        From: bob@example.com
        Subject: Multipart Test
        Date: Tue, 11 Jun 2024 10:30:00 -0400
        Content-Type: multipart/alternative; boundary="boundary123"

        --boundary123
        Content-Type: text/plain; charset="utf-8"

        This is the plain text version.
        --boundary123
        Content-Type: text/html; charset="utf-8"

        <html><body><p>This is the HTML version.</p></body></html>
        --boundary123--
        """

        let parsed = EmailParser.parse(emlContent: emlContent)

        XCTAssertEqual(parsed.sender, "bob@example.com")
        XCTAssertEqual(parsed.subject, "Multipart Test")
        XCTAssertTrue(parsed.body.contains("plain text version"))
        XCTAssertFalse(parsed.body.contains("<html>"))
    }

    func testParseMissingSubject() {
        let emlContent = """
        From: carol@example.com
        Date: Wed, 12 Jun 2024 14:00:00 -0400

        Some body content here.
        """

        let parsed = EmailParser.parse(emlContent: emlContent)

        XCTAssertEqual(parsed.subject, "")
        XCTAssertEqual(parsed.sender, "carol@example.com")
        XCTAssertTrue(parsed.body.contains("Some body content"))
    }

    func testParseEmptyBody() {
        let emlContent = """
        From: dave@example.com
        Subject: No Body
        Date: Thu, 13 Jun 2024 08:00:00 -0400

        """

        let parsed = EmailParser.parse(emlContent: emlContent)

        XCTAssertEqual(parsed.subject, "No Body")
        XCTAssertEqual(parsed.sender, "dave@example.com")
        XCTAssertEqual(parsed.body, "")
    }
}
