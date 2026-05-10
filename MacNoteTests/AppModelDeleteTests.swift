import XCTest
@testable import MacNote

@MainActor
final class AppModelDeleteTests: XCTestCase {
    var tmpNotes: URL!
    var tmpIndex: URL!
    var tmpRecovery: URL!
    var appModel: AppModel!

    override func setUpWithError() throws {
        tmpNotes    = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        tmpIndex    = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        tmpRecovery = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        for dir in [tmpNotes!, tmpIndex!, tmpRecovery!] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        appModel = AppModel(
            notesDirectory: tmpNotes,
            indexSupportDirectory: tmpIndex,
            recoveryDirectory: tmpRecovery
        )
        try appModel.indexService.setup()
    }

    override func tearDownWithError() throws {
        for dir in [tmpNotes, tmpIndex, tmpRecovery] {
            try? FileManager.default.removeItem(at: dir!)
        }
    }

    func testDeleteNoteRemovesFromSidebar() throws {
        let note = appModel.createNote(language: .markdown)
        XCTAssertTrue(appModel.notes.contains { $0.id == note.id })
        appModel.deleteNote(id: note.id)
        XCTAssertFalse(appModel.notes.contains { $0.id == note.id })
    }

    func testDeleteNoteMovesFileToTrash() throws {
        let note = appModel.createNote(language: .markdown)
        let originalPath = note.path.path
        appModel.deleteNote(id: note.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: originalPath))
        let trashPath = tmpNotes
            .appendingPathComponent(".trash")
            .appendingPathComponent(note.path.lastPathComponent)
            .path
        XCTAssertTrue(FileManager.default.fileExists(atPath: trashPath))
    }

    func testDeleteNoteRemovesFromIndex() throws {
        let note = appModel.createNote(language: .markdown)
        appModel.deleteNote(id: note.id)
        let allNotes = try appModel.indexService.fetchAll()
        XCTAssertFalse(allNotes.contains { $0.id == note.id })
    }

    func testDeleteNoteDeletesWAL() throws {
        let note = appModel.createNote(language: .markdown)
        let entry = RecoveryJournal.Entry(
            range: NSRange(location: 0, length: 0), replacement: "edit", timestamp: Date())
        try appModel.recoveryJournal.append(entry: entry, for: note.id)
        appModel.deleteNote(id: note.id)
        let walURL = tmpRecovery.appendingPathComponent("\(note.id.uuidString).wal")
        XCTAssertFalse(FileManager.default.fileExists(atPath: walURL.path))
    }

    func testDeleteNoteClearsSelectedNoteID() throws {
        let note = appModel.createNote(language: .markdown)
        appModel.selectedNoteID = note.id
        appModel.deleteNote(id: note.id)
        XCTAssertNil(appModel.selectedNoteID)
    }

    func testDeleteNonExistentNoteIsNoop() {
        let before = appModel.notes.count
        appModel.deleteNote(id: UUID())
        XCTAssertEqual(appModel.notes.count, before)
    }
}
