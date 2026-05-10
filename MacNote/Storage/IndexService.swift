import Foundation
import SQLite3
import os

// TODO: wire GRDB SPM dep — replace raw SQLite3 calls with DatabasePool

/// SQLite-backed index for notes: fast list, FTS search, and mtime-based reindex detection.
final class IndexService {

    // MARK: - Constants

    private static let dbFilename = "index.sqlite"

    // MARK: - State

    private let dbURL: URL
    // var dbPool: DatabasePool  // TODO: wire GRDB SPM dep
    private var db: OpaquePointer?
    // Serial queue gates every SQLite call; replaces SQLITE_OPEN_FULLMUTEX until GRDB lands.
    private let queue = DispatchQueue(label: "macnote.indexservice")
    private let logger = Logger(subsystem: "com.macnote", category: "IndexService")

    // MARK: - Init

    init(supportDirectory: URL? = nil) {
        let dir: URL
        if let supportDirectory {
            dir = supportDirectory
        } else {
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support")
            dir = appSupport.appendingPathComponent("MacNote", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        dbURL = dir.appendingPathComponent(IndexService.dbFilename)
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    // MARK: - Setup

    /// Open the database and create tables if they don't exist.
    func setup() throws {
        try queue.sync {
            // Open (or create) the database file.
            let rc = sqlite3_open(dbURL.path, &db)
            guard rc == SQLITE_OK, let db else {
                throw IndexServiceError.openFailed(message: sqliteMessage(db))
            }

            // Enable WAL mode for better concurrency.
            try exec("PRAGMA journal_mode=WAL;")
            try exec("PRAGMA foreign_keys=ON;")

            // Notes table.
            try exec("""
                CREATE TABLE IF NOT EXISTS notes (
                    id          TEXT PRIMARY KEY NOT NULL,
                    title       TEXT NOT NULL DEFAULT '',
                    language    TEXT NOT NULL DEFAULT 'md',
                    category_id TEXT,
                    created_at  REAL NOT NULL,
                    modified_at REAL NOT NULL,
                    path        TEXT NOT NULL
                );
                """)

            // Full-text search virtual table (FTS5).
            try exec("""
                CREATE VIRTUAL TABLE IF NOT EXISTS notes_fts
                USING fts5(id UNINDEXED, body, content='', tokenize='porter ascii');
                """)

            // Categories table.
            try exec("""
                CREATE TABLE IF NOT EXISTS categories (
                    id         TEXT PRIMARY KEY NOT NULL,
                    name       TEXT NOT NULL,
                    color_hex  TEXT NOT NULL DEFAULT '#0080FF'
                );
                """)

            logger.debug("IndexService setup complete at \(self.dbURL.path)")
        }
    }

    // MARK: - Insert

    func insert(note: NoteItem, body: String) throws {
        try queue.sync {
            guard let db else { throw IndexServiceError.notOpen }
            let sql = """
                INSERT OR REPLACE INTO notes
                    (id, title, language, category_id, created_at, modified_at, path)
                VALUES (?, ?, ?, ?, ?, ?, ?);
                """
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            try prepare(sql, &stmt)
            sqlite3_bind_text(stmt, 1, note.id.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, note.title, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, note.language.rawValue, -1, SQLITE_TRANSIENT)
            if let cat = note.categoryID {
                sqlite3_bind_text(stmt, 4, cat, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 4)
            }
            sqlite3_bind_double(stmt, 5, note.createdAt.timeIntervalSince1970)
            sqlite3_bind_double(stmt, 6, note.modifiedAt.timeIntervalSince1970)
            sqlite3_bind_text(stmt, 7, note.path.path, -1, SQLITE_TRANSIENT)
            try step(stmt)

            // Insert into FTS.
            let ftsSql = "INSERT INTO notes_fts(id, body) VALUES (?, ?);"
            var ftsStmt: OpaquePointer?
            defer { sqlite3_finalize(ftsStmt) }
            try prepare(ftsSql, &ftsStmt)
            sqlite3_bind_text(ftsStmt, 1, note.id.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(ftsStmt, 2, body, -1, SQLITE_TRANSIENT)
            try step(ftsStmt)
        }
    }

    // MARK: - Update

    func update(note: NoteItem, body: String) throws {
        try queue.sync {
            guard let db else { throw IndexServiceError.notOpen }
            let sql = """
                UPDATE notes SET
                    title = ?, language = ?, category_id = ?,
                    modified_at = ?, path = ?
                WHERE id = ?;
                """
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            try prepare(sql, &stmt)
            sqlite3_bind_text(stmt, 1, note.title, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, note.language.rawValue, -1, SQLITE_TRANSIENT)
            if let cat = note.categoryID {
                sqlite3_bind_text(stmt, 3, cat, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 3)
            }
            sqlite3_bind_double(stmt, 4, note.modifiedAt.timeIntervalSince1970)
            sqlite3_bind_text(stmt, 5, note.path.path, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 6, note.id.uuidString, -1, SQLITE_TRANSIENT)
            try step(stmt)

            // Update FTS: delete old row, insert new.
            let delFts = "DELETE FROM notes_fts WHERE id = ?;"
            var delStmt: OpaquePointer?
            defer { sqlite3_finalize(delStmt) }
            try prepare(delFts, &delStmt)
            sqlite3_bind_text(delStmt, 1, note.id.uuidString, -1, SQLITE_TRANSIENT)
            try step(delStmt)

            let insFts = "INSERT INTO notes_fts(id, body) VALUES (?, ?);"
            var insStmt: OpaquePointer?
            defer { sqlite3_finalize(insStmt) }
            try prepare(insFts, &insStmt)
            sqlite3_bind_text(insStmt, 1, note.id.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(insStmt, 2, body, -1, SQLITE_TRANSIENT)
            try step(insStmt)
        }
    }

    // MARK: - Delete

    func delete(noteID: UUID) throws {
        try queue.sync {
            guard let db else { throw IndexServiceError.notOpen }

            let sql = "DELETE FROM notes WHERE id = ?;"
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            try prepare(sql, &stmt)
            sqlite3_bind_text(stmt, 1, noteID.uuidString, -1, SQLITE_TRANSIENT)
            try step(stmt)

            let ftsSql = "DELETE FROM notes_fts WHERE id = ?;"
            var ftsStmt: OpaquePointer?
            defer { sqlite3_finalize(ftsStmt) }
            try prepare(ftsSql, &ftsStmt)
            sqlite3_bind_text(ftsStmt, 1, noteID.uuidString, -1, SQLITE_TRANSIENT)
            try step(ftsStmt)
        }
    }

    // MARK: - Fetch All

    func fetchAll() throws -> [NoteItem] {
        return try queue.sync {
            guard let db else { throw IndexServiceError.notOpen }
            let sql = "SELECT id, title, language, category_id, created_at, modified_at, path FROM notes ORDER BY modified_at DESC;"
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            try prepare(sql, &stmt)

            var results: [NoteItem] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let item = noteItem(from: stmt) { results.append(item) }
            }
            return results
        }
    }

    // MARK: - Search (FTS)

    func search(query: String) throws -> [NoteItem] {
        return try queue.sync {
            guard let db else { throw IndexServiceError.notOpen }
            // Phrase-wrap the query: wrapping in "" neutralises FTS5 operators
            // (*, (, ), :, OR, AND, NOT) and double-escaping inner " handles
            // quotes in user input. All input is treated as a literal phrase.
            let escaped = query.replacingOccurrences(of: "\"", with: "\"\"")
            let sql = """
                SELECT n.id, n.title, n.language, n.category_id, n.created_at, n.modified_at, n.path
                FROM notes n
                JOIN notes_fts f ON n.id = f.id
                WHERE notes_fts MATCH ?
                ORDER BY rank;
                """
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            try prepare(sql, &stmt)
            sqlite3_bind_text(stmt, 1, "\"\(escaped)\"", -1, SQLITE_TRANSIENT)

            var results: [NoteItem] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let item = noteItem(from: stmt) { results.append(item) }
            }
            return results
        }
    }

    // MARK: - Categories CRUD

    func fetchAllCategories() throws -> [(id: String, name: String, colorHex: String)] {
        try queue.sync {
            guard let db else { throw IndexServiceError.notOpen }
            let sql = "SELECT id, name, color_hex FROM categories ORDER BY name;"
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            try prepare(sql, &stmt)
            var results: [(id: String, name: String, colorHex: String)] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id       = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
                let name     = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
                let colorHex = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? "0080FF"
                results.append((id: id, name: name, colorHex: colorHex))
            }
            return results
        }
    }

    func upsertCategory(id: String, name: String, colorHex: String) throws {
        try queue.sync {
            guard let db else { throw IndexServiceError.notOpen }
            let sql = "INSERT OR REPLACE INTO categories (id, name, color_hex) VALUES (?, ?, ?);"
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            try prepare(sql, &stmt)
            sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, name, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, colorHex, -1, SQLITE_TRANSIENT)
            try step(stmt)
        }
    }

    func deleteCategory(id: String) throws {
        try queue.sync {
            guard let db else { throw IndexServiceError.notOpen }
            let sql = "DELETE FROM categories WHERE id = ?;"
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            try prepare(sql, &stmt)
            sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
            try step(stmt)
        }
    }

    // MARK: - Reindex detection

    /// Returns `true` if the file's mtime is newer than what's stored in `modified_at`.
    func needsReindex(note: NoteItem) -> Bool {
        queue.sync {
            guard let db else { return false }
            let sql = "SELECT modified_at FROM notes WHERE id = ?;"
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard (try? prepare(sql, &stmt)) != nil else { return true }
            sqlite3_bind_text(stmt, 1, note.id.uuidString, -1, SQLITE_TRANSIENT)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return true }
            let dbModified = sqlite3_column_double(stmt, 0)
            let fileModified = note.modifiedAt.timeIntervalSince1970
            return fileModified > dbModified + 0.001
        }
    }

    // MARK: - Private helpers

    @discardableResult
    private func exec(_ sql: String) throws -> Int32 {
        guard let db else { throw IndexServiceError.notOpen }
        var errMsg: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &errMsg)
        if rc != SQLITE_OK {
            let msg = errMsg.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(errMsg)
            throw IndexServiceError.execFailed(sql: sql, message: msg)
        }
        return rc
    }

    private func prepare(_ sql: String, _ stmt: inout OpaquePointer?) throws {
        guard let db else { throw IndexServiceError.notOpen }
        let rc = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        if rc != SQLITE_OK {
            throw IndexServiceError.prepareFailed(sql: sql, message: sqliteMessage(db))
        }
    }

    private func step(_ stmt: OpaquePointer?) throws {
        let rc = sqlite3_step(stmt)
        if rc != SQLITE_DONE && rc != SQLITE_ROW {
            throw IndexServiceError.stepFailed(code: rc)
        }
    }

    private func sqliteMessage(_ db: OpaquePointer?) -> String {
        db.map { String(cString: sqlite3_errmsg($0)) } ?? "no db"
    }

    /// Build a `NoteItem` from a prepared SELECT statement row.
    private func noteItem(from stmt: OpaquePointer?) -> NoteItem? {
        guard let stmt else { return nil }
        guard
            let idCStr  = sqlite3_column_text(stmt, 0),
            let id = UUID(uuidString: String(cString: idCStr))
        else { return nil }

        let title = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
        let langRaw = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? "md"
        let language = NoteLanguage(rawValue: langRaw) ?? .plain
        let categoryID = sqlite3_column_text(stmt, 3).map { String(cString: $0) }
        let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4))
        let modifiedAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 5))
        let pathStr = sqlite3_column_text(stmt, 6).map { String(cString: $0) } ?? ""
        let path = URL(fileURLWithPath: pathStr)

        return NoteItem(
            id: id,
            title: title,
            language: language,
            categoryID: categoryID,
            createdAt: createdAt,
            modifiedAt: modifiedAt,
            path: path
        )
    }
}

// MARK: - Errors

enum IndexServiceError: LocalizedError {
    case notOpen
    case openFailed(message: String)
    case execFailed(sql: String, message: String)
    case prepareFailed(sql: String, message: String)
    case stepFailed(code: Int32)

    var errorDescription: String? {
        switch self {
        case .notOpen:                         return "Database is not open"
        case .openFailed(let m):               return "Failed to open DB: \(m)"
        case .execFailed(let s, let m):        return "SQL exec failed [\(s)]: \(m)"
        case .prepareFailed(let s, let m):     return "SQL prepare failed [\(s)]: \(m)"
        case .stepFailed(let c):               return "sqlite3_step returned \(c)"
        }
    }
}

// MARK: - SQLITE_TRANSIENT shim

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
