import XCTest
@testable import MacNote

final class RecoveryJournalTests: XCTestCase {
    var tmpDir: URL!
    var journal: RecoveryJournal!

    override func setUpWithError() throws {
        tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        journal = RecoveryJournal(recoveryDirectory: tmpDir)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    func testAppendAndReplay() throws {
        let noteID = UUID()
        let entry = RecoveryJournal.Entry(range: NSRange(location: 0, length: 0), replacement: "Hello", timestamp: Date())
        try journal.append(entry: entry, for: noteID)
        let replayed = try journal.replay(for: noteID)
        XCTAssertEqual(replayed.count, 1)
        XCTAssertEqual(replayed[0].replacement, "Hello")
    }

    func testTruncateClearsEntries() throws {
        let noteID = UUID()
        let entry = RecoveryJournal.Entry(range: NSRange(location: 0, length: 0), replacement: "Hello", timestamp: Date())
        try journal.append(entry: entry, for: noteID)
        try journal.truncate(for: noteID)
        let replayed = try journal.replay(for: noteID)
        XCTAssertTrue(replayed.isEmpty)
    }

    func testPendingNoteIDsFindsNonEmptyFiles() throws {
        let noteID = UUID()
        let entry = RecoveryJournal.Entry(range: NSRange(location: 0, length: 5), replacement: "world", timestamp: Date())
        try journal.append(entry: entry, for: noteID)
        let pending = try journal.pendingNoteIDs()
        XCTAssertTrue(pending.contains(noteID))
    }

    func testMultipleEntriesReplayedInOrder() throws {
        let noteID = UUID()
        let e1 = RecoveryJournal.Entry(range: NSRange(location: 0, length: 0), replacement: "A", timestamp: Date())
        let e2 = RecoveryJournal.Entry(range: NSRange(location: 1, length: 0), replacement: "B", timestamp: Date())
        let e3 = RecoveryJournal.Entry(range: NSRange(location: 2, length: 0), replacement: "C", timestamp: Date())
        try journal.append(entry: e1, for: noteID)
        try journal.append(entry: e2, for: noteID)
        try journal.append(entry: e3, for: noteID)
        let replayed = try journal.replay(for: noteID)
        XCTAssertEqual(replayed.count, 3)
        XCTAssertEqual(replayed.map { $0.replacement }, ["A", "B", "C"])
    }

    func testTruncatedWALNotInPending() throws {
        let noteID = UUID()
        let entry = RecoveryJournal.Entry(range: NSRange(location: 0, length: 0), replacement: "X", timestamp: Date())
        try journal.append(entry: entry, for: noteID)
        try journal.truncate(for: noteID)
        let pending = try journal.pendingNoteIDs()
        XCTAssertFalse(pending.contains(noteID))
    }

    func testNonExistentNoteReturnsEmptyReplay() throws {
        let replayed = try journal.replay(for: UUID())
        XCTAssertTrue(replayed.isEmpty)
    }

    func testCorruptedTrailingEntryIsSkippedOnReplay() throws {
        let noteID = UUID()
        let good = RecoveryJournal.Entry(range: NSRange(location: 0, length: 0), replacement: "good", timestamp: Date())
        try journal.append(entry: good, for: noteID)
        // Manually append a truncated JSON line to simulate a crash mid-write.
        let walURL = tmpDir.appendingPathComponent("\(noteID.uuidString).wal")
        let handle = try FileHandle(forWritingTo: walURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        handle.write(Data("{\"incomplete\":".utf8))
        // Replay should return the valid entry and silently skip the corrupt line.
        let replayed = try journal.replay(for: noteID)
        XCTAssertEqual(replayed.count, 1)
        XCTAssertEqual(replayed[0].replacement, "good")
    }
}
