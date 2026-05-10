# MacNote

A fast, plain-text-only note app for macOS.

## Core constraints

- **Trustworthy persistence** — writes are atomic; no data loss on crash.
- **Fast cold-open** — app is interactive in under 200ms.
- **Fast autosave at scale** — autosave stays cheap as the note count grows.
- **Native macOS** — AppKit, no cross-platform abstractions.

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 15 or later

## Run

Open the project in Xcode and press **⌘R**:

```
open MacNote.xcodeproj
```

Or build and run from the terminal:

```
xcodebuild -project MacNote.xcodeproj -scheme MacNote -configuration Debug \
  CODE_SIGNING_ALLOWED=NO build
```

The built app ends up in `~/Library/Developer/Xcode/DerivedData/MacNote-*/Build/Products/Debug/MacNote.app`. Open it with:

```
open ~/Library/Developer/Xcode/DerivedData/MacNote-*/Build/Products/Debug/MacNote.app
```

## Tests

Run all tests from Xcode with **⌘U**, or from the terminal:

```
xcodebuild test -project MacNote.xcodeproj -scheme MacNote \
  CODE_SIGNING_ALLOWED=NO
```

## Data layout

| What | Where |
|------|-------|
| Notes | `~/.notes/{uuid}.{ext}` |
| Inline images | `~/.notes/{note-uuid}-{hash8}.{ext}` |
| Deleted images | `~/.notes/.trash/` |
| Index | `~/Library/Application Support/MacNote/index.sqlite` |
| Crash recovery WAL | `~/Library/Application Support/MacNote/recovery/{uuid}.wal` |
| Window/cursor state | `~/.notes/state.json` |

To rebuild the index from scratch, delete `index.sqlite` and relaunch — the app re-indexes all files in `~/.notes/` on startup.
