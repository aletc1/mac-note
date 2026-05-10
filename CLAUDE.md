# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Rules

- Don't assume. Don't hide confusion. Surface tradeoffs.
- Minimum code that solves the problem. Nothing speculative.
- Touch only what you must. Clean up only your own mess.
- Define success criteria. Loop until verified.

## Commands

**Type-check all app sources** (fast, no Xcode needed):
```
swiftc -typecheck -sdk $(xcrun --show-sdk-path --sdk macosx) \
  -target arm64-apple-macosx14.0 \
  $(find MacNote -name "*.swift" | sort)
```

**Build** (Xcode is the primary build system):
```
open MacNote.xcodeproj          # then ⌘B
```
Or from the terminal:
```
xcodebuild -project MacNote.xcodeproj -scheme MacNote \
  -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

**Run all tests:**
```
xcodebuild test -project MacNote.xcodeproj -scheme MacNote \
  CODE_SIGNING_ALLOWED=NO
```

**Run a single test class** (e.g. `NoteStoreTests`):
```
xcodebuild test -project MacNote.xcodeproj -scheme MacNote \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:MacNoteTests/NoteStoreTests
```

**Run a single test method:**
```
xcodebuild test -project MacNote.xcodeproj -scheme MacNote \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:MacNoteTests/NoteStoreTests/testCreateAndRead
```

**Validate the Xcode project file:**
```
plutil -lint MacNote.xcodeproj/project.pbxproj
```

> Note: On this machine `xcodebuild` has a plugin-load issue (`DVTDownloads.framework` mismatch with Xcode 26 beta). Use `swiftc -typecheck` to verify compilation and open in the Xcode IDE for running/testing.

## Architecture

The app is **library-shaped, not document-shaped** — it owns its own storage and does not use `NSDocument`.

### Data flow

```
~/.notes/{uuid}.{ext}           ← source of truth (plain text files)
    ↕  atomic write + WAL
NoteStore                       ← CRUD layer (sync throws; async wrapper for editor)
    ↓  on save
IndexService (SQLite FTS5)      ← rebuildable mirror; drives sidebar list + search
    ↑  on launch / FSEvents
FileWatcher (FSEvents)          ← detects external changes → triggers reconcile
```

Notes are identified by UUID filename; the display title is derived at runtime from the first non-blank line via `NoteItem.titleFromContent(_:)`. The file extension encodes the language (`md`, `json`, `swift`, …).

### Key classes and their roles

| Class | File | Role |
|---|---|---|
| `AppModel` | `AppModel.swift` | `@Observable` root state. Owns all services. Entry point for note CRUD, language change, sidebar filtering. |
| `EditorViewModel` | `Editor/EditorViewModel.swift` | Per-note save lifecycle: `markDirty` → WAL append + debounce → `saveNow` (atomic write) → WAL truncate → index update. |
| `MacNoteTextView` | `Editor/MacNoteTextView.swift` | `NSTextView` subclass. Handles paste, image drag-drop, and image-aware cursor movement. |
| `EditorPane` | `Editor/EditorPane.swift` | `NSViewRepresentable` wrapping `MacNoteTextView`. Coordinator bridges `NSTextViewDelegate` into `EditorViewModel`. |
| `NoteStore` | `Storage/NoteStore.swift` | `~/.notes/` CRUD. `write(content:to:)` is synchronous+throws; `writeAsync` is the detached-task wrapper used by the editor. Accepts an injectable directory for tests. |
| `RecoveryJournal` | `Storage/RecoveryJournal.swift` | Per-note WAL. Appends newline-delimited JSON entries with `O_APPEND|O_SYNC`; `append` loops on partial `write(2)` to handle EINTR. Entries replayed and applied sequentially in `EditorViewModel.load`. |
| `IndexService` | `Storage/IndexService.swift` | Raw SQLite3 (GRDB stubbed, see TODOs). FTS5 virtual table. All methods gated on a private serial `DispatchQueue` (replaces `SQLITE_OPEN_FULLMUTEX` until GRDB migration). `needsReindex` compares file mtime to DB `modified_at`. |
| `ImageStore` | `Storage/ImageStore.swift` | Content-addressed image storage (`{noteUUID}-{sha256prefix8}.{ext}`). `garbageCollect` moves orphans to `.trash/`. |
| `DraftBuffer` | `Models/DraftBuffer.swift` | Holds "new note" text before any file is created. `promote(to:)` marks it inactive when the first keystroke triggers file creation. |

### Autosave path (critical flow)

Every text change goes:
1. `NSTextViewDelegate.shouldChangeTextIn` → `EditorViewModel.markDirty(in:with:)` — records the delta
2. `NSTextViewDelegate.textDidChange` → `EditorViewModel.markDirty(in:with:)` — records full-content snapshot (range covers entire string)
3. `RecoveryJournal.append(entry:for:)` — O_SYNC write per step above (crash-safe; write loop handles partial writes)
4. `Debouncer` fires after 1.5 s idle → `EditorViewModel.saveNow()`
5. `saveNow` snapshots `currentContent` before the `await`; clears `isDirty` only after the write if content didn't change during the suspension; restores `isDirty` on failure
6. `NoteStore.writeAsync` runs off-main: temp file → `replaceItemAt` (atomic)
7. `RecoveryJournal.truncate(for:)` — WAL zeroed after successful save; truncate errors are logged but non-fatal
8. `IndexService.update(note:body:)` — title + FTS index refreshed

On note load (`EditorViewModel.load`), WAL entries are replayed in order and applied to the on-disk content, recovering any unsaved edits since the last successful write. On launch, `AppModel.startup()` calls `RecoveryJournal.pendingNoteIDs()` to identify notes with pending WAL entries.

### SwiftUI ↔ AppKit boundary

`EditorPane` (SwiftUI) wraps `MacNoteTextView` (AppKit) via `NSViewRepresentable`. The coordinator holds a weak reference to `EditorViewModel` and a `@Binding` to `DraftBuffer.text`. `EditorViewModel` is held in `EditorViewModelBox: ObservableObject` so SwiftUI can observe it without the `@Observable` macro (which doesn't compose with `NSViewRepresentable` coordinators cleanly).

### Testing conventions

All storage classes accept injectable URLs in their initializers (`notesDirectory:`, `supportDirectory:`, `recoveryDirectory:`) so tests run in a `FileManager.temporaryDirectory` sandbox that is torn down in `tearDownWithError`. The app's default directories are encoded as static `default*` properties (e.g. `NoteStore.defaultNotesDirectory`).

### SPM dependencies (not yet wired)

All dependency call-sites are marked `// TODO: wire SPM dep`. The stubs keep the project compilable without resolving packages.

| Package | Replaces |
|---|---|
| `ChimeHQ/Neon` + `SwiftTreeSitter` | `HighlighterController` stub |
| `groue/GRDB.swift` | Raw `SQLite3` in `IndexService` |
| `steipete/Demark` | HTML→Markdown stub in `PasteHandler` |

### Adding a new file to the Xcode project

`project.pbxproj` is maintained by hand (no xcodegen). To add a file:
1. Generate a UUID pair: `python3 -c "import uuid; print(uuid.uuid4().hex[:24].upper())"` (run twice — one for `PBXFileReference`, one for `PBXBuildFile`).
2. Add `PBXFileReference` entry, `PBXBuildFile` entry, the file to the correct `PBXGroup`, and the build file to the appropriate `PBXSourcesBuildPhase`.
3. Run `plutil -lint MacNote.xcodeproj/project.pbxproj` to verify.
