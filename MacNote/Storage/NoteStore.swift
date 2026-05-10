import Foundation
import os

/// Manages the `~/.notes/` directory: CRUD for note files with atomic writes.
final class NoteStore {

    // MARK: - Directory

    static let defaultNotesDirectory: URL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".notes", isDirectory: true)

    let notesDirectory: URL
    private let fm = FileManager.default
    private let logger = Logger(subsystem: "com.macnote", category: "NoteStore")

    // MARK: - Init

    init(notesDirectory: URL = NoteStore.defaultNotesDirectory) {
        self.notesDirectory = notesDirectory
    }

    // MARK: - Setup

    /// Create the notes directory if it doesn't exist yet.
    func ensureDirectory() throws {
        try fm.createDirectory(
            at: notesDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    // MARK: - Read

    /// Load the full UTF-8 text of a note from disk.
    func readContent(of note: NoteItem) throws -> String {
        let data = try Data(contentsOf: note.path)
        guard let string = String(data: data, encoding: .utf8) else {
            throw NoteStoreError.decodingFailed(note.path)
        }
        return string
    }

    // MARK: - Write (atomic)

    /// Write `content` atomically: write to a temp file then rename(2) into place.
    func write(content: String, to note: NoteItem) throws {
        let data = Data(content.utf8)
        let tmpURL = notesDirectory.appendingPathComponent(".\(note.id.uuidString).tmp")

        // Write to temp location.
        try data.write(to: tmpURL, options: .atomic)

        // Atomically replace the destination with the temp file.
        _ = try fm.replaceItemAt(note.path, withItemAt: tmpURL, backupItemName: nil, options: [])
        logger.debug("Wrote note \(note.id) (\(data.count) bytes)")
    }

    /// Async wrapper for the editor (runs write off-main without blocking UI).
    func writeAsync(content: String, to note: NoteItem) async throws {
        let store = self
        try await Task.detached(priority: .utility) {
            try store.write(content: content, to: note)
        }.value
    }

    // MARK: - Create

    /// Create a new empty note file on disk and return its `NoteItem`.
    func create(uuid: UUID = UUID(), language: NoteLanguage) throws -> NoteItem {
        try ensureDirectory()
        let filename = "\(uuid.uuidString).\(language.fileExtension)"
        let url = notesDirectory.appendingPathComponent(filename)

        // Write an empty file.
        try Data().write(to: url, options: .withoutOverwriting)

        let now = Date()
        return NoteItem(
            id: uuid,
            title: "Untitled",
            language: language,
            categoryID: nil,
            createdAt: now,
            modifiedAt: now,
            path: url
        )
    }

    // MARK: - Rename (extension change)

    /// Change a note's language by renaming its file (POSIX rename for atomicity).
    @discardableResult
    func rename(note: NoteItem, to language: NoteLanguage) throws -> NoteItem {
        let newFilename = "\(note.id.uuidString).\(language.fileExtension)"
        let newURL = notesDirectory.appendingPathComponent(newFilename)

        // rename(2) is atomic on the same filesystem.
        let oldPath = note.path.path
        let newPath = newURL.path
        guard Darwin.rename(oldPath, newPath) == 0 else {
            throw NoteStoreError.renameFailed(errno: errno)
        }

        var updated = note
        updated = NoteItem(
            id: note.id,
            title: note.title,
            language: language,
            categoryID: note.categoryID,
            createdAt: note.createdAt,
            modifiedAt: note.modifiedAt,
            path: newURL
        )
        return updated
    }

    // MARK: - Delete (move to .trash)

    /// Move the note's file into `~/.notes/.trash/` so it can be recovered manually.
    /// If a file with the same name already exists in `.trash/`, a timestamp prefix is added.
    func moveToTrash(note: NoteItem) throws {
        let trashDir = notesDirectory.appendingPathComponent(".trash", isDirectory: true)
        try fm.createDirectory(at: trashDir, withIntermediateDirectories: true)

        let baseName = note.path.lastPathComponent
        var dest = trashDir.appendingPathComponent(baseName)
        if fm.fileExists(atPath: dest.path) {
            let ts = Int(Date().timeIntervalSince1970)
            dest = trashDir.appendingPathComponent("\(ts)-\(baseName)")
        }
        try fm.moveItem(at: note.path, to: dest)
        logger.debug("Moved note \(note.id) to .trash/")
    }

    // MARK: - List

    /// Return all `UUID.{ext}` file URLs inside `~/.notes/`.
    func allNoteURLs() throws -> [URL] {
        try ensureDirectory()
        let contents = try fm.contentsOfDirectory(
            at: notesDirectory,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        return contents.filter { url in
            // Filename must be a valid UUID followed by a known extension.
            let name = url.deletingPathExtension().lastPathComponent
            return UUID(uuidString: name) != nil
                && NoteLanguage(rawValue: url.pathExtension) != nil
        }
    }
}

// MARK: - Errors

enum NoteStoreError: LocalizedError {
    case decodingFailed(URL)
    case renameFailed(errno: Int32)

    var errorDescription: String? {
        switch self {
        case .decodingFailed(let url):
            return "Failed to decode UTF-8 content at \(url.path)"
        case .renameFailed(let code):
            return "rename(2) failed with errno \(code): \(String(cString: strerror(code)))"
        }
    }
}
