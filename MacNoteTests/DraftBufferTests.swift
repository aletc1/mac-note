import XCTest
@testable import MacNote

final class DraftBufferTests: XCTestCase {

    func testDefaultStateIsActiveAndEmpty() {
        let buf = DraftBuffer()
        XCTAssertTrue(buf.isActive)
        XCTAssertTrue(buf.text.isEmpty)
    }

    func testPromoteDeactivatesBuffer() {
        let buf = DraftBuffer()
        buf.text = "Hello"
        buf.promote(to: UUID())
        XCTAssertFalse(buf.isActive)
        XCTAssertEqual(buf.text, "Hello")
    }

    func testClearResetsToActiveEmpty() {
        let buf = DraftBuffer()
        buf.text = "Draft text"
        buf.promote(to: UUID())
        buf.clear()
        XCTAssertTrue(buf.isActive)
        XCTAssertTrue(buf.text.isEmpty)
    }

    func testSnapshotReturnsCurrentText() {
        let buf = DraftBuffer()
        buf.text = "some content"
        XCTAssertEqual(buf.snapshot, "some content")
    }
}
