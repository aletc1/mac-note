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
    var findSession: FindSession
    var notesDirectory: URL = NoteStore.defaultNotesDirectory

    // MARK: - NSViewRepresentable

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel.vm, findSession: findSession)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        // Bottom breathing room past the last line: without it the caret sits
        // right at the container edge and every new line at the end of a long
        // note forces a visible scroll jump. `textContainerInset` can't do this
        // alone — it's a symmetric NSSize, so raising it also pads the top.
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 240, right: 0)

        let textView = MacNoteTextView()
        textView.commonSetup()
        textView.delegate = context.coordinator
        textView.highlighterController = HighlighterController()
        textView.imageRenderer = ImageRenderer()
        textView.notesDirectory = notesDirectory

        context.coordinator.textView = textView
        // `.id(note.id)` on DetailView forces this whole representable to be
        // rebuilt on every note switch, so this runs once per open note —
        // reset any highlights left over from the previous note before
        // pointing findSession at the new text view.
        findSession.clear()
        findSession.textView = textView

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
        let findSession: FindSession
        weak var textView: MacNoteTextView?
        var loadedNoteID: UUID?
        var loadedLanguage: NoteLanguage?

        init(viewModel: EditorViewModel, findSession: FindSession) {
            self.vm = viewModel
            self.findSession = findSession
        }

        // MARK: NSTextViewDelegate

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            let content = (tv as? MacNoteTextView)?.markdownContent ?? tv.string
            vm.updateContent(content)
            let range = NSRange(location: 0, length: (content as NSString).length)
            vm.markDirty(in: range, with: content)
            (tv as? MacNoteTextView)?.highlighterController?.invalidateAll()
            findSession.noteContentDidChange()
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
            tv.typingAttributes = EditorSettings.shared.defaultAttrs
        }
    }
}

// MARK: - EditorViewModelBox

final class EditorViewModelBox: ObservableObject {
    let vm: EditorViewModel
    init(_ vm: EditorViewModel) { self.vm = vm }
}
