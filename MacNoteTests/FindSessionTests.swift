import XCTest
@testable import MacNote

final class FindSessionTests: XCTestCase {

    // MARK: - FindSession.matches(in:query:) — pure, no text view required

    func testEmptyQueryReturnsNoMatches() {
        XCTAssertEqual(FindSession.matches(in: "hello world", query: ""), [])
    }

    func testNoMatchReturnsEmpty() {
        XCTAssertEqual(FindSession.matches(in: "hello world", query: "xyz"), [])
    }

    func testSingleMatch() {
        let ranges = FindSession.matches(in: "hello world", query: "world")
        XCTAssertEqual(ranges, [NSRange(location: 6, length: 5)])
    }

    func testMultipleNonOverlappingMatches() {
        let ranges = FindSession.matches(in: "cat sat on the cat mat", query: "cat")
        XCTAssertEqual(ranges, [
            NSRange(location: 0, length: 3),
            NSRange(location: 15, length: 3),
        ])
    }

    func testAdjacentMatchesDoNotOverlap() {
        // "aa" inside "aaaa" should find two non-overlapping matches, not three.
        let ranges = FindSession.matches(in: "aaaa", query: "aa")
        XCTAssertEqual(ranges, [
            NSRange(location: 0, length: 2),
            NSRange(location: 2, length: 2),
        ])
    }

    func testCaseInsensitive() {
        let ranges = FindSession.matches(in: "Hello HELLO hello", query: "hello")
        XCTAssertEqual(ranges.count, 3)
    }

    func testMatchAtEndOfString() {
        let ranges = FindSession.matches(in: "the end", query: "end")
        XCTAssertEqual(ranges, [NSRange(location: 4, length: 3)])
    }

    func testUnicodeQuery() {
        let ranges = FindSession.matches(in: "café au café", query: "café")
        XCTAssertEqual(ranges.count, 2)
    }

    // MARK: - Session state

    func testMatchCountTextIsNilWithoutQuery() {
        let session = FindSession()
        XCTAssertNil(session.matchCountText)
    }

    func testClearResetsQueryAndMatches() {
        let session = FindSession()
        session.query = "something"
        session.clear()
        XCTAssertEqual(session.query, "")
        XCTAssertTrue(session.matches.isEmpty)
    }

    func testNoteContentDidChangeIsNoOpWithoutActiveQuery() {
        // Guards against scheduling a refresh (and touching a nil text view)
        // on every keystroke when no find is in progress.
        let session = FindSession()
        session.noteContentDidChange() // should not crash with no query and no textView
    }

    func testNextAndPreviousAreNoOpsWithoutMatches() {
        let session = FindSession()
        session.next()
        session.previous()
        XCTAssertEqual(session.currentIndex, 0)
    }
}
