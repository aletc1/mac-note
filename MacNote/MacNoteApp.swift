import SwiftUI
import AppKit
import os

@main
struct MacNoteApp: App {

    // MARK: - App-wide state

    @State private var appModel = AppModel()
    @State private var editorVMBox = EditorViewModelBox(EditorViewModel())

    // MARK: - Scene

    var body: some Scene {
        WindowGroup {
            ContentView(appModel: appModel, editorVMBox: editorVMBox)
                .onAppear {
                    appModel.startup()
                    // Wire storage dependencies into the editor view model
                    editorVMBox.vm.noteStore    = appModel.noteStore
                    editorVMBox.vm.indexService = appModel.indexService
                    // Give AppModel a weak handle so deleteNote can cancel pending saves.
                    appModel.editorViewModel = editorVMBox.vm
                }
                .onDisappear {
                    Task {
                        await editorVMBox.vm.saveNow()
                        appModel.saveState()
                        appModel.fileWatcher.stop()
                    }
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            FormatMenuCommands(appModel: AppModelBox(appModel))
            DeleteNoteCommands(appModel: AppModelBox(appModel))
        }
    }
}

// MARK: - ContentView

/// Root layout: sidebar | detail.
struct ContentView: View {
    var appModel: AppModel
    @ObservedObject var editorVMBox: EditorViewModelBox

    var body: some View {
        NavigationSplitView {
            SidebarView(appModel: appModel)
        } detail: {
            DetailView(appModel: appModel, editorVMBox: editorVMBox)
        }
        .navigationSplitViewStyle(.balanced)
        .environment(appModel)
    }
}

// MARK: - SidebarView

struct SidebarView: View {
    var appModel: AppModel
    @State private var showCategoryEditor = false
    @State private var pendingDeleteID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search", text: Bindable(appModel).searchText)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Category filter
            SidebarCategoryFilter()

            Divider()

            // Date-grouped note list
            SidebarNoteList()

            Divider()

            // Bottom toolbar
            HStack {
                Button {
                    appModel.startNewNote()
                } label: {
                    Label("New Note", systemImage: "square.and.pencil")
                }
                .buttonStyle(.borderless)
                .keyboardShortcut("n", modifiers: .command)
                Spacer()
                Button {
                    showCategoryEditor = true
                } label: {
                    Label("Categories", systemImage: "tag")
                }
                .buttonStyle(.borderless)
            }
            .padding(8)
        }
        .frame(minWidth: 220)
        .sheet(isPresented: $showCategoryEditor) {
            CategoryEditorSheet()
                .environment(appModel)
        }
        .alert("Delete this note?",
               isPresented: Binding(
                   get: { pendingDeleteID != nil },
                   set: { if !$0 { pendingDeleteID = nil } }
               )) {
            Button("Delete", role: .destructive) {
                if let id = pendingDeleteID { appModel.deleteNote(id: id) }
                pendingDeleteID = nil
            }
            Button("Cancel", role: .cancel) { pendingDeleteID = nil }
        } message: {
            Text("The note and its images will be moved to ~/.notes/.trash/.")
        }
        .onReceive(NotificationCenter.default.publisher(for: .requestDeleteNote)) { note in
            if let id = note.object as? UUID { pendingDeleteID = id }
        }
    }
}

// MARK: - DeleteNoteCommands

struct DeleteNoteCommands: Commands {
    @ObservedObject var appModel: AppModelBox

    var body: some Commands {
        CommandGroup(after: .pasteboard) {
            Button("Delete Note\u{2026}") {
                if let id = appModel.model.selectedNoteID {
                    NotificationCenter.default.post(name: .requestDeleteNote, object: id)
                }
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(appModel.model.selectedNoteID == nil)
        }
    }
}

extension Notification.Name {
    static let requestDeleteNote = Notification.Name("MacNote.requestDeleteNote")
}

// MARK: - DetailView

struct DetailView: View {
    var appModel: AppModel
    @ObservedObject var editorVMBox: EditorViewModelBox
    @State private var showCopiedToast = false

    var body: some View {
        Group {
            if let selectedID = appModel.selectedNoteID,
               let note = appModel.notes.first(where: { $0.id == selectedID }) {
                EditorPane(
                    note: note,
                    draftText: .constant(""),
                    isDraft: false,
                    viewModel: editorVMBox,
                    notesDirectory: appModel.noteStore.notesDirectory
                )
                .id(note.id)   // force view recreation on note switch
            } else if appModel.draftBuffer.isActive {
                EditorPane(
                    note: nil,
                    draftText: Bindable(appModel.draftBuffer).text,
                    isDraft: true,
                    viewModel: editorVMBox,
                    notesDirectory: appModel.noteStore.notesDirectory
                )
            } else {
                EmptyDetailView()
            }
        }
        .frame(minWidth: 400)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                copyButton
            }
        }
        .overlay(alignment: .topTrailing) {
            copiedToast
        }
    }

    private var copyButton: some View {
        Button {
            copyCurrentNote()
        } label: {
            Label("Copy Note", systemImage: "doc.on.doc")
        }
        .help("Copy Note")
        .disabled(!canCopy)
    }

    private var canCopy: Bool {
        if appModel.draftBuffer.isActive {
            return !appModel.draftBuffer.text.isEmpty
        }
        return appModel.selectedNoteID != nil
    }

    @ViewBuilder
    private var copiedToast: some View {
        if showCopiedToast {
            Label("Copied", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: Capsule())
                .padding(.top, 12)
                .padding(.trailing, 16)
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private var copyableContent: String {
        if appModel.draftBuffer.isActive {
            return appModel.draftBuffer.text
        }
        guard appModel.selectedNoteID != nil else { return "" }
        return editorVMBox.vm.loadedContent
    }

    private func copyCurrentNote() {
        NoteClipboardExporter(notesDirectory: appModel.noteStore.notesDirectory)
            .copy(markdown: copyableContent)
        withAnimation(.easeOut(duration: 0.15)) {
            showCopiedToast = true
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            withAnimation(.easeIn(duration: 0.2)) {
                showCopiedToast = false
            }
        }
    }
}

// MARK: - EmptyDetailView

struct EmptyDetailView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "note.text")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("Select or create a note")
                .foregroundStyle(.secondary)
            Text("Command-N to create a new note")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
