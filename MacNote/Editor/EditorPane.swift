import SwiftUI
import AppKit
import os

/// SwiftUI wrapper around `MacNoteTextView`.
/// - Presents the text view inside a scroll view.
/// - Coordinator bridges `NSTextViewDelegate` callbacks into the view model.
/// - Re-loads content whenever `note` binding changes.
struct EditorPane: NSViewRepresentable {

    // MARK: - Bindings / observed state

    let note: NoteItem?
    @ObservedObject var viewModel: EditorViewModelBox
    var notesDirectory: URL = NoteStore.defaultNotesDirectory

    // MARK: - NSViewRepresentable

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel.vm)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = MacNoteTextView()
        textView.commonSetup()
        textView.delegate = context.coordinator
        textView.highlighterController = HighlighterController()
        textView.imageRenderer = ImageRenderer()
        textView.notesDirectory = notesDirectory

        context.coordinator.textView = textView

        let contentSize = scrollView.contentSize
        textView.minSize = NSSize(width: 0, height: contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                   height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: contentSize.width,
                                                       height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? MacNoteTextView else { return }
        let coordinator = context.coordinator

        if let note {
            if coordinator.loadedNoteID != note.id {
                coordinator.loadedNoteID = note.id
                coordinator.loadedLanguage = note.language
                Task { @MainActor in
                    await viewModel.vm.load(note: note)
                    let content = viewModel.vm.contentSnapshot
                    textView.currentNoteID = note.id
                    textView.loadMarkdown(content)
                    textView.highlighterController?.configure(for: note.language, textView: textView)
                    // `load` runs off-main during WAL replay, so the callback isn't fired
                    // from there. Notify here on the main actor instead.
                    viewModel.vm.onContentChanged?(!content.isEmpty)
                    Logger.editor.debug("EditorPane: loaded note '\(note.title)'")
                }
            } else if coordinator.loadedLanguage != note.language {
                coordinator.loadedLanguage = note.language
                textView.highlighterController?.configure(for: note.language, textView: textView)
            }
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {

        let vm: EditorViewModel
        weak var textView: MacNoteTextView?
        var loadedNoteID: UUID?
        var loadedLanguage: NoteLanguage?

        init(viewModel: EditorViewModel) {
            self.vm = viewModel
        }

        // MARK: NSTextViewDelegate

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            let content = (tv as? MacNoteTextView)?.markdownContent ?? tv.string
            vm.updateContent(content)
            let range = NSRange(location: 0, length: (content as NSString).length)
            vm.markDirty(in: range, with: content)
            (tv as? MacNoteTextView)?.highlighterController?.invalidateAll()
        }

        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            if let replacement = replacementString {
                vm.markDirty(in: affectedCharRange, with: replacement)
            }
            return true
        }

        // Reset typing attributes after cursor moves so the monospaced font is always active.
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = notification.object as? MacNoteTextView else { return }
            tv.typingAttributes = [.font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)]
        }
    }
}

// MARK: - EditorViewModelBox

final class EditorViewModelBox: ObservableObject {
    let vm: EditorViewModel
    init(_ vm: EditorViewModel) { self.vm = vm }
}
