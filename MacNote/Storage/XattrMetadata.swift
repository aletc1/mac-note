import Foundation

/// Metadata stored as an extended attribute on each note file.
struct NoteXattr: Codable {
    var categoryID: String?
    var createdAt: Date?
}

/// Helpers for reading and writing `NoteXattr` via `getxattr` / `setxattr` syscalls.
enum XattrMetadata {

    static let key = "com.macnote.meta#S"

    // MARK: - Read

    /// Read `NoteXattr` from the extended attributes of `url`.
    /// Returns `nil` if the attribute is absent (not an error).
    static func read(from url: URL) throws -> NoteXattr? {
        let path = url.path
        // First call: measure required buffer size.
        let size = getxattr(path, key, nil, 0, 0, 0)
        guard size > 0 else {
            if errno == ENOATTR { return nil }
            throw XattrError.readFailed(errno: errno)
        }

        var buffer = [UInt8](repeating: 0, count: size)
        let read = getxattr(path, key, &buffer, size, 0, 0)
        guard read >= 0 else { throw XattrError.readFailed(errno: errno) }

        let data = Data(buffer[..<read])
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(NoteXattr.self, from: data)
    }

    // MARK: - Write

    /// Encode `meta` as JSON and store it as an extended attribute on `url`.
    static func write(_ meta: NoteXattr, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(meta)

        let result = data.withUnsafeBytes { ptr -> Int32 in
            guard let base = ptr.baseAddress else { return -1 }
            return Int32(setxattr(url.path, key, base, data.count, 0, 0))
        }
        guard result == 0 else { throw XattrError.writeFailed(errno: errno) }
    }
}

// MARK: - Errors

enum XattrError: LocalizedError {
    case readFailed(errno: Int32)
    case writeFailed(errno: Int32)

    var errorDescription: String? {
        switch self {
        case .readFailed(let code):
            return "getxattr failed: errno \(code) — \(String(cString: strerror(code)))"
        case .writeFailed(let code):
            return "setxattr failed: errno \(code) — \(String(cString: strerror(code)))"
        }
    }
}

// MARK: - ENOATTR shim (not exported by Darwin overlay in all SDK versions)

private var ENOATTR: Int32 { 93 } // ENOATTR == 93 on macOS
