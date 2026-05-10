import SwiftUI

/// Adds a "Format" menu to the menu bar.
/// Each item calls `AppModel.changeLanguage(to:)` for the currently-selected note.
struct FormatMenuCommands: Commands {

    @ObservedObject var appModel: AppModelBox

    var body: some Commands {
        CommandMenu("Format") {
            Section("Language") {
                ForEach(NoteLanguage.allCases, id: \.self) { language in
                    Button {
                        appModel.model.changeLanguage(to: language)
                    } label: {
                        // SwiftUI Commands don't support .badge; use a label
                        // with a checkmark prefix to indicate the active language.
                        if isSelected(language) {
                            Label(language.displayName, systemImage: "checkmark")
                        } else {
                            Text(language.displayName)
                        }
                    }
                }
            }
        }
    }

    private func isSelected(_ language: NoteLanguage) -> Bool {
        guard let id = appModel.model.selectedNoteID,
              let note = appModel.model.notes.first(where: { $0.id == id })
        else { return false }
        return note.language == language
    }
}

// MARK: - AppModelBox

/// Thin ObservableObject wrapper so Commands (which can't use @Environment)
/// can hold a reference to the @Observable AppModel and trigger re-renders.
final class AppModelBox: ObservableObject {
    let model: AppModel
    init(_ model: AppModel) { self.model = model }
}

