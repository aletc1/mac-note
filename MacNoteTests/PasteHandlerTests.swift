import XCTest
@testable import MacNote

final class PasteHandlerTests: XCTestCase {
    func testRTFToMarkdownBold() {
        let attrStr = NSMutableAttributedString(string: "Hello world")
        attrStr.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: 14), range: NSRange(location: 0, length: 5))
        let md = RTFToMarkdown.convert(attrStr)
        XCTAssertTrue(md.contains("**Hello**"), "Bold text should be wrapped in **")
    }

    func testRTFToMarkdownLink() {
        let attrStr = NSMutableAttributedString(string: "Click here")
        let url = URL(string: "https://example.com")!
        attrStr.addAttribute(.link, value: url, range: NSRange(location: 0, length: 10))
        let md = RTFToMarkdown.convert(attrStr)
        XCTAssertTrue(md.contains("[Click here](https://example.com)"), "Links should become markdown links")
    }

    func testRTFToMarkdownPlainText() {
        let attrStr = NSAttributedString(string: "plain text")
        let md = RTFToMarkdown.convert(attrStr)
        XCTAssertEqual(md, "plain text")
    }

    func testRTFToMarkdownItalic() {
        let attrStr = NSMutableAttributedString(string: "hello world")
        let italicFont = NSFontManager.shared.font(
            withFamily: NSFont.systemFont(ofSize: 14).familyName ?? "Helvetica",
            traits: .italicFontMask,
            weight: 5,
            size: 14
        ) ?? NSFont.systemFont(ofSize: 14)
        attrStr.addAttribute(.font, value: italicFont, range: NSRange(location: 0, length: 5))
        let md = RTFToMarkdown.convert(attrStr)
        XCTAssertTrue(md.contains("_hello_"), "Italic text should be wrapped in _")
    }

    func testLinkURLWithClosingParenIsEncoded() {
        let attrStr = NSMutableAttributedString(string: "file")
        let url = URL(string: "https://example.com/file(1).pdf")!
        attrStr.addAttribute(.link, value: url, range: NSRange(location: 0, length: 4))
        let md = RTFToMarkdown.convert(attrStr)
        XCTAssertTrue(md.contains("%29"), "Closing paren in URL must be percent-encoded to avoid breaking the markdown link")
    }

    func testLinkTextWithClosingBracketIsEscaped() {
        let attrStr = NSMutableAttributedString(string: "[legacy]")
        let url = URL(string: "https://example.com")!
        attrStr.addAttribute(.link, value: url, range: NSRange(location: 0, length: 8))
        let md = RTFToMarkdown.convert(attrStr)
        XCTAssertTrue(md.contains("\\]"), "Closing bracket in link text must be escaped")
    }

    func testRTFToMarkdownEmptyString() {
        let attrStr = NSAttributedString(string: "")
        let md = RTFToMarkdown.convert(attrStr)
        XCTAssertEqual(md, "")
    }

    func testRTFToMarkdownMultipleRuns() {
        let attrStr = NSMutableAttributedString(string: "bold normal")
        attrStr.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: 14),
                              range: NSRange(location: 0, length: 4))
        let md = RTFToMarkdown.convert(attrStr)
        XCTAssertTrue(md.contains("**bold**"))
        XCTAssertTrue(md.contains("normal"))
    }
}
