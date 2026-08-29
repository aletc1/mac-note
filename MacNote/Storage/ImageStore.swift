import Foundation
import CryptoKit
import os

/// Manages inline image files stored alongside notes in `~/.notes/`.
/// Images are named `{noteUUID}-{hash8}.{ext}` for deduplication.
final class ImageStore {

    // MARK: - State

    private let notesDir: URL
    private let trashDir: URL
    private let logger = Logger(subsystem: "com.macnote", category: "ImageStore")

    // MARK: - Init

    init(notesDirectory: URL = NoteStore.defaultNotesDirectory) {
        self.notesDir = notesDirectory
        self.trashDir = notesDirectory.appendingPathComponent(".trash", isDirectory: true)
    }

    // MARK: - Write

    /// Write image data to `~/.notes/{noteUUID}-{hash8}.{ext}`, returning the filename.
    /// If a file with the same hash already exists it is reused (content-addressed).
    func write(imageData: Data, ext: String, for noteUUID: UUID) throws -> String {
        let hash = contentHash(imageData)
        // Lowercased so the UUID segment matches the lowercase hex hash segment.
        let filename = "\(noteUUID.uuidString.lowercased())-\(hash).\(ext)"
        let dest = notesDir.appendingPathComponent(filename)

        if !FileManager.default.fileExists(atPath: dest.path) {
            try imageData.write(to: dest, options: .atomic)
            logger.debug("Wrote image \(filename) (\(imageData.count) bytes)")
        }
        return filename
    }

    // MARK: - URL

    /// Return the full URL for an image filename.
    func url(for filename: String) -> URL {
        notesDir.appendingPathComponent(filename)
    }

    // MARK: - Garbage Collection

    /// Move images whose filenames start with `{noteUUID}-` but are NOT in
    /// `liveReferences` into `.trash/` so they can be cleaned up later.
    func garbageCollect(noteUUID: UUID, liveReferences: Set<String>) throws {
        let fm = FileManager.default

        // Ensure trash dir exists.
        try fm.createDirectory(at: trashDir, withIntermediateDirectories: true)

        let prefix = "\(noteUUID.uuidString.lowercased())-"
        let contents = try fm.contentsOfDirectory(
            at: notesDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        for url in contents {
            let name = url.lastPathComponent
            guard name.hasPrefix(prefix), !liveReferences.contains(name) else { continue }
            let dest = trashDir.appendingPathComponent(name)
            do {
                try fm.moveItem(at: url, to: dest)
                logger.debug("GC: moved orphaned image \(name) to .trash/")
            } catch {
                logger.warning("GC: failed to move \(name): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Private: SHA-256 prefix

    /// Return the first 8 hex characters of the SHA-256 digest of `data`.
    private func contentHash(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        let hex = digest.compactMap { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(8))
    }
}
