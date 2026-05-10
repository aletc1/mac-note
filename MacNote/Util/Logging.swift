import os

extension Logger {
    /// Storage subsystem: NoteStore, IndexService, CategoryStore, WAL
    static let storage = Logger(subsystem: "com.macnote.app", category: "storage")

    /// Editor subsystem: EditorViewModel, HighlighterController, ImageRenderer
    static let editor = Logger(subsystem: "com.macnote.app", category: "editor")

    /// Index subsystem: IndexService, FileWatcher, reconciliation
    static let index = Logger(subsystem: "com.macnote.app", category: "index")

    /// Paste / drag-and-drop subsystem: PasteHandler, image ingestion
    static let paste = Logger(subsystem: "com.macnote.app", category: "paste")

    /// App-level lifecycle (startup, state save/load)
    static let app = Logger(subsystem: "com.macnote.app", category: "app")
}
