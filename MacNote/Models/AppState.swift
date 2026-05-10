import Foundation

/// Persisted app state written to `~/.notes/state.json` on quit / background.
/// Restored on next launch so the user returns to exactly where they left off.
struct AppState: Codable {
    var lastOpenNoteID: UUID?
    /// Draft text that hadn't been saved to a real file yet.
    var draftText: String
    /// Last window frame so we can restore position (optional).
    var windowFrame: WindowFrame?
    /// Cursor offset (UTF-16 code units, matching NSRange.location).
    var cursorLocation: Int

    // MARK: - Defaults

    static var empty: AppState {
        AppState(
            lastOpenNoteID: nil,
            draftText: "",
            windowFrame: nil,
            cursorLocation: 0
        )
    }

    // MARK: - Persistence helpers

    /// The URL where state.json lives.
    static var stateFileURL: URL {
        let notesDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".notes", isDirectory: true)
        return notesDir.appendingPathComponent("state.json")
    }

    /// Load from disk, returning `.empty` if the file doesn't exist or is corrupt.
    static func load() -> AppState {
        let url = stateFileURL
        guard
            FileManager.default.fileExists(atPath: url.path),
            let data = try? Data(contentsOf: url),
            let state = try? JSONDecoder().decode(AppState.self, from: data)
        else {
            return .empty
        }
        return state
    }

    /// Persist to disk. Failures are non-fatal (logged by the caller).
    func save() throws {
        let url = AppState.stateFileURL
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(self)
        try data.write(to: url, options: .atomic)
    }
}

// MARK: - Window frame helper (avoids CGRect Codable conformance issues)

struct WindowFrame: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(_ rect: CGRect) {
        x = rect.origin.x
        y = rect.origin.y
        width = rect.size.width
        height = rect.size.height
    }

    var cgRect: CGRect {
        CGRect(origin: CGPoint(x: x, y: y), size: CGSize(width: width, height: height))
    }
}
