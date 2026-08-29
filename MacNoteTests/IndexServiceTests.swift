import XCTest
import SQLite3
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

    func testUpdateRemovesStaleBodyFromSearch() throws {
        let id = UUID()
        let note = NoteItem(id: id, title: "Groceries", language: .markdown,
                            categoryID: nil, createdAt: Date(), modifiedAt: Date(),
                            path: tmpDir.appendingPathComponent("g.md"))
        try service.insert(note: note, body: "milk eggs butter")
        try service.update(note: note, body: "bread jam")

        XCTAssertTrue(try service.search(query: "eggs").isEmpty)
        XCTAssertEqual(try service.search(query: "jam").count, 1)
    }

    func testDeleteRemovesNoteFromSearchIndex() throws {
        let id = UUID()
        let note = NoteItem(id: id, title: "Temp", language: .plain,
                            categoryID: nil, createdAt: Date(), modifiedAt: Date(),
                            path: tmpDir.appendingPathComponent("t.txt"))
        try service.insert(note: note, body: "unique searchable term")
        try service.delete(noteID: id)
        XCTAssertTrue(try service.search(query: "searchable").isEmpty)
    }

    /// A prior build created `notes_fts` as a contentless FTS5 table
    /// (`content=''`), which silently broke every id-based join and delete.
    /// `setup()` must detect that on-disk schema and rebuild the database
    /// rather than leaving it broken behind `CREATE ... IF NOT EXISTS`.
    func testMigratesAwayFromContentlessFTSSchema() throws {
        // A dedicated subdirectory — `tmpDir`'s own index.sqlite already
        // exists (created with the fixed schema by setUpWithError) by the
        // time this test runs.
        let migrationDir = tmpDir.appendingPathComponent("migration-test")
        try FileManager.default.createDirectory(at: migrationDir, withIntermediateDirectories: true)

        // Recreate the exact broken schema a previous version of the app
        // would have left on disk, then hand it to a fresh IndexService.
        let brokenDBURL = migrationDir.appendingPathComponent("index.sqlite")
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(brokenDBURL.path, &db), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(db, """
            CREATE TABLE notes (
                id TEXT PRIMARY KEY NOT NULL, title TEXT NOT NULL DEFAULT '',
                language TEXT NOT NULL DEFAULT 'md', category_id TEXT,
                created_at REAL NOT NULL, modified_at REAL NOT NULL, path TEXT NOT NULL
            );
            """, nil, nil, nil), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(db, """
            CREATE VIRTUAL TABLE notes_fts
            USING fts5(id UNINDEXED, body, content='', tokenize='porter ascii');
            """, nil, nil, nil), SQLITE_OK)
        sqlite3_close(db)

        let migratedService = IndexService(supportDirectory: migrationDir)
        try migratedService.setup()

        let note = NoteItem(id: UUID(), title: "Post-migration", language: .markdown,
                            categoryID: nil, createdAt: Date(), modifiedAt: Date(),
                            path: migrationDir.appendingPathComponent("pm.md"))
        try migratedService.insert(note: note, body: "searchable after migration")
        XCTAssertEqual(try migratedService.search(query: "searchable").count, 1)
    }
}
