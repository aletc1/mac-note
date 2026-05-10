import XCTest
@testable import MacNote

final class AppStateTests: XCTestCase {

    func testEmptyDefault() {
        let s = AppState.empty
        XCTAssertNil(s.lastOpenNoteID)
        XCTAssertTrue(s.draftText.isEmpty)
        XCTAssertNil(s.windowFrame)
        XCTAssertEqual(s.cursorLocation, 0)
    }

    func testCodableRoundTripMinimal() throws {
        let state = AppState.empty
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(AppState.self, from: data)
        XCTAssertEqual(decoded.lastOpenNoteID, state.lastOpenNoteID)
        XCTAssertEqual(decoded.draftText, state.draftText)
        XCTAssertEqual(decoded.cursorLocation, state.cursorLocation)
    }

    func testCodableRoundTripFull() throws {
        let id = UUID()
        let frame = WindowFrame(CGRect(origin: CGPoint(x: 10, y: 20), size: CGSize(width: 800, height: 600)))
        var state = AppState.empty
        state.lastOpenNoteID = id
        state.draftText = "Hello draft"
        state.windowFrame = frame
        state.cursorLocation = 42

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(AppState.self, from: data)

        XCTAssertEqual(decoded.lastOpenNoteID, id)
        XCTAssertEqual(decoded.draftText, "Hello draft")
        XCTAssertEqual(decoded.cursorLocation, 42)
        XCTAssertEqual(decoded.windowFrame?.x, 10)
        XCTAssertEqual(decoded.windowFrame?.y, 20)
        XCTAssertEqual(decoded.windowFrame?.width, 800)
        XCTAssertEqual(decoded.windowFrame?.height, 600)
    }

    func testLoadReturnsEmptyWhenNoFile() {
        let state = AppState.load()
        // state.json doesn't exist in a clean env — must return .empty defaults
        XCTAssertEqual(state.cursorLocation, 0)
        XCTAssertTrue(state.draftText.isEmpty)
    }
}
