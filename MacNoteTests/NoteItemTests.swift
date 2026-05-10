import XCTest
@testable import MacNote

final class NoteItemTests: XCTestCase {

    func testTitleFromPlainFirstLine() {
        XCTAssertEqual(NoteItem.titleFromContent("Hello world\nSecond line"), "Hello world")
    }

    func testTitleStripsMarkdownHeading() {
        XCTAssertEqual(NoteItem.titleFromContent("# My Note\nBody"), "My Note")
        XCTAssertEqual(NoteItem.titleFromContent("## Section\nBody"), "Section")
        XCTAssertEqual(NoteItem.titleFromContent("### Deep\nBody"), "Deep")
    }

    func testTitleEmptyContentIsUntitled() {
        XCTAssertEqual(NoteItem.titleFromContent(""), "Untitled")
    }

    func testTitleWhitespaceOnlyIsUntitled() {
        XCTAssertEqual(NoteItem.titleFromContent("   \n  \n"), "Untitled")
    }

    func testTitleCappedAt80Characters() {
        let long = String(repeating: "a", count: 120)
        let title = NoteItem.titleFromContent(long)
        XCTAssertEqual(title.count, 80)
    }

    func testTitleTrimsLeadingTrailingWhitespace() {
        XCTAssertEqual(NoteItem.titleFromContent("  Hello  \nrest"), "Hello")
    }

    func testTitleUsesFirstNonEmptyLine() {
        XCTAssertEqual(NoteItem.titleFromContent("First\nSecond\nThird"), "First")
    }
}
