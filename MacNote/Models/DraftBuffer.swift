import Foundation
import Observation

/// Manages the transient "new note" draft that exists in memory before the user
/// commits it to disk. While `isActive` is true the editor shows draft text
/// rather than a persisted note file.
@Observable final class DraftBuffer {
    var text: String = ""
    /// `true`  → editor is showing the draft (no real note selected)
    /// `false` → a real note is open; draft is idle
    var isActive: Bool = true

    /// Reset draft to empty and return to "new note" mode.
    func clear() {
        text = ""
        isActive = true
    }

    /// Called when the draft is saved as a real note.
    /// - Parameter noteID: The UUID of the newly-created `NoteItem`.
    func promote(to noteID: UUID) {
        isActive = false
        // text is intentionally kept until the caller has confirmed the write.
    }

    /// Snapshot the current text for recovery purposes.
    var snapshot: String { text }
}
