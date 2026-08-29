import SwiftUI

/// Adds Find (Edit menu) and Zoom (View menu) commands to the menu bar.
///
/// `Find…`/`Search All Notes` can't reach the toolbar field or sidebar box
/// directly — `Commands` can't use `@Environment`/`@FocusState` — so they
/// post through the same `NotificationCenter` channel `DeleteNoteCommands`
/// already uses (`MacNoteApp.swift`). `Find Next`/`Find Previous` call
/// straight into `FindSession`.
struct FindMenuCommands: Commands {

    @ObservedObject var findSession: FindSessionBox

    var body: some Commands {
        CommandGroup(after: .textEditing) {
            Button("Find\u{2026}") {
                NotificationCenter.default.post(name: .focusNoteFind, object: nil)
            }
            .keyboardShortcut("f", modifiers: .command)

            Button("Find Next") {
                findSession.session.next()
            }
            .keyboardShortcut("g", modifiers: .command)
            .disabled(findSession.session.matches.isEmpty)

            Button("Find Previous") {
                findSession.session.previous()
            }
            .keyboardShortcut("g", modifiers: [.command, .shift])
            .disabled(findSession.session.matches.isEmpty)

            Divider()

            Button("Search All Notes") {
                NotificationCenter.default.post(name: .focusNoteSearch, object: nil)
            }
            .keyboardShortcut("f", modifiers: [.command, .option])
        }
    }
}

// MARK: - FindSessionBox

/// Thin ObservableObject wrapper so Commands (which can't use @Environment)
/// can hold a reference to the @Observable FindSession and trigger re-renders.
/// Mirrors `AppModelBox` in `FormatMenuCommands.swift`.
final class FindSessionBox: ObservableObject {
    let session: FindSession
    init(_ session: FindSession) { self.session = session }
}

// MARK: - ViewMenuCommands

/// Font-zoom commands, injected into SwiftUI's existing View menu (after the
/// sidebar-toggle group). `CommandMenu("View")` would create a duplicate
/// second View menu instead.
struct ViewMenuCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Divider()

            Button("Zoom In") {
                EditorSettings.shared.zoomIn()
            }
            .keyboardShortcut("=", modifiers: .command)

            Button("Zoom Out") {
                EditorSettings.shared.zoomOut()
            }
            .keyboardShortcut("-", modifiers: .command)

            Button("Actual Size") {
                EditorSettings.shared.resetZoom()
            }
            .keyboardShortcut("0", modifiers: .command)
        }
    }
}
