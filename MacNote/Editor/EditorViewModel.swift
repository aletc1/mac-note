import Foundation
import os

// RecoveryJournal lives in MacNote/Storage/RecoveryJournal.swift.
// NoteStore      lives in MacNote/Storage/NoteStore.swift.
// IndexService   lives in MacNote/Storage/IndexService.swift.

// MARK: - EditorViewModel

/// Manages the save lifecycle for whichever note is currently open.
///
/// Flow:
///   textDidChange → markDirty → WAL append + debounced saveNow
///   saveNow       → atomic write via NoteStore → WAL truncate → index update
final class EditorViewModel {

    // MARK: - Observed state (read by coordinator / views)

    private(set) var currentNoteID: UUID?
    private(set) var isDirty: Bool = false

    // MARK: - Dependencies (injected by AppModel / coordinator)

    /// Set by the coordinator after AppModel is available.
    var noteStore: NoteStore?
    var indexService: IndexService?

    // MARK: - Private

    private let journal = RecoveryJournal()
    private let saveDebouncer: Debouncer

    /// Content snapshot kept in sync with the text view (used by saveNow).
    private var currentContent: String = ""
    /// NoteItem currently loaded (needed for atomic write path).
    private var currentNote: NoteItem?

    // MARK: - Init

    init(saveDelay: TimeInterval = 1.5) {
        saveDebouncer = Debouncer(delay: saveDelay)
    }

    // MARK: - API

    /// Called by the NSTextView coordinator on every text-change notification.
    func markDirty(in range: NSRange, with replacementString: String) {
        isDirty = true
        if let noteID = currentNoteID {
            let entry = RecoveryJournal.Entry(
                range: range, replacement: replacementString, timestamp: Date())
            try? journal.append(entry: entry, for: noteID)
        }
        saveDebouncer.schedule { [weak self] in
            guard let self else { return }
            Task { await self.saveNow() }
        }
    }

    /// Flush current content to disk immediately.
    func saveNow() async {
        guard let note = currentNote, isDirty else { return }
        // Snapshot content before the await so we can detect edits that arrive
        // during the write and avoid clobbering the dirty flag for those edits.
        let snapshot = currentContent
        Logger.storage.debug("EditorViewModel.saveNow() — note \(note.id)")
        do {
            guard let store = noteStore else { return }
            try await store.writeAsync(content: snapshot, to: note)
            do {
                try journal.truncate(for: note.id)
            } catch {
                Logger.storage.error("WAL truncate failed for note \(note.id): \(error)")
            }
            // Only clear the dirty flag if no new edits arrived during the write.
            if currentContent == snapshot { isDirty = false }

            let title = NoteItem.titleFromContent(snapshot)
            let updated = NoteItem(
                id: note.id, title: title, language: note.language,
                categoryID: note.categoryID, createdAt: note.createdAt,
                modifiedAt: Date(), path: note.path)
            currentNote = updated
            try? indexService?.update(note: updated, body: snapshot)
            Logger.storage.info("Saved note \(note.id) — title: \(title)")
        } catch {
            Logger.storage.error("saveNow failed for note \(note.id): \(error)")
        }
    }

    /// Keep `currentContent` in sync so `saveNow` always has the latest.
    func updateContent(_ content: String) {
        currentContent = content
    }

    /// Switch the editor to a different note.
    /// Flushes any pending save for the current note first, then loads the new one.
    func load(note: NoteItem) async {
        // Flush outstanding work for the previous note
        saveDebouncer.cancel()
        if isDirty { await saveNow() }

        currentNote   = note
        currentNoteID = note.id
        isDirty       = false

        Logger.editor.debug("EditorViewModel.load — \(note.id) '\(note.title)'")

        let content = (try? noteStore?.readContent(of: note)) ?? ""
        // Replay crash-recovery WAL on a background thread (avoids blocking main on large WALs).
        let noteID = note.id
        let j = journal
        let walEntries = await Task.detached { (try? j.replay(for: noteID)) ?? [] }.value
        var recovered = content
        if !walEntries.isEmpty {
            Logger.storage.warning("Replaying \(walEntries.count) WAL entr(ies) for \(noteID)")
            var ns = recovered as NSString
            for entry in walEntries {
                let safeLocation = min(entry.range.location, ns.length)
                let safeLength   = min(entry.range.length, ns.length - safeLocation)
                ns = ns.replacingCharacters(
                    in: NSRange(location: safeLocation, length: safeLength),
                    with: entry.replacement) as NSString
            }
            recovered = ns as String
        }
        currentContent = recovered
    }

    /// Text to hand off to the text view after `load(note:)` completes.
    var loadedContent: String { currentContent }

    /// Cancel pending saves (e.g. on window close after an explicit save).
    func cancelPendingSave() {
        saveDebouncer.cancel()
    }
}
