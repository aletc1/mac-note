import Foundation
import os

/// Write-Ahead Log for per-note crash recovery.
/// Each note gets its own newline-delimited JSON file in
/// `~/Library/Application Support/MacNote/recovery/<UUID>.wal`.
final class RecoveryJournal {

    // MARK: - Types

    struct Entry: Codable {
        /// Encoded as a two-element array [location, length] for compactness.
        let range: NSRange
        let replacement: String
        let timestamp: Date

        // MARK: Custom Codable for NSRange

        private enum CodingKeys: String, CodingKey {
            case range, replacement, timestamp
        }

        init(range: NSRange, replacement: String, timestamp: Date = Date()) {
            self.range = range
            self.replacement = replacement
            self.timestamp = timestamp
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            var rangeArr = try c.nestedUnkeyedContainer(forKey: .range)
            let location = try rangeArr.decode(Int.self)
            let length   = try rangeArr.decode(Int.self)
            range       = NSRange(location: location, length: length)
            replacement = try c.decode(String.self, forKey: .replacement)
            timestamp   = try c.decode(Date.self,   forKey: .timestamp)
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            var rangeArr = c.nestedUnkeyedContainer(forKey: .range)
            try rangeArr.encode(range.location)
            try rangeArr.encode(range.length)
            try c.encode(replacement, forKey: .replacement)
            try c.encode(timestamp,   forKey: .timestamp)
        }
    }

    // MARK: - State

    private let recoveryDir: URL
    private let logger = Logger(subsystem: "com.macnote", category: "RecoveryJournal")

    // MARK: - Init

    init(recoveryDirectory: URL? = nil) {
        if let dir = recoveryDirectory {
            recoveryDir = dir
        } else {
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support")
            recoveryDir = appSupport
                .appendingPathComponent("MacNote", isDirectory: true)
                .appendingPathComponent("recovery", isDirectory: true)
        }
        try? FileManager.default.createDirectory(
            at: recoveryDir,
            withIntermediateDirectories: true
        )
    }

    // MARK: - Helpers

    private func walURL(for noteID: UUID) -> URL {
        recoveryDir.appendingPathComponent("\(noteID.uuidString).wal")
    }

    // MARK: - Append (O_APPEND | O_SYNC)

    /// Append one JSON-encoded entry followed by a newline.
    func append(entry: Entry, for noteID: UUID) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var data = try encoder.encode(entry)
        data.append(0x0A) // newline

        let url = walURL(for: noteID)
        let path = url.path

        // Open with O_CREAT | O_APPEND | O_WRONLY | O_SYNC for durable appends.
        let fd = open(path, O_CREAT | O_APPEND | O_WRONLY | O_SYNC, 0o600)
        guard fd >= 0 else {
            throw RecoveryJournalError.openFailed(errno: errno)
        }
        defer { close(fd) }

        try data.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) throws in
            guard let base = ptr.baseAddress else { return }
            var remaining = data.count
            var offset = 0
            while remaining > 0 {
                let n = Darwin.write(fd, base.advanced(by: offset), remaining)
                if n < 0 {
                    if errno == EINTR { continue }
                    throw RecoveryJournalError.writeFailed(errno: errno)
                }
                if n == 0 { throw RecoveryJournalError.writeFailed(errno: 0) }
                remaining -= n
                offset += n
            }
        }
    }

    // MARK: - Replay

    /// Read all entries from the WAL for a given note.
    func replay(for noteID: UUID) throws -> [Entry] {
        let url = walURL(for: noteID)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }

        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { return [] }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var entries: [Entry] = []
        var start = data.startIndex
        while start < data.endIndex {
            // Find the next newline.
            if let nl = data[start...].firstIndex(of: 0x0A) {
                let lineData = data[start..<nl]
                if !lineData.isEmpty,
                   let entry = try? decoder.decode(Entry.self, from: Data(lineData)) {
                    entries.append(entry)
                }
                start = data.index(after: nl)
            } else {
                // Last line without trailing newline.
                let lineData = data[start...]
                if !lineData.isEmpty,
                   let entry = try? decoder.decode(Entry.self, from: Data(lineData)) {
                    entries.append(entry)
                }
                break
            }
        }
        return entries
    }

    // MARK: - Delete WAL

    /// Remove the WAL file for a deleted note.
    func deleteWAL(for noteID: UUID) throws {
        let url = walURL(for: noteID)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
        logger.debug("Deleted WAL for note \(noteID)")
    }

    // MARK: - Truncate

    /// Zero out (truncate to 0 bytes) the WAL after a successful save.
    func truncate(for noteID: UUID) throws {
        let url = walURL(for: noteID)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.truncate(atOffset: 0)
        logger.debug("Truncated WAL for note \(noteID)")
    }

    // MARK: - Pending note IDs on launch

    /// Return IDs of notes that have non-empty WAL files (need replay on launch).
    func pendingNoteIDs() throws -> [UUID] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: recoveryDir.path) else { return [] }

        let contents = try fm.contentsOfDirectory(
            at: recoveryDir,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        return contents.compactMap { url -> UUID? in
            guard url.pathExtension == "wal" else { return nil }
            let name = url.deletingPathExtension().lastPathComponent
            guard let uuid = UUID(uuidString: name) else { return nil }
            // Only include non-empty files.
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return size > 0 ? uuid : nil
        }
    }
}

// MARK: - Errors

enum RecoveryJournalError: LocalizedError {
    case openFailed(errno: Int32)
    case writeFailed(errno: Int32)

    var errorDescription: String? {
        switch self {
        case .openFailed(let code):
            return "Failed to open WAL file: errno \(code)"
        case .writeFailed(let code):
            return "Failed to write WAL entry: errno \(code)"
        }
    }
}
