import AppKit

/// Single source of truth for the editor's font size ("zoom").
///
/// Persisted to `UserDefaults` — not `AppState` (`Models/AppState.swift`),
/// which is session-restore state written only on quit. A view preference
/// like this needs an immediate write.
///
/// `@Observable` so SwiftUI (the toolbar zoom popover) updates automatically.
/// AppKit code that can't observe `@Observable` (`MacNoteTextView`,
/// `HighlighterController`) reacts instead to the `.editorFontSizeChanged`
/// notification posted on every change.
@Observable
final class EditorSettings {

    static let shared = EditorSettings()

    static let minSize: CGFloat = 9
    static let maxSize: CGFloat = 32
    static let defaultSize: CGFloat = 14

    private static let defaultsKey = "editorFontSize"

    private(set) var fontSize: CGFloat

    init() {
        let stored = UserDefaults.standard.object(forKey: Self.defaultsKey) as? Double
        fontSize = Self.clamp(CGFloat(stored ?? Double(Self.defaultSize)))
    }

    // MARK: - Fonts derived from the current size

    var regularFont: NSFont { .monospacedSystemFont(ofSize: fontSize, weight: .regular) }
    var boldFont: NSFont { .monospacedSystemFont(ofSize: fontSize, weight: .bold) }
    var defaultAttrs: [NSAttributedString.Key: Any] { [.font: regularFont] }

    // MARK: - Mutation

    func setFontSize(_ newValue: CGFloat) {
        let clamped = Self.clamp(newValue)
        guard clamped != fontSize else { return }
        fontSize = clamped
        UserDefaults.standard.set(Double(fontSize), forKey: Self.defaultsKey)
        NotificationCenter.default.post(name: .editorFontSizeChanged, object: nil)
    }

    func zoomIn() { setFontSize(fontSize + 1) }
    func zoomOut() { setFontSize(fontSize - 1) }
    func resetZoom() { setFontSize(Self.defaultSize) }

    private static func clamp(_ value: CGFloat) -> CGFloat {
        min(max(value, minSize), maxSize)
    }
}

extension Notification.Name {
    static let editorFontSizeChanged = Notification.Name("MacNote.editorFontSizeChanged")
}
