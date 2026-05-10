import XCTest
@testable import MacNote

final class IndexServiceTests: XCTestCase {
    var tmpDir: URL!
    var service: IndexService!

    override func setUpWithError() throws {
        tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        service = IndexService(supportDirectory: tmpDir)
        try service.setup()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    func testInsertAndFetch() throws {
        let note = NoteItem(id: UUID(), title: "Test Note", language: .markdown,
                            categoryID: nil, createdAt: Date(), modifiedAt: Date(),
                            path: tmpDir.appendingPathComponent("test.md"))
        try service.insert(note: note, body: "Hello world")
        let fetched = try service.fetchAll()
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].title, "Test Note")
    }

    func testSearchReturnsMatches() throws {
        let note = NoteItem(id: UUID(), title: "Shopping list", language: .markdown,
                            categoryID: nil, createdAt: Date(), modifiedAt: Date(),
                            path: tmpDir.appendingPathComponent("shop.md"))
        try service.insert(note: note, body: "milk eggs butter")
        let results = try service.search(query: "eggs")
        XCTAssertEqual(results.count, 1)
    }

    func testDeleteRemovesNote() throws {
        let id = UUID()
        let note = NoteItem(id: id, title: "To delete", language: .plain,
                            categoryID: nil, createdAt: Date(), modifiedAt: Date(),
                            path: tmpDir.appendingPathComponent("del.txt"))
        try service.insert(note: note, body: "body")
        try service.delete(noteID: id)
        let fetched = try service.fetchAll()
        XCTAssertTrue(fetched.isEmpty)
    }

    func testUpdateChangesTitle() throws {
        let id = UUID()
        var note = NoteItem(id: id, title: "Original", language: .markdown,
                            categoryID: nil, createdAt: Date(), modifiedAt: Date(),
                            path: tmpDir.appendingPathComponent("u.md"))
        try service.insert(note: note, body: "first body")
        note = NoteItem(id: id, title: "Updated", language: .markdown,
                        categoryID: nil, createdAt: note.createdAt, modifiedAt: Date(),
                        path: note.path)
        try service.update(note: note, body: "second body")
        let fetched = try service.fetchAll()
        XCTAssertEqual(fetched.first?.title, "Updated")
    }

    func testSearchNoResultsForMissingTerm() throws {
        let note = NoteItem(id: UUID(), title: "Note", language: .markdown,
                            categoryID: nil, createdAt: Date(), modifiedAt: Date(),
                            path: tmpDir.appendingPathComponent("n.md"))
        try service.insert(note: note, body: "cats and dogs")
        let results = try service.search(query: "elephants")
        XCTAssertTrue(results.isEmpty)
    }

    func testConcurrentInsertsDontCrash() throws {
        let noteIDs = (0..<20).map { _ in UUID() }
        let notes: [NoteItem] = noteIDs.enumerated().map { i, id in
            NoteItem(id: id, title: "Note \(i)", language: .plain,
                     categoryID: nil, createdAt: Date(), modifiedAt: Date(),
                     path: tmpDir.appendingPathComponent("note\(i).txt"))
        }
        DispatchQueue.concurrentPerform(iterations: notes.count) { i in
            try? service.insert(note: notes[i], body: "body \(i)")
        }
        let fetched = try service.fetchAll()
        XCTAssertEqual(fetched.count, notes.count)
    }

    func testFetchAllOrderedByModifiedDescending() throws {
        let older = NoteItem(id: UUID(), title: "Older", language: .plain,
                             categoryID: nil,
                             createdAt: Date(timeIntervalSinceNow: -100),
                             modifiedAt: Date(timeIntervalSinceNow: -100),
                             path: tmpDir.appendingPathComponent("old.txt"))
        let newer = NoteItem(id: UUID(), title: "Newer", language: .plain,
                             categoryID: nil,
                             createdAt: Date(),
                             modifiedAt: Date(),
                             path: tmpDir.appendingPathComponent("new.txt"))
        try service.insert(note: older, body: "old")
        try service.insert(note: newer, body: "new")
        let fetched = try service.fetchAll()
        XCTAssertEqual(fetched.first?.title, "Newer")
    }
}
