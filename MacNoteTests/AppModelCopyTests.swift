import XCTest
@testable import MacNote

@MainActor
final class AppModelCopyTests: XCTestCase {
    var tmpNotes: URL!
    var tmpIndex: URL!
    var tmpRecovery: URL!
    var appModel: AppModel!
    var editorVM: EditorViewModel!

    override func setUpWithError() throws {
        tmpNotes    = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        tmpIndex    = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        tmpRecovery = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        for dir in [tmpNotes!, tmpIndex!, tmpRecovery!] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        appModel = AppModel(
            notesDirectory: tmpNotes,
            indexSupportDirectory: tmpIndex,
            recoveryDirectory: tmpRecovery
        )
        try appModel.indexService.setup()

        // Mirror the wiring done by MacNoteApp.onAppear so the editor → AppModel
        // callback is in place for the tests that exercise it.
        editorVM = EditorViewModel()
        editorVM.noteStore = appModel.noteStore
        editorVM.indexService = appModel.indexService
        appModel.editorViewModel = editorVM
        editorVM.onContentChanged = { [weak appModel] hasContent in
            appModel?.editorHasContent = hasContent
        }
    }

    override func tearDownWithError() throws {
        for dir in [tmpNotes, tmpIndex, tmpRecovery] {
            try? FileManager.default.removeItem(at: dir!)
        }
    }

    // MARK: - canCopyCurrentNote

    func testCanCopyFalseWhenNoSelection() {
        XCTAssertNil(appModel.selectedNoteID)
        appModel.editorHasContent = true
        XCTAssertFalse(appModel.canCopyCurrentNote,
                       "Selection is required even when editor reports content")
    }

    func testCanCopyFalseWhenSelectedButEmpty() {
        let note = appModel.createNote(language: .markdown)
        appModel.selectedNoteID = note.id
        appModel.editorHasContent = false
        XCTAssertFalse(appModel.canCopyCurrentNote)
    }

    func testCanCopyTrueWhenSelectedAndHasContent() {
        let note = appModel.createNote(language: .markdown)
        appModel.selectedNoteID = note.id
        appModel.editorHasContent = true
        XCTAssertTrue(appModel.canCopyCurrentNote)
    }

    // MARK: - editorHasContent reactivity

    func testEditorCallbackUpdatesEditorHasContentOnUpdate() {
        XCTAssertFalse(appModel.editorHasContent)

        editorVM.updateContent("hello")
        XCTAssertTrue(appModel.editorHasContent,
                      "updateContent with non-empty string flips editorHasContent on")

        editorVM.updateContent("")
        XCTAssertFalse(appModel.editorHasContent,
                       "updateContent with empty string flips editorHasContent off")
    }

    func testDiscardPendingChangesClearsEditorHasContent() {
        editorVM.updateContent("hello")
        XCTAssertTrue(appModel.editorHasContent)

        editorVM.discardPendingChanges()
        XCTAssertFalse(appModel.editorHasContent,
                       "discardPendingChanges should reset editorHasContent")
    }

    // MARK: - copyCurrentNote

    func testCopyCurrentNoteIsNoopWhenCannotCopy() {
        // No selection, editorHasContent stays false → canCopy is false
        appModel.copyCurrentNote()
        XCTAssertFalse(appModel.isShowingCopyToast,
                       "Toast should not appear when copy is gated off")
    }

    func testCopyCurrentNoteShowsToastWhenCanCopy() {
        let note = appModel.createNote(language: .markdown)
        appModel.selectedNoteID = note.id
        editorVM.updateContent("payload")

        XCTAssertTrue(appModel.canCopyCurrentNote)
        appModel.copyCurrentNote()
        XCTAssertTrue(appModel.isShowingCopyToast,
                      "Toast should be visible immediately after a successful copy")
    }

    func testRapidSuccessiveCopiesKeepToastVisible() {
        let note = appModel.createNote(language: .markdown)
        appModel.selectedNoteID = note.id
        editorVM.updateContent("payload")

        appModel.copyCurrentNote()
        XCTAssertTrue(appModel.isShowingCopyToast)

        // Second copy before the 1.5s timeout — toast must remain visible and the
        // generation counter advances so the *first* hide-task no-ops.
        appModel.copyCurrentNote()
        XCTAssertTrue(appModel.isShowingCopyToast,
                      "Rapid second copy must keep the toast on screen")
    }
}
