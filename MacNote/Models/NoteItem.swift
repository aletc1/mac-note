import Foundation

/// A lightweight value type representing a note in the sidebar list.
/// The actual note content is stored on disk and loaded on demand.
struct NoteItem: Identifiable, Hashable {
    let id: UUID
    var title: String
    var language: NoteLanguage
    var categoryID: String?
    var createdAt: Date
    var modifiedAt: Date
    /// Absolute path to the note file on disk (inside ~/.notes/)
    var path: URL
}

// MARK: - Convenience

extension NoteItem {
    /// Returns a note item whose title is derived from its first non-empty line.
    static func make(
        id: UUID = UUID(),
        title: String,
        language: NoteLanguage = .markdown,
        categoryID: String? = nil,
        path: URL,
        now: Date = Date()
    ) -> NoteItem {
        NoteItem(
            id: id,
            title: title,
            language: language,
            categoryID: categoryID,
            createdAt: now,
            modifiedAt: now,
            path: path
        )
    }

    /// Derive a sidebar title from raw note content (first non-blank line, capped at 80 chars).
    static func titleFromContent(_ content: String) -> String {
        let firstLine = content
            .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map(String.init) ?? "Untitled"
        let trimmed = firstLine
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "^#+\\s*", with: "", options: .regularExpression)
        return trimmed.isEmpty ? "Untitled" : String(trimmed.prefix(80))
    }
}
