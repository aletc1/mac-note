import Foundation
import Observation
import os

// NoteStore    → MacNote/Storage/NoteStore.swift
// IndexService → MacNote/Storage/IndexService.swift
// FileWatcher  → MacNote/Storage/FileWatcher.swift
// CategoryStore→ MacNote/Categories/CategoryStore.swift

// MARK: - AppModel

@Observable final class AppModel {

    // MARK: - Published state (observed by SwiftUI views)

    var notes: [NoteItem] = []
    var selectedNoteID: UUID?
    var searchText: String = ""
    var selectedCategoryID: String?
    var draftBuffer: DraftBuffer = DraftBuffer()

    // MARK: - Services

    let noteStore: NoteStore
    let indexService: IndexService
    let categoryStore: CategoryStore
    let fileWatcher: FileWatcher
    let imageStore: ImageStore
    let recoveryJournal: RecoveryJournal

    /// Set by MacNoteApp at startup so deleteNote can cancel a pending debounced save.
    weak var editorViewModel: EditorViewModel?

    // MARK: - Init

    init(
        notesDirectory: URL = NoteStore.defaultNotesDirectory,
        indexSupportDirectory: URL? = nil,
        recoveryDirectory: URL? = nil
    ) {
        noteStore       = NoteStore(notesDirectory: notesDirectory)
        indexService    = IndexService(supportDirectory: indexSupportDirectory)
        categoryStore   = CategoryStore()
        fileWatcher     = FileWatcher()
        imageStore      = ImageStore(notesDirectory: notesDirectory)
        recoveryJournal = RecoveryJournal(recoveryDirectory: recoveryDirectory)
    }

    // MARK: - Startup

    /// Must be called from `.onAppear` on the root view (on the main actor).
    @MainActor
    func startup() {
        Logger.app.info("AppModel.startup()")

        let notesDir = noteStore.notesDirectory
        try? FileManager.default.createDirectory(
            at: notesDir, withIntermediateDirectories: true)

        // Open / create the SQLite index
        do { try indexService.setup() } catch {
            Logger.index.error("IndexService.setup failed: \(error)")
        }

        // Load categories
        categoryStore.indexService = indexService
        try? categoryStore.load()

        // Reconcile disk → index → sidebar
        reconcileIndex()

        // Restore persisted app state
        let state = AppState.load()
        if let lastID = state.lastOpenNoteID,
           notes.contains(where: { $0.id == lastID }) {
            selectedNoteID = lastID
            draftBuffer.isActive = false
        }
        if !state.draftText.isEmpty {
            draftBuffer.text = state.draftText
            if selectedNoteID == nil { draftBuffer.isActive = true }
        }

        // Watch for external file-system changes
        fileWatcher.onChange = { [weak self] _ in
            DispatchQueue.main.async { self?.reconcileIndex() }
        }
        fileWatcher.start(watching: notesDir)
        Logger.app.info("Startup complete — \(self.notes.count) note(s)")
    }

    // MARK: - Note creation

    /// Allocates a UUID, creates the file on disk, inserts into the index, and returns the new NoteItem.
    @discardableResult
    @MainActor
    func createNote(language: NoteLanguage = .markdown, categoryID: String? = nil) -> NoteItem {
        do {
            var item = try noteStore.create(uuid: UUID(), language: language)

            // Apply optional category
            if let catID = categoryID {
                item = NoteItem(id: item.id, title: item.title, language: item.language,
                                categoryID: catID, createdAt: item.createdAt,
                                modifiedAt: item.modifiedAt, path: item.path)
            }

            // Seed from draft if active
            var body = ""
            if draftBuffer.isActive && !draftBuffer.text.isEmpty {
                body = draftBuffer.text
                Task { try? await noteStore.write(content: body, to: item) }
                item = NoteItem(id: item.id,
                                title: NoteItem.titleFromContent(body),
                                language: item.language, categoryID: item.categoryID,
                                createdAt: item.createdAt, modifiedAt: item.modifiedAt,
                                path: item.path)
            }

            try indexService.insert(note: item, body: body)
            notes.insert(item, at: 0)
            draftBuffer.promote(to: item.id)
            selectedNoteID = item.id
            Logger.storage.info("Created note \(item.id)")
            return item
        } catch {
            Logger.storage.error("createNote failed: \(error)")
            // Return a transient placeholder so callers never crash
            let fallback = NoteItem(
                id: UUID(), title: "Untitled", language: language,
                categoryID: categoryID, createdAt: Date(), modifiedAt: Date(),
                path: noteStore.notesDirectory.appendingPathComponent("untitled.md"))
            return fallback
        }
    }

    // MARK: - New note (toolbar button)

    /// Called by the "New Note" button. Saves any draft content first, then opens a fresh blank draft.
    @MainActor
    func startNewNote() {
        if draftBuffer.isActive && !draftBuffer.text.isEmpty {
            // Flush existing draft to disk, then open a fresh blank draft
            createNote()
            draftBuffer.clear()
            selectedNoteID = nil
        } else if !draftBuffer.isActive {
            // Editing a saved note — create a new empty note as usual
            createNote()
        }
        // If already on an empty draft, nothing to do
    }

    // MARK: - Language change

    func changeLanguage(to language: NoteLanguage) {
        guard let id = selectedNoteID,
              let idx = notes.firstIndex(where: { $0.id == id })
        else { return }
        let oldNote = notes[idx]
        do {
            let renamed = try noteStore.rename(note: oldNote, to: language)
            notes[idx] = renamed
            Task { try? indexService.update(note: renamed, body: "") }
            Logger.editor.info("Language → \(language.displayName) for note \(id)")
        } catch {
            Logger.editor.error("changeLanguage rename failed: \(error)")
        }
    }

    // MARK: - Category assignment

    @MainActor
    func setCategory(_ categoryID: String?, for noteID: UUID) {
        guard let idx = notes.firstIndex(where: { $0.id == noteID }) else { return }
        let n = notes[idx]
        let updated = NoteItem(id: n.id, title: n.title, language: n.language,
                               categoryID: categoryID, createdAt: n.createdAt,
                               modifiedAt: n.modifiedAt, path: n.path)
        notes[idx] = updated
        try? XattrMetadata.write(NoteXattr(categoryID: categoryID, createdAt: n.createdAt),
                                 to: n.path)
        try? indexService.update(note: updated, body: "")
    }

    // MARK: - Delete note

    @MainActor
    func deleteNote(id: UUID) {
        guard let idx = notes.firstIndex(where: { $0.id == id }) else { return }
        let note = notes[idx]

        // Cancel any pending debounced save so it can't resurrect the file.
        if selectedNoteID == id {
            editorViewModel?.discardPendingChanges()
            selectedNoteID = nil
        }

        do { try noteStore.moveToTrash(note: note) }
        catch { Logger.storage.error("deleteNote: moveToTrash failed: \(error)") }

        do { try imageStore.garbageCollect(noteUUID: id, liveReferences: []) }
        catch { Logger.storage.error("deleteNote: image GC failed: \(error)") }

        do { try recoveryJournal.deleteWAL(for: id) }
        catch { Logger.storage.error("deleteNote: WAL delete failed: \(error)") }

        do { try indexService.delete(noteID: id) }
        catch { Logger.index.error("deleteNote: index delete failed: \(error)") }

        notes.remove(at: idx)
        Logger.app.info("Deleted note \(id)")
    }

    // MARK: - Filtered notes (sidebar)

    var filteredNotes: [NoteItem] {
        notes.filter { note in
            let matchesSearch = searchText.isEmpty ||
                note.title.localizedCaseInsensitiveContains(searchText)
            let matchesCategory = selectedCategoryID == nil ||
                note.categoryID == selectedCategoryID
            return matchesSearch && matchesCategory
        }
    }

    // MARK: - Index reconciliation

    /// Re-scan `~/.notes/`, reindex stale files, and refresh the sidebar list.
    @MainActor
    func reconcileIndex() {
        Logger.index.debug("reconcileIndex started")
        do {
            let urls = try noteStore.allNoteURLs()
            for url in urls {
                let lang = NoteLanguage.infer(from: url)
                let rv = try? url.resourceValues(
                    forKeys: [.creationDateKey, .contentModificationDateKey])
                let created  = rv?.creationDate ?? Date()
                let modified = rv?.contentModificationDate ?? Date()
                let stem = url.deletingPathExtension().lastPathComponent
                guard let id = UUID(uuidString: stem) else { continue }
                let candidate = NoteItem(id: id, title: "", language: lang, categoryID: nil,
                                         createdAt: created, modifiedAt: modified, path: url)
                if indexService.needsReindex(note: candidate) {
                    let content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                    let title   = NoteItem.titleFromContent(content)
                    let xattr   = try? XattrMetadata.read(from: url)
                    let indexed = NoteItem(id: id, title: title, language: lang,
                                          categoryID: xattr?.categoryID,
                                          createdAt: created, modifiedAt: modified, path: url)
                    try? indexService.insert(note: indexed, body: content)
                }
            }
            notes = (try indexService.fetchAll())
        } catch {
            Logger.index.error("reconcileIndex failed: \(error)")
        }
    }

    // MARK: - State persistence

    func saveState(cursorLocation: Int = 0) {
        let state = AppState(
            lastOpenNoteID: selectedNoteID,
            draftText: draftBuffer.isActive ? draftBuffer.text : "",
            windowFrame: nil,
            cursorLocation: cursorLocation
        )
        do {
            try state.save()
            Logger.app.debug("AppState saved")
        } catch {
            Logger.app.error("AppState save failed: \(error)")
        }
    }
}
