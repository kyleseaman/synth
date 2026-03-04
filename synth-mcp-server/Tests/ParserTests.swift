import XCTest
@testable import SynthMCPLib

final class FrontmatterParserTests: XCTestCase {
    func testParseValidFrontmatter() {
        let content = "---\ntitle: Hello\ntags:\n  - swift\n  - rust\n---\nBody text"
        let result = FrontmatterParser.parse(content)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.fields["title"]?.stringValue, "Hello")
        XCTAssertEqual(result?.fields["tags"]?.listValue, ["swift", "rust"])
        XCTAssertEqual(result?.body, "Body text")
    }

    func testParseReturnsNilWithoutFrontmatter() {
        XCTAssertNil(FrontmatterParser.parse("No frontmatter here"))
        XCTAssertNil(FrontmatterParser.parse(""))
    }

    func testParseInlineArray() {
        let content = "---\ntags: [alpha, beta, gamma]\n---\n"
        let result = FrontmatterParser.parse(content)
        XCTAssertEqual(result?.fields["tags"]?.listValue, ["alpha", "beta", "gamma"])
    }

    func testParseEmptyInlineArray() {
        let content = "---\ntags: []\n---\n"
        let result = FrontmatterParser.parse(content)
        XCTAssertEqual(result?.fields["tags"]?.listValue, [])
    }

    func testParseQuotedStrings() {
        let content = "---\ntitle: \"Hello World\"\nauthor: 'Jane'\n---\n"
        let result = FrontmatterParser.parse(content)
        XCTAssertEqual(result?.fields["title"]?.stringValue, "Hello World")
        XCTAssertEqual(result?.fields["author"]?.stringValue, "Jane")
    }

    func testReconstructPreservesFieldOrder() {
        let fields: [String: FrontmatterParser.FrontmatterValue] = [
            "title": .scalar("Test"),
            "tags": .list(["one", "two"])
        ]
        let result = FrontmatterParser.reconstruct(
            fields: fields, body: "\nContent", fieldOrder: ["title", "tags"]
        )
        XCTAssertTrue(result.hasPrefix("---\ntitle: Test\ntags:\n  - one\n  - two\n---\n"))
        XCTAssertTrue(result.hasSuffix("\nContent"))
    }

    func testReconstructEmptyList() {
        let fields: [String: FrontmatterParser.FrontmatterValue] = [
            "tags": .list([])
        ]
        let result = FrontmatterParser.reconstruct(fields: fields, body: "\n")
        XCTAssertTrue(result.contains("tags: []"))
    }

    func testTagsExtraction() {
        let content = "---\ntags:\n  - swift\n  - rust\n---\nBody"
        guard let frontmatter = FrontmatterParser.parse(content) else {
            XCTFail("Expected valid frontmatter")
            return
        }
        XCTAssertEqual(FrontmatterParser.tags(from: frontmatter), ["swift", "rust"])
    }

    func testTagsFromScalar() {
        let content = "---\ntags: single-tag\n---\n"
        guard let frontmatter = FrontmatterParser.parse(content) else {
            XCTFail("Expected valid frontmatter")
            return
        }
        XCTAssertEqual(FrontmatterParser.tags(from: frontmatter), ["single-tag"])
    }

    func testAddTagCreatesNewFrontmatter() {
        let result = FrontmatterParser.addTag("swift", to: "Hello world")
        XCTAssertTrue(result.contains("tags:"))
        XCTAssertTrue(result.contains("- swift"))
        XCTAssertTrue(result.contains("Hello world"))
    }

    func testAddTagToExistingFrontmatter() {
        let content = "---\ntags:\n  - rust\n---\nBody"
        let result = FrontmatterParser.addTag("swift", to: content)
        XCTAssertTrue(result.contains("- rust"))
        XCTAssertTrue(result.contains("- swift"))
    }

    func testAddTagSkipsDuplicate() {
        let content = "---\ntags:\n  - swift\n---\nBody"
        let result = FrontmatterParser.addTag("swift", to: content)
        XCTAssertEqual(result, content)
    }

    func testRemoveTag() {
        let content = "---\ntags:\n  - swift\n  - rust\n---\nBody"
        let (result, removed) = FrontmatterParser.removeTag("swift", fromFrontmatter: content)
        XCTAssertTrue(removed)
        XCTAssertFalse(result.contains("- swift"))
        XCTAssertTrue(result.contains("- rust"))
    }

    func testRemoveTagNotFound() {
        let content = "---\ntags:\n  - swift\n---\nBody"
        let (result, removed) = FrontmatterParser.removeTag("missing", fromFrontmatter: content)
        XCTAssertFalse(removed)
        XCTAssertEqual(result, content)
    }

    func testRemoveTagNoFrontmatter() {
        let content = "No frontmatter"
        let (result, removed) = FrontmatterParser.removeTag("tag", fromFrontmatter: content)
        XCTAssertFalse(removed)
        XCTAssertEqual(result, content)
    }
}

final class HTTPRequestParserTests: XCTestCase {
    func testParseValidGetRequest() {
        let raw = "GET /health HTTP/1.1\r\nHost: localhost\r\n\r\n"
        let request = HTTPRequest.parse(raw)
        XCTAssertNotNil(request)
        XCTAssertEqual(request?.method, "GET")
        XCTAssertEqual(request?.path, "/health")
        XCTAssertEqual(request?.httpVersion, "HTTP/1.1")
    }

    func testParsePostWithBody() {
        let body = "{\"key\":\"value\"}"
        let raw = "POST /api HTTP/1.1\r\nContent-Length: \(body.count)\r\n\r\n\(body)"
        let request = HTTPRequest.parse(raw)
        XCTAssertNotNil(request)
        XCTAssertEqual(request?.method, "POST")
        let bodyString = request?.body.flatMap { String(data: $0, encoding: .utf8) }
        XCTAssertEqual(bodyString, body)
    }

    func testParseFromData() {
        let raw = "GET / HTTP/1.1\r\n\r\n"
        let request = HTTPRequest.parse(Data(raw.utf8))
        XCTAssertNotNil(request)
        XCTAssertEqual(request?.method, "GET")
    }

    func testParseReturnsNilForInvalidInput() {
        XCTAssertNil(HTTPRequest.parse(""))
        XCTAssertNil(HTTPRequest.parse(Data()))
    }

    func testHeaderCaseInsensitivity() {
        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: "application/json")
        XCTAssertEqual(headers.first(name: "content-type"), "application/json")
        XCTAssertEqual(headers["CONTENT-TYPE"], "application/json")
    }

    func testHeaderMultipleValues() {
        var headers = HTTPHeaders()
        headers.add(name: "Accept", value: "text/html")
        headers.add(name: "Accept", value: "application/json")
        XCTAssertEqual(headers.all(name: "accept").count, 2)
        XCTAssertEqual(headers.first(name: "accept"), "text/html")
    }

    func testContentLengthLimitsBody() {
        let body = "short"
        let extra = "extra data that should be ignored"
        let raw = "POST / HTTP/1.1\r\nContent-Length: \(body.count)\r\n\r\n\(body)\(extra)"
        let request = HTTPRequest.parse(raw)
        let bodyString = request?.body.flatMap { String(data: $0, encoding: .utf8) }
        XCTAssertEqual(bodyString, body)
    }
}
