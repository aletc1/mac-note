import XCTest
@testable import MacNote

final class NoteStoreTests: XCTestCase {
    var tmpDir: URL!
    var store: NoteStore!

    override func setUpWithError() throws {
        tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        store = NoteStore(notesDirectory: tmpDir)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    func testCreateAndRead() throws {
        let note = try store.create(uuid: UUID(), language: .markdown)
        try store.write(content: "Hello world", to: note)
        let content = try store.readContent(of: note)
        XCTAssertEqual(content, "Hello world")
    }

    func testAtomicWriteDoesNotLeakTempFile() throws {
        let note = try store.create(uuid: UUID(), language: .markdown)
        let bigContent = String(repeating: "a", count: 100_000)
        try store.write(content: bigContent, to: note)  // need sync version for test
        let files = try FileManager.default.contentsOfDirectory(at: tmpDir, includingPropertiesForKeys: nil)
        XCTAssertFalse(files.contains { $0.pathExtension == "tmp" })
    }

    func testRenameChangesExtension() throws {
        let note = try store.create(uuid: UUID(), language: .markdown)
        let renamed = try store.rename(note: note, to: .json)
        XCTAssertEqual(renamed.language, .json)
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamed.path.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: note.path.path))
    }

    func testAllNoteURLs() throws {
        _ = try store.create(uuid: UUID(), language: .markdown)
        _ = try store.create(uuid: UUID(), language: .json)
        let urls = try store.allNoteURLs()
        XCTAssertEqual(urls.count, 2)
    }

    func testDeleteRemovesFile() throws {
        let note = try store.create(uuid: UUID(), language: .markdown)
        XCTAssertTrue(FileManager.default.fileExists(atPath: note.path.path))
        try store.delete(note: note)
        XCTAssertFalse(FileManager.default.fileExists(atPath: note.path.path))
    }

    func testWriteDoesNotChangeUUID() throws {
        let id = UUID()
        let note = try store.create(uuid: id, language: .markdown)
        try store.write(content: "version 2", to: note)
        XCTAssertEqual(note.id, id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: note.path.path))
    }

    func testCreateFileNameContainsUUID() throws {
        let id = UUID()
        let note = try store.create(uuid: id, language: .markdown)
        XCTAssertTrue(note.path.lastPathComponent.hasPrefix(id.uuidString))
    }

    func testEmptyDirectoryHasNoNotes() throws {
        let urls = try store.allNoteURLs()
        XCTAssertTrue(urls.isEmpty)
    }
}
